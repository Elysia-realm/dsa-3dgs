// Runtime-gated replicated alpha engines. Alpha arithmetic is image-state
// independent, so transactions may execute in parallel. Results are restored
// to pixel issue order before the single stateful blend commit port; this is
// the conservative hazard scoreboard for same-pixel front-to-back ordering.
module raster_alpha_lane_array #(
    parameter int unsigned LANES=4,parameter int unsigned META_W=128,
    parameter int unsigned SEQ_W=32,parameter int unsigned RETIRE_DEPTH=16,
    parameter bit ENABLE_OPERAND_ISOLATION=1'b0,
    parameter int unsigned COUNT_W=$clog2(LANES+1),
    parameter int unsigned NUMERIC_W=16+16+15+16+15+6+6+13,
    parameter int unsigned INPUT_W=SEQ_W+META_W+NUMERIC_W,
    parameter int unsigned LANE_META_W=SEQ_W+META_W,
    parameter int unsigned RESULT_W=LANE_META_W+14
) (
    input logic clk_i,input logic rst_ni,input logic[COUNT_W-1:0]cfg_active_lanes_i,
    input logic s_valid_i,output logic s_ready_o,input logic[SEQ_W-1:0]s_seq_i,
    input logic[META_W-1:0]s_meta_i,input logic signed[15:0]s_dx_q10_i,s_dy_q10_i,
    input logic[14:0]s_l00_q12_i,input logic signed[15:0]s_l10_q12_i,input logic[14:0]s_l11_q12_i,
    input logic signed[5:0]s_coordinate_shift_i,s_factor_shift_i,input logic[12:0]s_opacity_q12_i,
    output logic m_valid_o,input logic m_ready_i,output logic[SEQ_W-1:0]m_seq_o,
    output logic[META_W-1:0]m_meta_o,output logic[12:0]m_alpha_q12_o,output logic m_pass_alpha_o,
    output logic[LANES-1:0]active_mask_o,output logic all_idle_o,retire_wait_o,protocol_error_o
);
    logic[INPUT_W-1:0]source_data;logic[LANES-1:0]lane_s_valid,lane_s_ready,lane_m_valid,lane_m_ready;
    logic[LANES-1:0][INPUT_W-1:0]lane_s_data;logic[LANES-1:0][RESULT_W-1:0]lane_result;
    logic[LANES-1:0][LANE_META_W-1:0]lane_meta;logic[LANES-1:0][SEQ_W-1:0]lane_seq;
    logic[LANES-1:0][12:0]lane_alpha;logic[LANES-1:0]lane_pass;
    logic[RESULT_W-1:0]ordered_result;logic[SEQ_W-1:0]ordered_seq,result_seq;
    logic[$clog2(RETIRE_DEPTH+1)-1:0]outstanding;
    assign source_data={s_seq_i,s_meta_i,s_dx_q10_i,s_dy_q10_i,s_l00_q12_i,s_l10_q12_i,s_l11_q12_i,
      s_coordinate_shift_i,s_factor_shift_i,s_opacity_q12_i};
    generate genvar lane;
      for(lane=0;lane<LANES;lane=lane+1)begin:g_lane
        logic[SEQ_W-1:0]in_seq;logic[META_W-1:0]in_meta;logic signed[15:0]in_dx,in_dy;logic[14:0]in_l00,in_l11;
        logic signed[15:0]in_l10;logic signed[5:0]in_coordinate_shift,in_factor_shift;logic[12:0]in_opacity;
        assign {in_seq,in_meta,in_dx,in_dy,in_l00,in_l10,in_l11,in_coordinate_shift,in_factor_shift,in_opacity}=lane_s_data[lane];
        alpha_block_float_core #(.META_W(LANE_META_W))u_alpha(
          .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(lane_s_valid[lane]),.s_ready_o(lane_s_ready[lane]),
          .s_meta_i({in_seq,in_meta}),.s_dx_q10_i(in_dx),.s_dy_q10_i(in_dy),.s_l00_q12_i(in_l00),
          .s_l10_q12_i(in_l10),.s_l11_q12_i(in_l11),.s_coordinate_shift_i(in_coordinate_shift),
          .s_factor_shift_i(in_factor_shift),.s_opacity_q12_i(in_opacity),
          .m_valid_o(lane_m_valid[lane]),.m_ready_i(lane_m_ready[lane]),.m_meta_o(lane_meta[lane]),
          .m_alpha_q12_o(lane_alpha[lane]),.m_pass_alpha_o(lane_pass[lane]));
        assign lane_seq[lane]=lane_meta[lane][LANE_META_W-1-:SEQ_W];
        assign lane_result[lane]={lane_meta[lane],lane_alpha[lane],lane_pass[lane]};
      end
    endgenerate
    ordered_sh_lane_scheduler #(.LANES(LANES),.INPUT_W(INPUT_W),.RESULT_W(RESULT_W),.SEQ_W(SEQ_W),
      .RETIRE_DEPTH(RETIRE_DEPTH),.ENABLE_OPERAND_ISOLATION(ENABLE_OPERAND_ISOLATION))u_order(
      .clk_i(clk_i),.rst_ni(rst_ni),.cfg_active_lanes_i(cfg_active_lanes_i),.s_valid_i(s_valid_i),.s_ready_o(s_ready_o),
      .s_seq_i(s_seq_i),.s_data_i(source_data),.lane_s_valid_o(lane_s_valid),.lane_s_ready_i(lane_s_ready),.lane_s_data_o(lane_s_data),
      .lane_m_valid_i(lane_m_valid),.lane_m_ready_o(lane_m_ready),.lane_m_seq_i(lane_seq),.lane_m_data_i(lane_result),
      .m_valid_o(m_valid_o),.m_ready_i(m_ready_i),.m_seq_o(ordered_seq),.m_data_o(ordered_result),.active_mask_o(active_mask_o),
      .all_idle_o(all_idle_o),.retire_wait_o(retire_wait_o),.protocol_error_o(protocol_error_o),.outstanding_o(outstanding));
    assign {result_seq,m_meta_o,m_alpha_q12_o,m_pass_alpha_o}=ordered_result;
    assign m_seq_o=ordered_seq;
`ifndef SYNTHESIS
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_valid_o|->result_seq==ordered_seq);
`endif
endmodule
