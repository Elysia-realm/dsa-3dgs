// Atomic sorted-issue distributor plus distributed ordered retire. Projection
// lanes may finish out of order, but their tagged block/cull streams reach the
// raster path strictly in issue order. Sequence ID occupies the low SEQ_W bits
// of input metadata and of the metadata field at the head of each task packet.
module ordered_projection_lane_scheduler #(
    parameter int unsigned LANES=4,
    parameter int unsigned INPUT_W=256,
    parameter int unsigned TASK_W=384,
    parameter int unsigned META_W=64,
    parameter int unsigned SEQ_W=32,
    parameter int unsigned RETIRE_DEPTH=16,
    parameter bit ENABLE_OPERAND_ISOLATION=1'b0,
    parameter int unsigned COUNT_W=$clog2(LANES+1),
    parameter int unsigned INDEX_W=LANES<=2?1:$clog2(LANES),
    parameter int unsigned RETIRE_COUNT_W=$clog2(RETIRE_DEPTH+1)
) (
    input logic clk_i,input logic rst_ni,input logic[COUNT_W-1:0]cfg_active_lanes_i,
    input logic s_valid_i,output logic s_ready_o,input logic[INPUT_W-1:0]s_data_i,
    output logic[LANES-1:0]lane_s_valid_o,input logic[LANES-1:0]lane_s_ready_i,
    output logic[LANES-1:0][INPUT_W-1:0]lane_s_data_o,
    input logic[LANES-1:0]lane_task_valid_i,output logic[LANES-1:0]lane_task_ready_o,
    input logic[LANES-1:0][TASK_W-1:0]lane_task_data_i,
    input logic[LANES-1:0]lane_task_first_i,lane_task_last_i,lane_task_culled_i,
    input logic[LANES-1:0]lane_idle_i,
    output logic m_valid_o,input logic m_ready_i,output logic[TASK_W-1:0]m_data_o,
    output logic m_first_o,m_last_o,m_culled_o,output logic culled_pulse_o,
    output logic[LANES-1:0]active_mask_o,output logic all_idle_o,
    output logic retire_wait_o,output logic retire_protocol_error_o,
    output logic[RETIRE_COUNT_W-1:0]retire_occupancy_o
);
    localparam int unsigned TASK_SEQ_LSB=TASK_W-META_W;
    logic[INDEX_W-1:0]dispatch_index_q;
    logic[COUNT_W-1:0]active_count;
    logic issue_ready,issue_valid,input_accept,retire_empty;
    logic[LANES-1:0][SEQ_W-1:0]lane_seq;
    integer lane_index;
    always_comb begin
      if(cfg_active_lanes_i==0)active_count={{(COUNT_W-1){1'b0}},1'b1};
      else if(cfg_active_lanes_i>LANES)active_count=LANES;else active_count=cfg_active_lanes_i;
      for(lane_index=0;lane_index<LANES;lane_index=lane_index+1)begin
        active_mask_o[lane_index]=lane_index<active_count;
        lane_s_valid_o[lane_index]=1'b0;
        lane_s_data_o[lane_index]=ENABLE_OPERAND_ISOLATION?'0:s_data_i;
      end
      lane_s_valid_o[dispatch_index_q]=s_valid_i&&issue_ready&&active_mask_o[dispatch_index_q];
      lane_s_data_o[dispatch_index_q]=s_data_i;
      s_ready_o=issue_ready&&active_mask_o[dispatch_index_q]&&lane_s_ready_i[dispatch_index_q];
    end
    generate
      genvar sequence_lane;
      for(sequence_lane=0;sequence_lane<LANES;sequence_lane=sequence_lane+1)begin:g_sequence
        assign lane_seq[sequence_lane]=lane_task_data_i[sequence_lane][TASK_SEQ_LSB+:SEQ_W];
      end
    endgenerate
    assign input_accept=s_valid_i&&s_ready_o;
    // issue_valid is qualified by lane readiness, making the lane acceptance
    // and ordered-FIFO insertion the same architectural transaction.
    assign issue_valid=s_valid_i&&active_mask_o[dispatch_index_q]&&lane_s_ready_i[dispatch_index_q];
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)dispatch_index_q<='0;
      else if(input_accept)begin
        if(dispatch_index_q+1>=active_count)dispatch_index_q<='0;
        else dispatch_index_q<=dispatch_index_q+1'b1;
      end else if(dispatch_index_q>=active_count)dispatch_index_q<='0;
    end
    ordered_gaussian_retire #(.LANES(LANES),.DEPTH(RETIRE_DEPTH),.SEQ_W(SEQ_W),.DATA_W(TASK_W))u_retire(
      .clk_i(clk_i),.rst_ni(rst_ni),.issue_valid_i(issue_valid),.issue_ready_o(issue_ready),
      .issue_seq_i(s_data_i[INPUT_W-META_W+:SEQ_W]),.lane_valid_i(lane_task_valid_i),
      .lane_ready_o(lane_task_ready_o),.lane_seq_i(lane_seq),.lane_data_i(lane_task_data_i),
      .lane_first_i(lane_task_first_i),.lane_last_i(lane_task_last_i),.lane_culled_i(lane_task_culled_i),
      .m_valid_o(m_valid_o),.m_ready_i(m_ready_i),.m_seq_o(),.m_data_o(m_data_o),
      .m_first_o(m_first_o),.m_last_o(m_last_o),.m_culled_o(m_culled_o),
      .occupancy_o(retire_occupancy_o),.empty_o(retire_empty),.retire_wait_o(retire_wait_o),
      .protocol_error_o(retire_protocol_error_o));
    assign all_idle_o=&(lane_idle_i|~active_mask_o)&&retire_empty;
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)culled_pulse_o<=0;
      else culled_pulse_o<=m_valid_o&&m_ready_i&&m_culled_o;
    end
endmodule
