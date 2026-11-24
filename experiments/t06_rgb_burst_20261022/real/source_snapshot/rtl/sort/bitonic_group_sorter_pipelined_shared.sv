// Spatial Bitonic BSU: fixed wiring and K/2 concurrent CAS per registered
// layer. Two input group banks and elastic layers overlap collect/sort/emit.
// The first CAS genuinely uses G of the shared PE; its response slot is
// reserved BEFORE issuing, preventing a G -> downstream P/R -> PE deadlock.
module bitonic_group_sorter_pipelined_shared #(
    parameter int unsigned CAPACITY=8,DEPTH_W=27,GID_W=32,SEQ_W=16,
    parameter int unsigned GROUP_W=2,PAYLOAD_W=1,PE_DATA_W=32,
    parameter int unsigned COMPARE_LANES=4,
    parameter int unsigned COUNT_W=$clog2(CAPACITY+1),LANE_W=$clog2(COMPARE_LANES+1)
)(
    input logic clk_i,rst_ni,clear_overflow_i,input logic[LANE_W-1:0]cfg_active_lanes_i,
    input logic s_valid_i,output logic s_ready_o,input logic s_empty_i,
    input logic signed[DEPTH_W-1:0]s_depth_i,input logic[GID_W-1:0]s_gid_i,
    input logic[SEQ_W-1:0]s_seq_i,input logic[GROUP_W-1:0]s_group_i,
    input logic[PAYLOAD_W-1:0]s_payload_i,input logic s_group_last_i,
    output logic m_valid_o,input logic m_ready_i,
    output logic signed[DEPTH_W-1:0]m_depth_o,output logic[GID_W-1:0]m_gid_o,
    output logic[SEQ_W-1:0]m_seq_o,output logic[GROUP_W-1:0]m_group_o,
    output logic[PAYLOAD_W-1:0]m_payload_o,output logic m_group_first_o,m_group_last_o,
    output logic overflow_o,busy_o,subset_done_o,
    output logic pe_req_valid_o,input logic pe_req_ready_i,
    output logic signed[PE_DATA_W-1:0]pe_lhs_o,pe_rhs_o,
    output logic[GID_W-1:0]pe_lhs_gid_o,pe_rhs_gid_o,
    output logic[SEQ_W-1:0]pe_lhs_seq_o,pe_rhs_seq_o,
    input logic pe_rsp_valid_i,output logic pe_rsp_ready_o,input logic pe_less_i,
    output logic[31:0]perf_shared_compares_o,perf_local_compares_o,
    output logic[31:0]perf_swaps_o,perf_phases_o,perf_groups_o,perf_stalls_o,
    output logic[31:0]perf_collect_emit_overlap_o,perf_parallel_stage_cycles_o
);
    localparam int L=$clog2(CAPACITY),STAGES=L*(L+1)/2;
    localparam int KEY_W=1+DEPTH_W+GID_W+SEQ_W+L,ITEM_W=KEY_W+PAYLOAD_W;
    localparam int SEQ_L=PAYLOAD_W+L,GID_L=SEQ_L+SEQ_W,DEPTH_L=GID_L+GID_W;
    logic[CAPACITY*ITEM_W-1:0]bank_data[0:1],pipe_data[0:STAGES-1];
    logic[COUNT_W-1:0]bank_count[0:1],pipe_count[0:STAGES-1];
    logic[GROUP_W-1:0]bank_group[0:1],pipe_group[0:STAGES-1];
    logic[1:0]bank_full;
    logic write_bank,read_bank,g_inflight,drop_q;
    logic[COUNT_W-1:0]collect_count,emit_index;
    logic[STAGES-1:0]valid_q,ready,vin,fire;
    wire[CAPACITY*ITEM_W-1:0]layer_input[0:STAGES-1],layer_sorted[0:STAGES-1];
    wire[STAGES*(CAPACITY/2)-1:0]swaps,active_swaps;
    wire[ITEM_W-1:0]first_left=bank_data[read_bank][0+:ITEM_W];
    wire[ITEM_W-1:0]first_right=bank_data[read_bank][ITEM_W+:ITEM_W];
    wire[KEY_W-1:0]lk=first_left[ITEM_W-1:PAYLOAD_W],rk=first_right[ITEM_W-1:PAYLOAD_W];
    wire first_swap=(lk[KEY_W-1]!=rk[KEY_W-1])?lk[KEY_W-1]:
      (lk[KEY_W-2:L]==rk[KEY_W-2:L]?rk[L-1:0]<lk[L-1:0]:pe_less_i);
    wire[ITEM_W-1:0]output_item=pipe_data[STAGES-1][int'(emit_index)*ITEM_W+:ITEM_W];
    wire accept=s_valid_i&&s_ready_o;
    wire last_fire=valid_q[STAGES-1]&&ready[STAGES-1];
    wire bank_release=fire[0];
    assign s_ready_o=!bank_full[write_bank];
    // cfg_active_lanes is not used to serialize a spatial network. Mode
    // allocation is applied by the upstream service gate and shared PE weights.
    assign pe_req_valid_o=bank_full[read_bank]&&!g_inflight&&ready[0];
    assign pe_rsp_ready_o=g_inflight&&ready[0];
    assign pe_lhs_o={{(PE_DATA_W-DEPTH_W){~first_right[DEPTH_L+DEPTH_W-1]}},
      (first_right[DEPTH_L+:DEPTH_W]^{1'b1,{(DEPTH_W-1){1'b0}}})};
    assign pe_rhs_o={{(PE_DATA_W-DEPTH_W){~first_left[DEPTH_L+DEPTH_W-1]}},
      (first_left[DEPTH_L+:DEPTH_W]^{1'b1,{(DEPTH_W-1){1'b0}}})};
    assign pe_lhs_gid_o=first_right[GID_L+:GID_W];assign pe_rhs_gid_o=first_left[GID_L+:GID_W];
    assign pe_lhs_seq_o=first_right[SEQ_L+:SEQ_W];assign pe_rhs_seq_o=first_left[SEQ_L+:SEQ_W];
    assign m_valid_o=valid_q[STAGES-1]&&pipe_count[STAGES-1]!=0;
    assign m_payload_o=output_item[PAYLOAD_W-1:0];assign m_seq_o=output_item[SEQ_L+:SEQ_W];
    assign m_gid_o=output_item[GID_L+:GID_W];
    assign m_depth_o=output_item[DEPTH_L+:DEPTH_W]^{1'b1,{(DEPTH_W-1){1'b0}}};
    assign m_group_o=pipe_group[STAGES-1];assign m_group_first_o=emit_index==0;
    assign m_group_last_o=emit_index+1'b1==pipe_count[STAGES-1];
    assign busy_o=|valid_q|| |bank_full||collect_count!=0||drop_q||g_inflight;
    assign ready[STAGES-1]=!valid_q[STAGES-1]||pipe_count[STAGES-1]==0||(m_ready_i&&m_group_last_o);
    for(genvar s=0;s<STAGES;s=s+1)begin:g_stage
      if(s<STAGES-1)assign ready[s]=!valid_q[s]||ready[s+1];
      if(s==0)begin
        assign vin[s]=g_inflight&&pe_rsp_valid_i;
        assign layer_input[s]=bank_data[read_bank];
      end else begin
        assign vin[s]=valid_q[s-1];assign layer_input[s]=pipe_data[s-1];
      end
      assign fire[s]=ready[s]&&vin[s];
      assign active_swaps[s*(CAPACITY/2)+:CAPACITY/2]=swaps[s*(CAPACITY/2)+:CAPACITY/2]&{(CAPACITY/2){fire[s]}};
      always_ff@(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin valid_q[s]<=0;pipe_count[s]<=0;pipe_group[s]<=0;end
        else if(ready[s])begin
          valid_q[s]<=vin[s];
          if(vin[s])begin
            pipe_data[s]<=layer_sorted[s];
            if(s==0)begin pipe_count[s]<=bank_count[read_bank];pipe_group[s]<=bank_group[read_bank];end
            else begin pipe_count[s]<=pipe_count[s-1];pipe_group[s]<=pipe_group[s-1];end
          end
        end
      end
    end
    // Every pair and every connection is elaboration-time constant.
    for(genvar span=2;span<=CAPACITY;span=span*2)begin:g_span
      for(genvar step=span/2;step>=1;step=step/2)begin:g_step
        localparam int S=$clog2(span)*($clog2(span)-1)/2+$clog2(span)-1-$clog2(step);
        for(genvar a=0;a<CAPACITY;a=a+1)begin:g_pair
          if((a^step)>a)begin:g_left
            localparam int B=a^step,P=(a/(2*step))*step+(a%step);
            wire[ITEM_W-1:0]x=layer_input[S][a*ITEM_W+:ITEM_W],y=layer_input[S][B*ITEM_W+:ITEM_W];
            wire sw;
            if(S==0&&a==0)assign sw=first_swap;
            else if((a&span)==0)assign sw=y[ITEM_W-1:PAYLOAD_W]<x[ITEM_W-1:PAYLOAD_W];
            else assign sw=x[ITEM_W-1:PAYLOAD_W]<y[ITEM_W-1:PAYLOAD_W];
            assign layer_sorted[S][a*ITEM_W+:ITEM_W]=sw?y:x;
            assign layer_sorted[S][B*ITEM_W+:ITEM_W]=sw?x:y;
            assign swaps[S*(CAPACITY/2)+P]=sw;
          end
        end
      end
    end
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        bank_full<=0;write_bank<=0;read_bank<=0;g_inflight<=0;drop_q<=0;collect_count<=0;emit_index<=0;
        bank_count[0]<=0;bank_count[1]<=0;bank_group[0]<=0;bank_group[1]<=0;
        overflow_o<=0;subset_done_o<=0;perf_shared_compares_o<=0;perf_local_compares_o<=0;
        perf_swaps_o<=0;perf_phases_o<=0;perf_groups_o<=0;perf_stalls_o<=0;
        perf_collect_emit_overlap_o<=0;perf_parallel_stage_cycles_o<=0;
      end else begin
        subset_done_o<=last_fire;
        if(clear_overflow_i)overflow_o<=0;
        if(pe_req_valid_o&&pe_req_ready_i)begin g_inflight<=1;perf_shared_compares_o<=perf_shared_compares_o+1'b1;end
        if(pe_req_valid_o&&!pe_req_ready_i)perf_stalls_o<=perf_stalls_o+1'b1;
        if(bank_release)begin bank_full[read_bank]<=0;read_bank<=~read_bank;g_inflight<=0;end
        if(accept)begin
          if(drop_q)begin if(s_group_last_i)begin drop_q<=0;collect_count<=0;end end
          else if((s_empty_i&&(collect_count!=0||!s_group_last_i))||
                  (!s_empty_i&&collect_count==CAPACITY)||
                  (collect_count!=0&&s_group_i!=bank_group[write_bank]))begin
            overflow_o<=1;collect_count<=0;drop_q<=!s_group_last_i;
          end else begin
            if(collect_count==0)bank_group[write_bank]<=s_group_i;
            if(s_empty_i)begin bank_data[write_bank]<='1;bank_count[write_bank]<=0;end
            else begin
              bank_data[write_bank][int'(collect_count)*ITEM_W+:ITEM_W]<=
                {1'b0,(s_depth_i^{1'b1,{(DEPTH_W-1){1'b0}}}),s_gid_i,s_seq_i,L'(collect_count),s_payload_i};
              bank_count[write_bank]<=collect_count+1'b1;
              if(s_group_last_i)for(integer i=0;i<CAPACITY;i=i+1)
                if(i>int'(collect_count))bank_data[write_bank][i*ITEM_W+:ITEM_W]<='1;
            end
            if(s_group_last_i)begin bank_full[write_bank]<=1;write_bank<=~write_bank;collect_count<=0;end
            else collect_count<=collect_count+1'b1;
          end
        end
        if(last_fire)begin
          emit_index<=0;
          if(pipe_count[STAGES-1]!=0)perf_groups_o<=perf_groups_o+1'b1;
        end else if(m_valid_o&&m_ready_i)emit_index<=emit_index+1'b1;
        perf_phases_o<=perf_phases_o+32'($countones(fire));
        perf_local_compares_o<=perf_local_compares_o+32'($countones(fire)*(CAPACITY/2))-32'(fire[0]);
        perf_swaps_o<=perf_swaps_o+32'($countones(active_swaps));
        if(accept&&m_valid_o&&m_ready_i)perf_collect_emit_overlap_o<=perf_collect_emit_overlap_o+1'b1;
        if($countones(fire)>1)perf_parallel_stage_cycles_o<=perf_parallel_stage_cycles_o+1'b1;
      end
    end
`ifndef SYNTHESIS
    initial begin assert(CAPACITY==8||CAPACITY==16);assert(PE_DATA_W>=DEPTH_W);end
    assert property(@(posedge clk_i)disable iff(!rst_ni)g_inflight|->ready[0]);
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_valid_o&&!m_ready_i|=>
      m_valid_o&&$stable({m_depth_o,m_gid_o,m_seq_o,m_payload_o,m_group_o,m_group_first_o,m_group_last_o}));
`endif
endmodule
