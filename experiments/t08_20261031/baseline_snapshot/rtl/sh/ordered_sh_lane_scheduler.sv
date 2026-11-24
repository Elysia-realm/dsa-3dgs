// Atomic distributor and ordered retire for one-result-per-Gaussian SH lanes.
// Physical lanes may complete in any order, but the output follows the sorted
// issue sequence. This module contains no SH arithmetic and is independently
// testable with deliberately different lane latencies.
module ordered_sh_lane_scheduler #(
    parameter int unsigned LANES=4,parameter int unsigned INPUT_W=256,
    parameter int unsigned RESULT_W=64,parameter int unsigned SEQ_W=16,
    parameter int unsigned RETIRE_DEPTH=16,
    parameter bit ENABLE_OPERAND_ISOLATION=1'b0,
    parameter int unsigned COUNT_W=$clog2(LANES+1),
    parameter int unsigned INDEX_W=LANES<=2?1:$clog2(LANES),
    parameter int unsigned OUTSTANDING_W=$clog2(RETIRE_DEPTH+1)
) (
    input logic clk_i,input logic rst_ni,input logic[COUNT_W-1:0]cfg_active_lanes_i,
    input logic s_valid_i,output logic s_ready_o,input logic[SEQ_W-1:0]s_seq_i,
    input logic[INPUT_W-1:0]s_data_i,
    output logic[LANES-1:0]lane_s_valid_o,input logic[LANES-1:0]lane_s_ready_i,
    output logic[LANES-1:0][INPUT_W-1:0]lane_s_data_o,
    input logic[LANES-1:0]lane_m_valid_i,output logic[LANES-1:0]lane_m_ready_o,
    input logic[LANES-1:0][SEQ_W-1:0]lane_m_seq_i,
    input logic[LANES-1:0][RESULT_W-1:0]lane_m_data_i,
    output logic m_valid_o,input logic m_ready_i,output logic[SEQ_W-1:0]m_seq_o,
    output logic[RESULT_W-1:0]m_data_o,output logic[LANES-1:0]active_mask_o,
    output logic all_idle_o,retire_wait_o,protocol_error_o,
    output logic[OUTSTANDING_W-1:0]outstanding_o
);
    logic[INDEX_W-1:0]dispatch_index_q;logic[COUNT_W-1:0]active_count;
    logic issue_ready,issue_valid,input_accept,retire_accept,retire_empty;
    logic retire_first,retire_last,retire_culled;logic[OUTSTANDING_W-1:0]retire_occupancy;
    logic[LANES-1:0]lane_first,lane_last,lane_culled;integer lane_index;
    always_comb begin
      if(cfg_active_lanes_i==0)active_count={{(COUNT_W-1){1'b0}},1'b1};
      else if(cfg_active_lanes_i>LANES)active_count=LANES;else active_count=cfg_active_lanes_i;
      for(lane_index=0;lane_index<LANES;lane_index=lane_index+1)begin
        active_mask_o[lane_index]=lane_index<active_count;
        lane_s_valid_o[lane_index]=0;
        lane_s_data_o[lane_index]=ENABLE_OPERAND_ISOLATION?'0:s_data_i;
      end
      lane_s_valid_o[dispatch_index_q]=s_valid_i&&issue_ready&&active_mask_o[dispatch_index_q];
      lane_s_data_o[dispatch_index_q]=s_data_i;
      s_ready_o=issue_ready&&active_mask_o[dispatch_index_q]&&lane_s_ready_i[dispatch_index_q];
    end
    assign input_accept=s_valid_i&&s_ready_o;
    assign issue_valid=s_valid_i&&active_mask_o[dispatch_index_q]&&lane_s_ready_i[dispatch_index_q];
    assign lane_first='1;assign lane_last='1;assign lane_culled='0;
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)dispatch_index_q<='0;
      else if(input_accept)begin
        if(dispatch_index_q+1>=active_count)dispatch_index_q<='0;
        else dispatch_index_q<=dispatch_index_q+1'b1;
      end else if(dispatch_index_q>=active_count)dispatch_index_q<='0;
    end
    ordered_gaussian_retire #(.LANES(LANES),.DEPTH(RETIRE_DEPTH),.SEQ_W(SEQ_W),.DATA_W(RESULT_W))u_retire(
      .clk_i(clk_i),.rst_ni(rst_ni),.issue_valid_i(issue_valid),.issue_ready_o(issue_ready),.issue_seq_i(s_seq_i),
      .lane_valid_i(lane_m_valid_i),.lane_ready_o(lane_m_ready_o),.lane_seq_i(lane_m_seq_i),.lane_data_i(lane_m_data_i),
      .lane_first_i(lane_first),.lane_last_i(lane_last),.lane_culled_i(lane_culled),
      .m_valid_o(m_valid_o),.m_ready_i(m_ready_i),.m_seq_o(m_seq_o),.m_data_o(m_data_o),
      .m_first_o(retire_first),.m_last_o(retire_last),.m_culled_o(retire_culled),
      .occupancy_o(retire_occupancy),.empty_o(retire_empty),.retire_wait_o(retire_wait_o),.protocol_error_o(protocol_error_o));
    assign retire_accept=m_valid_o&&m_ready_i;
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)outstanding_o<='0;
      else case({input_accept,retire_accept})
        2'b10:outstanding_o<=outstanding_o+1'b1;
        2'b01:outstanding_o<=outstanding_o-1'b1;
        default:outstanding_o<=outstanding_o;
      endcase
    end
    assign all_idle_o=outstanding_o==0&&retire_empty;
`ifndef SYNTHESIS
    assert property(@(posedge clk_i)disable iff(!rst_ni)$changed(cfg_active_lanes_i)|->$past(all_idle_o));
`endif
endmodule
