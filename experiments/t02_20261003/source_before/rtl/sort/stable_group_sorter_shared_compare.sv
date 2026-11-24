// Stable in-group insertion sorter whose key comparisons are issued through
// the G client of shared_reconfigurable_pe_slice.  Storage and output order are
// unchanged; only the comparison resource is external and serialized.
module stable_group_sorter_shared_compare #(
    parameter int unsigned CAPACITY=8,
    parameter int unsigned DEPTH_W=27,
    parameter int unsigned GID_W=32,
    parameter int unsigned SEQ_W=32,
    parameter int unsigned GROUP_W=2,
    parameter int unsigned PAYLOAD_W=32,
    parameter int unsigned COUNT_W=$clog2(CAPACITY+1),
    parameter int unsigned PE_DATA_W=32
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
    output logic overflow_o,output logic busy_o,
    output logic pe_req_valid_o,input logic pe_req_ready_i,
    output logic signed[PE_DATA_W-1:0]pe_lhs_o,pe_rhs_o,
    output logic[GID_W-1:0]pe_lhs_gid_o,pe_rhs_gid_o,
    output logic[SEQ_W-1:0]pe_lhs_seq_o,pe_rhs_seq_o,
    input logic pe_rsp_valid_i,output logic pe_rsp_ready_o,input logic pe_less_i
);
    typedef enum logic[2:0]{COLLECT,CMP_REQ,CMP_WAIT,INSERT,EMIT}state_t;
    state_t state_q;
    logic signed[DEPTH_W-1:0]depth_q[0:CAPACITY-1];logic[GID_W-1:0]gid_q[0:CAPACITY-1];
    logic[SEQ_W-1:0]seq_q[0:CAPACITY-1];logic[PAYLOAD_W-1:0]payload_q[0:CAPACITY-1];
    logic[GROUP_W-1:0]group_q,in_group_q;logic[COUNT_W-1:0]count_q,emit_index_q;
    logic[COUNT_W-1:0]search_index_q,insert_index_q;logic in_group_last_q;
    logic signed[DEPTH_W-1:0]in_depth_q;logic[GID_W-1:0]in_gid_q;
    logic[SEQ_W-1:0]in_seq_q;logic[PAYLOAD_W-1:0]in_payload_q;
    localparam int unsigned ADDR_W=CAPACITY<=1?1:$clog2(CAPACITY);
    logic[ADDR_W-1:0]search_addr,insert_addr,emit_addr;
    logic compare_chain;
    logic[COUNT_W-1:0]compare_index;
    integer shift_index;

    assign compare_chain=state_q==CMP_WAIT&&pe_rsp_valid_i&&!pe_less_i&&search_index_q+1'b1<count_q;
    assign compare_index=compare_chain?search_index_q+1'b1:search_index_q;
    assign search_addr=compare_index[ADDR_W-1:0];
    assign insert_addr=insert_index_q[ADDR_W-1:0];
    assign emit_addr=emit_index_q[ADDR_W-1:0];

    assign s_ready_o=state_q==COLLECT;
    assign pe_req_valid_o=state_q==CMP_REQ||compare_chain;
    assign pe_rsp_ready_o=state_q==CMP_WAIT;
    assign pe_lhs_o={{(PE_DATA_W-DEPTH_W){in_depth_q[DEPTH_W-1]}},in_depth_q};
    assign pe_rhs_o={{(PE_DATA_W-DEPTH_W){depth_q[search_addr][DEPTH_W-1]}},depth_q[search_addr]};
    assign pe_lhs_gid_o=in_gid_q;assign pe_rhs_gid_o=gid_q[search_addr];
    assign pe_lhs_seq_o=in_seq_q;assign pe_rhs_seq_o=seq_q[search_addr];
    assign m_valid_o=state_q==EMIT&&emit_index_q<count_q;
    assign m_depth_o=depth_q[emit_addr];assign m_gid_o=gid_q[emit_addr];
    assign m_seq_o=seq_q[emit_addr];assign m_group_o=group_q;assign m_payload_o=payload_q[emit_addr];
    assign m_group_first_o=emit_index_q==0;assign m_group_last_o=emit_index_q+1'b1==count_q;
    assign busy_o=state_q!=COLLECT||count_q!=0;

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        state_q<=COLLECT;count_q<='0;emit_index_q<='0;search_index_q<='0;
        insert_index_q<='0;overflow_o<=0;group_q<='0;in_group_q<='0;in_group_last_q<=0;
        in_depth_q<='0;in_gid_q<='0;in_seq_q<='0;in_payload_q<='0;
      end else begin
        if(clear_overflow_i)overflow_o<=0;
        case(state_q)
          COLLECT:if(s_valid_i&&s_ready_o)begin
            if(count_q<COUNT_W'(CAPACITY))begin
              in_depth_q<=s_depth_i;in_gid_q<=s_gid_i;in_seq_q<=s_seq_i;
              in_payload_q<=s_payload_i;in_group_q<=s_group_i;in_group_last_q<=s_group_last_i;
              search_index_q<='0;
              if(count_q==0)begin insert_index_q<='0;state_q<=INSERT;end
              else state_q<=CMP_REQ;
            end else begin
              overflow_o<=1;
              if(s_group_last_i)begin emit_index_q<='0;state_q<=EMIT;end
            end
          end
          CMP_REQ:if(pe_req_valid_o&&pe_req_ready_i)state_q<=CMP_WAIT;
          CMP_WAIT:if(pe_rsp_valid_i&&pe_rsp_ready_o)begin
            if(pe_less_i)begin insert_index_q<=search_index_q;state_q<=INSERT;end
            else if(search_index_q+1'b1>=count_q)begin insert_index_q<=count_q;state_q<=INSERT;end
            else begin
              search_index_q<=search_index_q+1'b1;
              state_q<=pe_req_ready_i?CMP_WAIT:CMP_REQ;
            end
          end
          INSERT:begin
            for(shift_index=CAPACITY-1;shift_index>0;shift_index=shift_index-1)
              if(shift_index>insert_index_q&&shift_index<=count_q)begin
                depth_q[shift_index]<=depth_q[shift_index-1];gid_q[shift_index]<=gid_q[shift_index-1];
                seq_q[shift_index]<=seq_q[shift_index-1];payload_q[shift_index]<=payload_q[shift_index-1];
              end
            depth_q[insert_addr]<=in_depth_q;gid_q[insert_addr]<=in_gid_q;
            seq_q[insert_addr]<=in_seq_q;payload_q[insert_addr]<=in_payload_q;
            group_q<=in_group_q;count_q<=count_q+1'b1;
            if(in_group_last_q)begin emit_index_q<='0;state_q<=EMIT;end else state_q<=COLLECT;
          end
          EMIT:if(m_valid_o&&m_ready_i)begin
            if(m_group_last_o)begin state_q<=COLLECT;count_q<='0;emit_index_q<='0;end
            else emit_index_q<=emit_index_q+1'b1;
          end
          default:state_q<=COLLECT;
        endcase
      end
    end

`ifndef SYNTHESIS
    initial assert(PE_DATA_W>=DEPTH_W);
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_valid_o&&!m_ready_i
      |=>$stable({m_depth_o,m_gid_o,m_seq_o,m_group_o,m_payload_o,m_group_first_o,m_group_last_o}));
`endif
endmodule
