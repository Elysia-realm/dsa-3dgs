// Folded, stable K-element BSU. Each layer executes disjoint CAS pairs in
// cfg_active_lanes batches. Lane zero uses the physical G/P/R PE; other lanes
// are dedicated comparators. An ordinal resolves equal full keys stably.
// s_empty_i marks an explicit empty subset (valid+last); no output is emitted.
// Oversize subsets are drained and rejected atomically, never partially sorted.
module bitonic_group_sorter_shared #(
    parameter int unsigned CAPACITY=8, DEPTH_W=27, GID_W=32, SEQ_W=16,
    parameter int unsigned GROUP_W=2, PAYLOAD_W=1, PE_DATA_W=32,
    parameter int unsigned COMPARE_LANES=4,
    parameter int unsigned COUNT_W=$clog2(CAPACITY+1),
    parameter int unsigned LANE_W=$clog2(COMPARE_LANES+1)
) (
    input logic clk_i,rst_ni,clear_overflow_i,
    input logic[LANE_W-1:0]cfg_active_lanes_i,
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
    output logic[31:0]perf_swaps_o,perf_phases_o,perf_groups_o,perf_stalls_o
);
    localparam int ORD_W=$clog2(CAPACITY);
    localparam int KEY_W=1+DEPTH_W+GID_W+SEQ_W+ORD_W;
    localparam int ITEM_W=KEY_W+PAYLOAD_W;
    localparam int SEQ_L=PAYLOAD_W+ORD_W,GID_L=SEQ_L+SEQ_W,DEPTH_L=GID_L+GID_W;
    typedef enum logic[2:0]{COLLECT,REQUEST,RESPONSE,EMIT,DROP}state_t;
    state_t state_q;
    logic[ITEM_W-1:0]items[0:CAPACITY-1];
    logic[COUNT_W-1:0]count_q,emit_q,span_q,stride_q,pair_q;
    logic[ORD_W-1:0]stride_log_q;
    logic[LANE_W-1:0]lanes_q;
    logic[GROUP_W-1:0]group_q;
    logic[COMPARE_LANES-1:0]local_swap_q;
    integer left_idx[0:COMPARE_LANES-1],right_idx[0:COMPARE_LANES-1];
    logic[COMPARE_LANES-1:0]active_pair,ascending,swap_pair;
    logic[KEY_W-1:0]left_key,right_key;
    logic right_less,keys_equal;
    integer n;
    wire accept=s_valid_i&&s_ready_o;
    assign s_ready_o=state_q==COLLECT||state_q==DROP;
    assign busy_o=state_q!=COLLECT||count_q!=0;
    assign pe_req_valid_o=state_q==REQUEST;
    assign pe_rsp_ready_o=state_q==RESPONSE;
    assign m_valid_o=state_q==EMIT;
    assign m_payload_o=items[emit_q][PAYLOAD_W-1:0];
    assign m_seq_o=items[emit_q][SEQ_L+:SEQ_W];
    assign m_gid_o=items[emit_q][GID_L+:GID_W];
    assign m_depth_o=items[emit_q][DEPTH_L+:DEPTH_W]^{1'b1,{(DEPTH_W-1){1'b0}}};
    assign m_group_o=group_q;assign m_group_first_o=emit_q==0;
    assign m_group_last_o=emit_q+1'b1==count_q;

    always_comb begin
      for(integer j=0;j<COMPARE_LANES;j=j+1)begin
        // Insert a zero bit at the current XOR stride into pair number.
        left_idx[j]=(((int'(pair_q)+j)>>stride_log_q)<<(stride_log_q+1))|
          ((int'(pair_q)+j)&(int'(stride_q)-1));
        right_idx[j]=left_idx[j]^int'(stride_q);
        active_pair[j]=j<int'(lanes_q)&&(int'(pair_q)+j)<CAPACITY/2;
        if(!active_pair[j])begin left_idx[j]=0;right_idx[j]=0;end
        ascending[j]=(left_idx[j]&int'(span_q))==0;
        swap_pair[j]=active_pair[j]&&(ascending[j]?
          items[right_idx[j]][ITEM_W-1:PAYLOAD_W]<items[left_idx[j]][ITEM_W-1:PAYLOAD_W]:
          items[left_idx[j]][ITEM_W-1:PAYLOAD_W]<items[right_idx[j]][ITEM_W-1:PAYLOAD_W]);
      end
    end
    assign pe_lhs_o={{(PE_DATA_W-DEPTH_W){~items[right_idx[0]][DEPTH_L+DEPTH_W-1]}},
      (items[right_idx[0]][DEPTH_L+:DEPTH_W]^{1'b1,{(DEPTH_W-1){1'b0}}})};
    assign pe_rhs_o={{(PE_DATA_W-DEPTH_W){~items[left_idx[0]][DEPTH_L+DEPTH_W-1]}},
      (items[left_idx[0]][DEPTH_L+:DEPTH_W]^{1'b1,{(DEPTH_W-1){1'b0}}})};
    assign pe_lhs_gid_o=items[right_idx[0]][GID_L+:GID_W];
    assign pe_rhs_gid_o=items[left_idx[0]][GID_L+:GID_W];
    assign pe_lhs_seq_o=items[right_idx[0]][SEQ_L+:SEQ_W];
    assign pe_rhs_seq_o=items[left_idx[0]][SEQ_L+:SEQ_W];
    assign left_key=items[left_idx[0]][ITEM_W-1:PAYLOAD_W];
    assign right_key=items[right_idx[0]][ITEM_W-1:PAYLOAD_W];
    assign keys_equal=left_key==right_key;
    // Invalid sentinels are +infinity regardless of their arithmetic fields.
    assign right_less=(left_key[KEY_W-1]!=right_key[KEY_W-1])?left_key[KEY_W-1]:
      (left_key[KEY_W-2:ORD_W]==right_key[KEY_W-2:ORD_W]?
        right_key[ORD_W-1:0]<left_key[ORD_W-1:0]:pe_less_i);

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        state_q<=COLLECT;count_q<=0;emit_q<=0;span_q<=2;stride_q<=1;pair_q<=0;
        stride_log_q<=0;
        lanes_q<=1;group_q<=0;overflow_o<=0;subset_done_o<=0;local_swap_q<=0;
        perf_shared_compares_o<=0;perf_local_compares_o<=0;perf_swaps_o<=0;
        perf_phases_o<=0;perf_groups_o<=0;perf_stalls_o<=0;
      end else begin
        subset_done_o<=0;
        if(clear_overflow_i)overflow_o<=0;
        case(state_q)
          COLLECT:if(accept)begin
            if(count_q==0)begin
              group_q<=s_group_i;
              lanes_q<=cfg_active_lanes_i==0?LANE_W'(1):
                cfg_active_lanes_i>COMPARE_LANES?LANE_W'(COMPARE_LANES):cfg_active_lanes_i;
            end
            if(s_empty_i)begin
              if(count_q!=0||!s_group_last_i)overflow_o<=1;
              count_q<=0;subset_done_o<=1;
            end else if(count_q==CAPACITY|| (count_q!=0&&s_group_i!=group_q))begin
              overflow_o<=1;count_q<=0;
              if(s_group_last_i)subset_done_o<=1;else state_q<=DROP;
            end else begin
              items[count_q]<={1'b0,(s_depth_i^{1'b1,{(DEPTH_W-1){1'b0}}}),s_gid_i,s_seq_i,ORD_W'(count_q),s_payload_i};
              count_q<=count_q+1'b1;
              if(s_group_last_i)begin
                for(n=0;n<CAPACITY;n=n+1)if(n>int'(count_q))items[n]<='1;
                span_q<=2;stride_q<=1;stride_log_q<=0;pair_q<=0;state_q<=REQUEST;
              end
            end
          end
          DROP:if(accept&&s_group_last_i)begin state_q<=COLLECT;subset_done_o<=1;end
          REQUEST:begin
            if(!pe_req_ready_i)perf_stalls_o<=perf_stalls_o+1'b1;
            if(pe_req_ready_i)begin
              local_swap_q<=swap_pair;state_q<=RESPONSE;
              perf_shared_compares_o<=perf_shared_compares_o+1'b1;
              perf_local_compares_o<=perf_local_compares_o+
                32'((CAPACITY/2-int'(pair_q)<int'(lanes_q)?CAPACITY/2-int'(pair_q):int'(lanes_q))-1);
            end
          end
          RESPONSE:if(pe_rsp_valid_i)begin
            for(n=0;n<COMPARE_LANES;n=n+1)begin
              if(active_pair[n]&&(n==0?(ascending[0]?right_less:!right_less&&!keys_equal):local_swap_q[n]))begin
                items[left_idx[n]]<=items[right_idx[n]];
                items[right_idx[n]]<=items[left_idx[n]];
              end
            end
            // Work counts include sentinels: the folded network is fixed-size.
            perf_swaps_o<=perf_swaps_o+32'($countones((local_swap_q&~COMPARE_LANES'(1))|
              COMPARE_LANES'(ascending[0]?right_less:!right_less&&!keys_equal)));
            if(int'(pair_q)+int'(lanes_q)<CAPACITY/2)begin pair_q<=pair_q+COUNT_W'(lanes_q);state_q<=REQUEST;end
            else begin
              pair_q<=0;perf_phases_o<=perf_phases_o+1'b1;
              if(stride_q>1)begin stride_q<=stride_q>>1;stride_log_q<=stride_log_q-1'b1;state_q<=REQUEST;end
              else if(span_q<CAPACITY)begin
                span_q<=span_q<<1;stride_q<=span_q;
                for(n=0;n<ORD_W;n=n+1)if(span_q[n])stride_log_q<=ORD_W'(n);
                state_q<=REQUEST;
              end
              else begin emit_q<=0;state_q<=EMIT;end
            end
          end
          EMIT:if(m_ready_i)begin
            if(m_group_last_o)begin state_q<=COLLECT;count_q<=0;emit_q<=0;subset_done_o<=1;perf_groups_o<=perf_groups_o+1'b1;end
            else emit_q<=emit_q+1'b1;
          end
          default:state_q<=COLLECT;
        endcase
      end
    end
`ifndef SYNTHESIS
    initial begin assert(CAPACITY==8||CAPACITY==16);assert(PE_DATA_W>=DEPTH_W);end
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_valid_o&&!m_ready_i|=>
      m_valid_o&&$stable({m_depth_o,m_gid_o,m_seq_o,m_payload_o,m_group_first_o,m_group_last_o}));
    assert property(@(posedge clk_i)disable iff(!rst_ni)pe_req_valid_o&&!pe_req_ready_i|=>
      pe_req_valid_o&&$stable({pe_lhs_o,pe_rhs_o,pe_lhs_gid_o,pe_rhs_gid_o,pe_lhs_seq_o,pe_rhs_seq_o}));
`endif
endmodule
