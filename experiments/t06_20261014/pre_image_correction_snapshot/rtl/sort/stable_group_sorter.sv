// Collect one coarse depth group and emit it in stable (depth,GID,sequence)
// order. Insertion into a small register/SRAM window gives a deterministic,
// synthesizable baseline; a sorting network may replace it without changing
// the stream contract. Capacity overflow is sticky and never drops silently.
module stable_group_sorter #(
    parameter int unsigned CAPACITY=8,
    parameter int unsigned DEPTH_W=27,
    parameter int unsigned GID_W=32,
    parameter int unsigned SEQ_W=32,
    parameter int unsigned GROUP_W=2,
    parameter int unsigned PAYLOAD_W=32,
    parameter int unsigned COUNT_W=$clog2(CAPACITY+1)
) (
    input logic clk_i,input logic rst_ni,input logic clear_overflow_i,
    input logic s_valid_i,output logic s_ready_o,
    input logic signed[DEPTH_W-1:0]s_depth_i,input logic[GID_W-1:0]s_gid_i,
    input logic[SEQ_W-1:0]s_seq_i,input logic[GROUP_W-1:0]s_group_i,
    input logic[PAYLOAD_W-1:0]s_payload_i,input logic s_group_last_i,
    output logic m_valid_o,input logic m_ready_i,
    output logic signed[DEPTH_W-1:0]m_depth_o,output logic[GID_W-1:0]m_gid_o,
    output logic[SEQ_W-1:0]m_seq_o,output logic[GROUP_W-1:0]m_group_o,
    output logic[PAYLOAD_W-1:0]m_payload_o,output logic m_group_first_o,m_group_last_o,
    output logic overflow_o,output logic busy_o
);
    typedef enum logic{COLLECT,EMIT}state_t;state_t state_q;
    logic signed[DEPTH_W-1:0]depth_q[0:CAPACITY-1];logic[GID_W-1:0]gid_q[0:CAPACITY-1];
    logic[SEQ_W-1:0]seq_q[0:CAPACITY-1];logic[PAYLOAD_W-1:0]payload_q[0:CAPACITY-1];
    logic[GROUP_W-1:0]group_q;logic[COUNT_W-1:0]count_q,emit_index_q;
    logic[COUNT_W-1:0]insert_index;logic accept,emit;
    integer search_index,shift_index;
    function automatic logic key_less(
      input logic signed[DEPTH_W-1:0]ad,input logic[GID_W-1:0]ag,input logic[SEQ_W-1:0]as,
      input logic signed[DEPTH_W-1:0]bd,input logic[GID_W-1:0]bg,input logic[SEQ_W-1:0]bs);
      begin key_less=(ad<bd)||((ad==bd)&&((ag<bg)||((ag==bg)&&(as<bs))));end
    endfunction
    always_comb begin
      insert_index=count_q;
      for(search_index=0;search_index<CAPACITY;search_index=search_index+1)
        if(search_index<count_q&&insert_index==count_q&&key_less(s_depth_i,s_gid_i,s_seq_i,
          depth_q[search_index],gid_q[search_index],seq_q[search_index]))insert_index=search_index;
    end
    assign s_ready_o=state_q==COLLECT;
    assign accept=s_valid_i&&s_ready_o;
    assign m_valid_o=state_q==EMIT&&emit_index_q<count_q;
    assign m_depth_o=depth_q[emit_index_q];assign m_gid_o=gid_q[emit_index_q];
    assign m_seq_o=seq_q[emit_index_q];assign m_group_o=group_q;
    assign m_payload_o=payload_q[emit_index_q];assign m_group_first_o=emit_index_q==0;
    assign m_group_last_o=emit_index_q+1==count_q;assign emit=m_valid_o&&m_ready_i;
    assign busy_o=state_q!=COLLECT||count_q!=0;
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin state_q<=COLLECT;count_q<='0;emit_index_q<='0;overflow_o<=0;group_q<='0;end
      else begin
        if(clear_overflow_i)overflow_o<=0;
        if(state_q==COLLECT&&accept)begin
          if(count_q<CAPACITY)begin
            for(shift_index=CAPACITY-1;shift_index>0;shift_index=shift_index-1)begin
              if(shift_index>insert_index&&shift_index<=count_q)begin
                depth_q[shift_index]<=depth_q[shift_index-1];gid_q[shift_index]<=gid_q[shift_index-1];
                seq_q[shift_index]<=seq_q[shift_index-1];payload_q[shift_index]<=payload_q[shift_index-1];
              end
            end
            depth_q[insert_index]<=s_depth_i;gid_q[insert_index]<=s_gid_i;
            seq_q[insert_index]<=s_seq_i;payload_q[insert_index]<=s_payload_i;
            count_q<=count_q+1'b1;group_q<=s_group_i;
            if(s_group_last_i)begin state_q<=EMIT;emit_index_q<='0;end
          end else begin overflow_o<=1; if(s_group_last_i)begin state_q<=EMIT;emit_index_q<='0;end end
        end
        if(state_q==EMIT&&emit)begin
          if(m_group_last_o)begin state_q<=COLLECT;count_q<='0;emit_index_q<='0;end
          else emit_index_q<=emit_index_q+1'b1;
        end
      end
    end
endmodule
