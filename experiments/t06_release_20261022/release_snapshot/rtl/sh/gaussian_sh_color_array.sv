// Replicated per-Gaussian degree-3 SH engines with runtime lane gating and
// ordered completion. A mode changes the enabled subset only; all enabled
// lanes execute the identical fixed-point arithmetic.
module gaussian_sh_color_array #(
    parameter int unsigned LANES=4,parameter int unsigned META_W=64,
    parameter int unsigned SEQ_W=16,parameter int unsigned COORD_W=27,
    parameter int unsigned COEFF_W=18,parameter int unsigned COEFFS=16,
    parameter int unsigned RETIRE_DEPTH=16,
    parameter bit ENABLE_OPERAND_ISOLATION=1'b0,
    parameter int unsigned COUNT_W=$clog2(LANES+1),
    parameter int unsigned COEFF_FLAT_W=3*COEFFS*COEFF_W,
    parameter int unsigned INPUT_W=META_W+3*COORD_W+COEFF_FLAT_W,
    parameter int unsigned RESULT_W=META_W+3*13+2
) (
    input logic clk_i,input logic rst_ni,input logic[COUNT_W-1:0]cfg_active_lanes_i,
    input logic s_valid_i,output logic s_ready_o,input logic[META_W-1:0]s_meta_i,
    input logic signed[COORD_W-1:0]s_world_x_q16_i,s_world_y_q16_i,s_world_z_q16_i,
    input logic signed[COORD_W-1:0]cfg_camera_x_q16_i,cfg_camera_y_q16_i,cfg_camera_z_q16_i,
    input logic[COEFF_FLAT_W-1:0]s_coeff_q12_flat_i,
    output logic m_valid_o,input logic m_ready_i,output logic[META_W-1:0]m_meta_o,
    output logic[12:0]m_r_q12_o,m_g_q12_o,m_b_q12_o,
    output logic m_direction_fallback_o,m_numeric_overflow_o,
    output logic[LANES-1:0]active_mask_o,output logic all_idle_o,retire_wait_o,protocol_error_o
);
    logic[INPUT_W-1:0]source_data;logic[LANES-1:0]lane_s_valid,lane_s_ready,lane_m_valid,lane_m_ready;
    logic[LANES-1:0][INPUT_W-1:0]lane_s_data;logic[LANES-1:0][RESULT_W-1:0]lane_result;
    logic[LANES-1:0][META_W-1:0]lane_meta;logic[LANES-1:0][SEQ_W-1:0]lane_seq;
    logic[LANES-1:0][12:0]lane_r,lane_g,lane_b;logic[LANES-1:0]lane_fallback,lane_overflow;
    logic[RESULT_W-1:0]ordered_result;logic[SEQ_W-1:0]ordered_seq;
    logic[$clog2(RETIRE_DEPTH+1)-1:0]outstanding;assign source_data={s_meta_i,s_world_x_q16_i,s_world_y_q16_i,s_world_z_q16_i,s_coeff_q12_flat_i};
    generate genvar lane;
      for(lane=0;lane<LANES;lane=lane+1)begin:g_lane
        logic[META_W-1:0]in_meta;logic signed[COORD_W-1:0]in_x,in_y,in_z;logic[COEFF_FLAT_W-1:0]in_coeff;
        assign {in_meta,in_x,in_y,in_z,in_coeff}=lane_s_data[lane];
        gaussian_sh_color_core #(.META_W(META_W),.COORD_W(COORD_W),.COEFF_W(COEFF_W),.COEFFS(COEFFS))u_core(
          .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(lane_s_valid[lane]),.s_ready_o(lane_s_ready[lane]),.s_meta_i(in_meta),
          .s_world_x_q16_i(in_x),.s_world_y_q16_i(in_y),.s_world_z_q16_i(in_z),
          .cfg_camera_x_q16_i(cfg_camera_x_q16_i),.cfg_camera_y_q16_i(cfg_camera_y_q16_i),.cfg_camera_z_q16_i(cfg_camera_z_q16_i),
          .s_coeff_q12_flat_i(in_coeff),.m_valid_o(lane_m_valid[lane]),.m_ready_i(lane_m_ready[lane]),.m_meta_o(lane_meta[lane]),
          .m_r_q12_o(lane_r[lane]),.m_g_q12_o(lane_g[lane]),.m_b_q12_o(lane_b[lane]),
          .m_direction_fallback_o(lane_fallback[lane]),.m_numeric_overflow_o(lane_overflow[lane]));
        assign lane_seq[lane]=lane_meta[lane][SEQ_W-1:0];
        assign lane_result[lane]={lane_meta[lane],lane_r[lane],lane_g[lane],lane_b[lane],lane_fallback[lane],lane_overflow[lane]};
      end
    endgenerate
    ordered_sh_lane_scheduler #(.LANES(LANES),.INPUT_W(INPUT_W),.RESULT_W(RESULT_W),.SEQ_W(SEQ_W),
      .RETIRE_DEPTH(RETIRE_DEPTH),.ENABLE_OPERAND_ISOLATION(ENABLE_OPERAND_ISOLATION))u_schedule(
      .clk_i(clk_i),.rst_ni(rst_ni),.cfg_active_lanes_i(cfg_active_lanes_i),.s_valid_i(s_valid_i),.s_ready_o(s_ready_o),
      .s_seq_i(s_meta_i[SEQ_W-1:0]),.s_data_i(source_data),.lane_s_valid_o(lane_s_valid),.lane_s_ready_i(lane_s_ready),.lane_s_data_o(lane_s_data),
      .lane_m_valid_i(lane_m_valid),.lane_m_ready_o(lane_m_ready),.lane_m_seq_i(lane_seq),.lane_m_data_i(lane_result),
      .m_valid_o(m_valid_o),.m_ready_i(m_ready_i),.m_seq_o(ordered_seq),.m_data_o(ordered_result),.active_mask_o(active_mask_o),
      .all_idle_o(all_idle_o),.retire_wait_o(retire_wait_o),.protocol_error_o(protocol_error_o),.outstanding_o(outstanding));
    assign {m_meta_o,m_r_q12_o,m_g_q12_o,m_b_q12_o,m_direction_fallback_o,m_numeric_overflow_o}=ordered_result;
endmodule
