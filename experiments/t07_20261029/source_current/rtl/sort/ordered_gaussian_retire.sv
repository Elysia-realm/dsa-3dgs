// Distributed ordered-retire queue for parallel Gaussian engines. Issue order
// is already sorted near-to-far. Each lane retains its completed Gaussian block
// stream under backpressure; only the lane whose sequence equals the queue head
// may retire. A culled Gaussian is represented by one event with last=1.
module ordered_gaussian_retire #(
    parameter int unsigned LANES=4,
    parameter int unsigned DEPTH=16,
    parameter int unsigned SEQ_W=32,
    parameter int unsigned DATA_W=384,
    parameter int unsigned PTR_W=DEPTH<=2?1:$clog2(DEPTH),
    parameter int unsigned COUNT_W=$clog2(DEPTH+1),
    parameter int unsigned LANE_W=LANES<=2?1:$clog2(LANES)
) (
    input logic clk_i,input logic rst_ni,
    input logic issue_valid_i,output logic issue_ready_o,input logic[SEQ_W-1:0]issue_seq_i,
    input logic[LANES-1:0]lane_valid_i,output logic[LANES-1:0]lane_ready_o,
    input logic[LANES-1:0][SEQ_W-1:0]lane_seq_i,
    input logic[LANES-1:0][DATA_W-1:0]lane_data_i,
    input logic[LANES-1:0]lane_first_i,lane_last_i,lane_culled_i,
    output logic m_valid_o,input logic m_ready_i,output logic[SEQ_W-1:0]m_seq_o,
    output logic[DATA_W-1:0]m_data_o,output logic m_first_o,m_last_o,m_culled_o,
    output logic[COUNT_W-1:0]occupancy_o,output logic empty_o,
    output logic retire_wait_o,output logic protocol_error_o
);
    logic[SEQ_W-1:0]order_q[0:DEPTH-1];logic[PTR_W-1:0]write_ptr_q,read_ptr_q;
    logic[COUNT_W-1:0]count_q;logic[LANE_W-1:0]selected_lane;logic found;
    logic head_started_q;
    logic issue_accept,retire_accept;integer lane_index;
    assign issue_ready_o=count_q<DEPTH;assign issue_accept=issue_valid_i&&issue_ready_o;
    // Keep result selection independent of downstream ready.  Combining the
    // output mux and ready demux in one process makes conservative synthesis
    // tools infer a false data -> ready -> data combinational loop.
    always_comb begin
      found=0;selected_lane='0;
      for(lane_index=0;lane_index<LANES;lane_index=lane_index+1)
        if(!found&&lane_valid_i[lane_index]&&count_q!=0&&lane_seq_i[lane_index]==order_q[read_ptr_q])begin
          found=1;selected_lane=lane_index[LANE_W-1:0];end
    end
    always_comb begin
      lane_ready_o='0;
      if(found)lane_ready_o[selected_lane]=m_ready_i;
    end
    assign m_valid_o=found;assign m_seq_o=count_q!=0?order_q[read_ptr_q]:'0;
    assign m_data_o=lane_data_i[selected_lane];assign m_first_o=lane_first_i[selected_lane];
    assign m_last_o=lane_last_i[selected_lane];assign m_culled_o=lane_culled_i[selected_lane];
    assign retire_accept=m_valid_o&&m_ready_i;
    assign occupancy_o=count_q;assign empty_o=count_q==0;
    assign retire_wait_o=count_q!=0&&!found;
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin write_ptr_q<='0;read_ptr_q<='0;count_q<='0;head_started_q<=0;protocol_error_o<=0;end
      else begin
        if(issue_accept)begin order_q[write_ptr_q]<=issue_seq_i;
          write_ptr_q<=write_ptr_q==DEPTH-1?'0:write_ptr_q+1'b1;end
        if(retire_accept)begin
          if(!head_started_q&&!m_first_o)protocol_error_o<=1;
          if(head_started_q&&m_first_o)protocol_error_o<=1;
          if(m_culled_o&&(!m_first_o||!m_last_o))protocol_error_o<=1;
          if(m_culled_o&&head_started_q)protocol_error_o<=1;
          if(m_last_o)begin
            read_ptr_q<=read_ptr_q==DEPTH-1?'0:read_ptr_q+1'b1;
            head_started_q<=0;
          end else head_started_q<=1;
        end
        case({issue_accept,retire_accept&&m_last_o})
          2'b10:count_q<=count_q+1'b1;2'b01:count_q<=count_q-1'b1;default:count_q<=count_q;
        endcase
      end
    end
endmodule
