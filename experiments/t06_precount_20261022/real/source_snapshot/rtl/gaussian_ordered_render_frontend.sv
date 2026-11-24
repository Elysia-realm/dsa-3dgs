// System data-path wrapper from a sorted full Gaussian record through dynamic
// ordered projection, one-time SH color, Gaussian-internal block traversal,
// pixel expansion, alpha, blend and termination. DMA and frame writeback are
// intentionally outside this front-end boundary.
module gaussian_ordered_render_frontend #(
    parameter int unsigned LANES=4,parameter int unsigned GID_W=32,parameter int unsigned SEQ_W=16,
    parameter int unsigned EPOCH_W=16,parameter int unsigned COORD_W=27,parameter int unsigned QUAT_W=22,
    parameter int unsigned SCALE_W=24,parameter int unsigned ROT_W=22,parameter int unsigned COV2_W=35,
    parameter int unsigned SCREEN_W=27,parameter int unsigned PIXEL_COORD_W=16,parameter int unsigned TILE_W=12,
    parameter int unsigned STATE_ENTRIES=4096,parameter int unsigned STATE_WINDOW_ENTRIES=2,
    parameter int unsigned STATE_MSHR_COUNT=2,
    parameter bit ENABLE_RESPONSE_BLEND_BYPASS=1'b0,
    parameter bit ENABLE_BLEND_COMMIT_BYPASS=1'b0,
    parameter bit ENABLE_OPERAND_ISOLATION=1'b0,
    parameter bit ENABLE_SHAPE_BLOCK_REJECT=1'b0,
    parameter bit USE_SHARED_PROJECTION_PE=1'b0,
    parameter bit SHARED_P_DOT3=1'b0,
    parameter bit USE_SHARED_RASTER_PE=1'b0,
    parameter bit ENABLE_ALPHA_ZERO_SKIP=1'b0,
    parameter int unsigned PE_DATA_W=32,parameter int unsigned PE_RESULT_W=2*PE_DATA_W+1,
    parameter bit USE_STATE_CACHE_BACKEND=1'b0,
    parameter int unsigned COEFF_W=18,parameter int unsigned COEFFS=16,parameter int unsigned COEFF_FLAT_W=3*COEFFS*COEFF_W,
    parameter int unsigned META_W=EPOCH_W+GID_W+SEQ_W,
    parameter int unsigned RAW_DESC_W=META_W+13+COORD_W+3*COV2_W+2*SCREEN_W+4*PIXEL_COORD_W+1,
    parameter int unsigned DESC_W=RAW_DESC_W+15+16+15+6+6+1
) (
    input logic clk_i,input logic rst_ni,input logic shadow_mode_we_i,input logic[1:0]shadow_mode_i,
    input logic mode_commit_i,input logic epoch_boundary_i,output logic[1:0]active_mode_o,
    output logic[15:0]epoch_id_o,output logic mode_pending_o,mode_commit_pulse_o,mode_overrun_o,
    input logic s_valid_i,output logic s_ready_o,input logic[GID_W-1:0]s_gid_i,input logic[SEQ_W-1:0]s_seq_i,
    input logic signed[COORD_W-1:0]s_world_x_q16_i,s_world_y_q16_i,s_world_z_q16_i,
    input logic signed[QUAT_W-1:0]s_qw_q20_i,s_qx_q20_i,s_qy_q20_i,s_qz_q20_i,
    input logic[SCALE_W-1:0]s_scale_x_q20_i,s_scale_y_q20_i,s_scale_z_q20_i,input logic[12:0]s_opacity_q12_i,
    input logic[COEFF_FLAT_W-1:0]s_coeff_q12_flat_i,
    input logic signed[ROT_W-1:0]cfg_r00_q20_i,cfg_r01_q20_i,cfg_r02_q20_i,cfg_r10_q20_i,cfg_r11_q20_i,cfg_r12_q20_i,
    input logic signed[ROT_W-1:0]cfg_r20_q20_i,cfg_r21_q20_i,cfg_r22_q20_i,
    input logic signed[COORD_W-1:0]cfg_tx_q16_i,cfg_ty_q16_i,cfg_tz_q16_i,
    input logic signed[COORD_W-1:0]cfg_camera_x_q16_i,cfg_camera_y_q16_i,cfg_camera_z_q16_i,
    input logic signed[32:0]cfg_fx_q16_i,cfg_fy_q16_i,cfg_cx_q16_i,cfg_cy_q16_i,
    input logic signed[COORD_W-1:0]cfg_near_q16_i,cfg_far_q16_i,input logic[COV2_W-1:0]cfg_regularizer_q8_i,
    input logic[PIXEL_COORD_W-1:0]cfg_image_width_i,cfg_image_height_i,
    output logic commit_valid_o,input logic commit_ready_i,output logic[31:0]commit_task_id_o,commit_block_id_o,
    output logic[GID_W-1:0]commit_gid_o,output logic[EPOCH_W-1:0]commit_epoch_id_o,
    output logic[12:0]commit_alpha_q12_o,output logic commit_pass_alpha_o,output logic[31:0]commit_pixel_id_o,
    output logic[12:0]commit_r_q12_o,commit_g_q12_o,commit_b_q12_o,output logic[15:0]commit_t_q16_o,
    output logic commit_newly_terminated_o,output logic block_terminated_pulse_o,skipped_terminated_pulse_o,
    output logic empty_or_culled_pulse_o,shape_rejected_pulse_o,output logic all_idle_o,output logic retire_wait_o,protocol_error_o,
    output logic stage_projection_busy_o,stage_raster_busy_o,block_candidate_pulse_o,
    output logic[LANES-1:0]projection_active_mask_o,output logic[LANES-1:0]sh_active_mask_o,raster_active_mask_o,
    output logic state_miss_req_valid_o,input logic state_miss_req_ready_i,
    output logic[1:0]state_miss_req_tag_o,output logic[31:0]state_miss_req_pixel_id_o,input logic state_miss_rsp_valid_i,
    output logic state_miss_rsp_ready_o,input logic[1:0]state_miss_rsp_tag_i,input logic state_miss_rsp_error_i,
    input logic[127:0]state_miss_rsp_data_i,output logic state_cache_error_o,state_cache_idle_o,
    output logic pe_req_valid_o,input logic pe_req_ready_i,
    output logic signed[PE_DATA_W-1:0]pe_lhs_o,pe_rhs_o,
    output logic signed[PE_RESULT_W-1:0]pe_acc_o,
    input logic pe_rsp_valid_i,output logic pe_rsp_ready_o,
    input logic signed[PE_RESULT_W-1:0]pe_result_i,
    output logic r_pe_req_valid_o,input logic r_pe_req_ready_i,
    output logic signed[PE_DATA_W-1:0]r_pe_lhs_o,r_pe_rhs_o,
    input logic r_pe_rsp_valid_i,output logic r_pe_rsp_ready_o,
    input logic signed[PE_RESULT_W-1:0]r_pe_result_i
);
    logic block_valid,block_ready,block_first,block_last,block_culled,sh_fallback,numeric_overflow;
    logic[DESC_W-1:0]block_desc;logic[TILE_W-1:0]block_x,block_y;logic[12:0]block_r,block_g,block_b;
    logic[EPOCH_W-1:0]block_epoch;logic[GID_W-1:0]block_gid;logic[SEQ_W-1:0]block_seq;
    logic[12:0]block_opacity;logic signed[SCREEN_W-1:0]block_mean_x,block_mean_y;
    logic[PIXEL_COORD_W-1:0]bbox_x0,bbox_y0,bbox_x1,bbox_y1;logic[14:0]l00,l11;logic signed[15:0]l10;
    logic signed[5:0]coordinate_shift,factor_shift;logic keep,descriptor_overflow,raster_idle;logic[2:0]result_occupancy;
    logic[31:0]block_task_id;logic front_idle,front_retire_wait,front_protocol_error,raster_retire_wait,raster_protocol_error;
    logic[$clog2(LANES+1)-1:0]raster_active_lanes;
    gaussian_projection_sh_array #(.LANES(LANES),.GID_W(GID_W),.SEQ_W(SEQ_W),.EPOCH_W(EPOCH_W),
      .USE_SHARED_PROJECTION_PE(USE_SHARED_PROJECTION_PE),.SHARED_P_DOT3(SHARED_P_DOT3),.PE_DATA_W(PE_DATA_W),.PE_RESULT_W(PE_RESULT_W),
      .ENABLE_OPERAND_ISOLATION(ENABLE_OPERAND_ISOLATION))u_front(
      .clk_i(clk_i),.rst_ni(rst_ni),.shadow_mode_we_i(shadow_mode_we_i),.shadow_mode_i(shadow_mode_i),.mode_commit_i(mode_commit_i),
      .epoch_boundary_i(epoch_boundary_i),.downstream_empty_i(raster_idle),.active_mode_o(active_mode_o),.epoch_id_o(epoch_id_o),
      .mode_pending_o(mode_pending_o),.mode_commit_pulse_o(mode_commit_pulse_o),.mode_overrun_o(mode_overrun_o),
      .s_valid_i(s_valid_i),.s_ready_o(s_ready_o),.s_gid_i(s_gid_i),.s_seq_i(s_seq_i),
      .s_world_x_q16_i(s_world_x_q16_i),.s_world_y_q16_i(s_world_y_q16_i),.s_world_z_q16_i(s_world_z_q16_i),
      .s_qw_q20_i(s_qw_q20_i),.s_qx_q20_i(s_qx_q20_i),.s_qy_q20_i(s_qy_q20_i),.s_qz_q20_i(s_qz_q20_i),
      .s_scale_x_q20_i(s_scale_x_q20_i),.s_scale_y_q20_i(s_scale_y_q20_i),.s_scale_z_q20_i(s_scale_z_q20_i),
      .s_opacity_q12_i(s_opacity_q12_i),.s_coeff_q12_flat_i(s_coeff_q12_flat_i),
      .cfg_r00_q20_i(cfg_r00_q20_i),.cfg_r01_q20_i(cfg_r01_q20_i),.cfg_r02_q20_i(cfg_r02_q20_i),
      .cfg_r10_q20_i(cfg_r10_q20_i),.cfg_r11_q20_i(cfg_r11_q20_i),.cfg_r12_q20_i(cfg_r12_q20_i),
      .cfg_r20_q20_i(cfg_r20_q20_i),.cfg_r21_q20_i(cfg_r21_q20_i),.cfg_r22_q20_i(cfg_r22_q20_i),
      .cfg_tx_q16_i(cfg_tx_q16_i),.cfg_ty_q16_i(cfg_ty_q16_i),.cfg_tz_q16_i(cfg_tz_q16_i),
      .cfg_camera_x_q16_i(cfg_camera_x_q16_i),.cfg_camera_y_q16_i(cfg_camera_y_q16_i),.cfg_camera_z_q16_i(cfg_camera_z_q16_i),
      .cfg_fx_q16_i(cfg_fx_q16_i),.cfg_fy_q16_i(cfg_fy_q16_i),.cfg_cx_q16_i(cfg_cx_q16_i),.cfg_cy_q16_i(cfg_cy_q16_i),
      .cfg_near_q16_i(cfg_near_q16_i),.cfg_far_q16_i(cfg_far_q16_i),.cfg_regularizer_q8_i(cfg_regularizer_q8_i),
      .cfg_image_width_i(cfg_image_width_i),.cfg_image_height_i(cfg_image_height_i),
      .m_valid_o(block_valid),.m_ready_i(block_ready),.m_desc_o(block_desc),.m_block_x_o(block_x),.m_block_y_o(block_y),
      .m_r_q12_o(block_r),.m_g_q12_o(block_g),.m_b_q12_o(block_b),.m_first_o(block_first),.m_last_o(block_last),
      .m_culled_o(block_culled),.m_sh_fallback_o(sh_fallback),.m_numeric_overflow_o(numeric_overflow),
      .projection_active_mask_o(projection_active_mask_o),.sh_active_mask_o(sh_active_mask_o),
      .all_idle_o(front_idle),.retire_wait_o(front_retire_wait),.protocol_error_o(front_protocol_error),
      .stage_projection_busy_o(stage_projection_busy_o),
      .pe_req_valid_o(pe_req_valid_o),.pe_req_ready_i(pe_req_ready_i),.pe_lhs_o(pe_lhs_o),.pe_rhs_o(pe_rhs_o),
      .pe_acc_o(pe_acc_o),.pe_rsp_valid_i(pe_rsp_valid_i),.pe_rsp_ready_o(pe_rsp_ready_o),.pe_result_i(pe_result_i));
    ordered_gaussian_block_decoder #(.EPOCH_W(EPOCH_W),.GID_W(GID_W),.SEQ_W(SEQ_W),.SCREEN_W(SCREEN_W))u_decode(
      .desc_i(block_desc),.epoch_o(block_epoch),.gid_o(block_gid),.seq_o(block_seq),.opacity_q12_o(block_opacity),
      .mean_x_q8_o(block_mean_x),.mean_y_q8_o(block_mean_y),.bbox_x0_o(bbox_x0),.bbox_y0_o(bbox_y0),
      .bbox_x1_o(bbox_x1),.bbox_y1_o(bbox_y1),.l00_q12_o(l00),.l10_q12_o(l10),.l11_q12_o(l11),
      .coordinate_shift_o(coordinate_shift),.factor_shift_o(factor_shift),.keep_o(keep),.numeric_overflow_o(descriptor_overflow));
    assign block_task_id={{(32-SEQ_W){1'b0}},block_seq};
    gaussian_resource_mode_table #(.GROUP_LANES(1),.PROJECTION_LANES(LANES),.SH_LANES(LANES),.RASTER_LANES(LANES))u_raster_mode(
      .active_mode_i(active_mode_o),.group_active_lanes_o(),.projection_active_lanes_o(),.sh_active_lanes_o(),
      .raster_active_lanes_o(raster_active_lanes),.group_weight_o(),.projection_weight_o(),.raster_weight_o(),
      .shared_math_owner_o(),.aggressive_clock_gate_o());
    ordered_block_raster_frontend #(.LANES(LANES),.TASK_W(32),.BLOCK_W(32),.GID_W(GID_W),.EPOCH_W(EPOCH_W),.TILE_W(TILE_W),
      .COORD_W(SCREEN_W),.PIXEL_COORD_W(PIXEL_COORD_W),.PIXEL_ID_W(32),.STATE_ENTRIES(STATE_ENTRIES),
      .STATE_WINDOW_ENTRIES(STATE_WINDOW_ENTRIES),.STATE_MSHR_COUNT(STATE_MSHR_COUNT),
      .ENABLE_RESPONSE_BLEND_BYPASS(ENABLE_RESPONSE_BLEND_BYPASS),
      .ENABLE_BLEND_COMMIT_BYPASS(ENABLE_BLEND_COMMIT_BYPASS),
      .ENABLE_OPERAND_ISOLATION(ENABLE_OPERAND_ISOLATION),
      .ENABLE_SHAPE_BLOCK_REJECT(ENABLE_SHAPE_BLOCK_REJECT),
      .USE_STATE_CACHE_BACKEND(USE_STATE_CACHE_BACKEND),
      .USE_SHARED_RASTER_PE(USE_SHARED_RASTER_PE),
      .ENABLE_ALPHA_ZERO_SKIP(ENABLE_ALPHA_ZERO_SKIP))u_raster(
      .clk_i(clk_i),.rst_ni(rst_ni),.cfg_active_lanes_i(raster_active_lanes),
      .block_valid_i(block_valid),.block_ready_o(block_ready),.task_id_i(block_task_id),
      .gid_i(block_gid),.epoch_id_i(block_epoch),.block_x_i(block_x),.block_y_i(block_y),.bbox_x0_i(bbox_x0),.bbox_y0_i(bbox_y0),
      .bbox_x1_i(bbox_x1),.bbox_y1_i(bbox_y1),.mean_x_q8_i(block_mean_x),.mean_y_q8_i(block_mean_y),
      .color_r_q12_i(block_r),.color_g_q12_i(block_g),.color_b_q12_i(block_b),.l00_q12_i(l00),.l10_q12_i(l10),.l11_q12_i(l11),
      .coordinate_shift_i(coordinate_shift),.factor_shift_i(factor_shift),.opacity_q12_i(block_opacity),
      .gaussian_first_block_i(block_first),.gaussian_last_block_i(block_last),.culled_i(block_culled||!keep),
      .cfg_image_width_i(cfg_image_width_i),.cfg_image_height_i(cfg_image_height_i),.empty_or_culled_pulse_o(empty_or_culled_pulse_o),
      .shape_rejected_pulse_o(shape_rejected_pulse_o),
      .block_terminated_pulse_o(block_terminated_pulse_o),.skipped_terminated_pulse_o(skipped_terminated_pulse_o),
      .commit_valid_o(commit_valid_o),.commit_ready_i(commit_ready_i),.commit_task_id_o(commit_task_id_o),
      .commit_block_id_o(commit_block_id_o),.commit_gid_o(commit_gid_o),.commit_epoch_id_o(commit_epoch_id_o),
      .commit_alpha_q12_o(commit_alpha_q12_o),.commit_pass_alpha_o(commit_pass_alpha_o),.commit_pixel_id_o(commit_pixel_id_o),
      .commit_r_q12_o(commit_r_q12_o),.commit_g_q12_o(commit_g_q12_o),.commit_b_q12_o(commit_b_q12_o),
      .commit_t_q16_o(commit_t_q16_o),.commit_newly_terminated_o(commit_newly_terminated_o),
      .result_occupancy_o(result_occupancy),.active_mask_o(raster_active_mask_o),.retire_wait_o(raster_retire_wait),
      .protocol_error_o(raster_protocol_error),.idle_o(raster_idle),
      .state_miss_req_valid_o(state_miss_req_valid_o),.state_miss_req_ready_i(state_miss_req_ready_i),
      .state_miss_req_tag_o(state_miss_req_tag_o),.state_miss_req_pixel_id_o(state_miss_req_pixel_id_o),.state_miss_rsp_valid_i(state_miss_rsp_valid_i),
      .state_miss_rsp_tag_i(state_miss_rsp_tag_i),
      .state_miss_rsp_ready_o(state_miss_rsp_ready_o),.state_miss_rsp_error_i(state_miss_rsp_error_i),
      .state_miss_rsp_data_i(state_miss_rsp_data_i),.state_cache_error_o(state_cache_error_o),
      .state_cache_idle_o(state_cache_idle_o),
      .r_pe_req_valid_o(r_pe_req_valid_o),.r_pe_req_ready_i(r_pe_req_ready_i),
      .r_pe_lhs_o(r_pe_lhs_o),.r_pe_rhs_o(r_pe_rhs_o),
      .r_pe_rsp_valid_i(r_pe_rsp_valid_i),.r_pe_rsp_ready_o(r_pe_rsp_ready_o),.r_pe_result_i(r_pe_result_i));
    assign retire_wait_o=front_retire_wait||raster_retire_wait;
    assign protocol_error_o=front_protocol_error||raster_protocol_error;
    assign all_idle_o=front_idle&&raster_idle&&!block_valid;
    assign stage_raster_busy_o=!raster_idle;
    assign block_candidate_pulse_o=block_valid&&block_ready&&!block_culled&&keep;
endmodule
