// Raster front end for an already ordered Gaussian block stream. SH RGB is an
// input Gaussian attribute and is reused for every pixel in every block; this
// wrapper does not perform per-pixel SH work and does not create tile bins.
// Multiple identical instances may be enabled by the epoch-safe R resource
// mode, while ordering remains the responsibility of ordered Gaussian retire.
module ordered_block_raster_frontend #(
    parameter int unsigned LANES=4,
    parameter int unsigned TASK_W=32,parameter int unsigned BLOCK_W=32,
    parameter int unsigned GID_W=32,parameter int unsigned EPOCH_W=16,
    parameter int unsigned TILE_W=12,parameter int unsigned COORD_W=27,
    parameter int unsigned PIXEL_COORD_W=16,parameter int unsigned PIXEL_ID_W=32,
    parameter int unsigned STATE_ENTRIES=4096,parameter int unsigned STATE_WINDOW_ENTRIES=2,
    parameter int unsigned STATE_MSHR_COUNT=2,
    parameter bit ENABLE_RESPONSE_BLEND_BYPASS=1'b0,
    parameter bit ENABLE_BLEND_COMMIT_BYPASS=1'b0,
    parameter bit ENABLE_OPERAND_ISOLATION=1'b0,
    parameter bit ENABLE_SHAPE_BLOCK_REJECT=1'b0,
    parameter bit USE_STATE_CACHE_BACKEND=1'b0,
    parameter bit USE_SHARED_RASTER_PE=1'b0,
    parameter bit ENABLE_ALPHA_ZERO_SKIP=1'b0
) (
    input logic clk_i,input logic rst_ni,
    input logic[$clog2(LANES+1)-1:0]cfg_active_lanes_i,
    input logic block_valid_i,output logic block_ready_o,
    input logic[TASK_W-1:0]task_id_i,input logic[GID_W-1:0]gid_i,input logic[EPOCH_W-1:0]epoch_id_i,
    input logic[TILE_W-1:0]block_x_i,block_y_i,
    input logic[PIXEL_COORD_W-1:0]bbox_x0_i,bbox_y0_i,bbox_x1_i,bbox_y1_i,
    input logic signed[COORD_W-1:0]mean_x_q8_i,mean_y_q8_i,
    input logic[12:0]color_r_q12_i,color_g_q12_i,color_b_q12_i,
    input logic[14:0]l00_q12_i,input logic signed[15:0]l10_q12_i,input logic[14:0]l11_q12_i,
    input logic signed[5:0]coordinate_shift_i,factor_shift_i,input logic[12:0]opacity_q12_i,
    input logic gaussian_first_block_i,gaussian_last_block_i,culled_i,
    input logic[PIXEL_COORD_W-1:0]cfg_image_width_i,cfg_image_height_i,
    output logic empty_or_culled_pulse_o,output logic shape_rejected_pulse_o,output logic block_terminated_pulse_o,
    output logic skipped_terminated_pulse_o,
    output logic commit_valid_o,input logic commit_ready_i,
    output logic[TASK_W-1:0]commit_task_id_o,output logic[BLOCK_W-1:0]commit_block_id_o,
    output logic[GID_W-1:0]commit_gid_o,output logic[EPOCH_W-1:0]commit_epoch_id_o,
    output logic[12:0]commit_alpha_q12_o,output logic commit_pass_alpha_o,
    output logic[PIXEL_ID_W-1:0]commit_pixel_id_o,
    output logic[12:0]commit_r_q12_o,commit_g_q12_o,commit_b_q12_o,
    output logic[15:0]commit_t_q16_o,output logic commit_newly_terminated_o,
    output logic[2:0]result_occupancy_o,output logic[LANES-1:0]active_mask_o,
    output logic retire_wait_o,protocol_error_o,output logic idle_o,
    output logic state_miss_req_valid_o,input logic state_miss_req_ready_i,
    output logic[1:0]state_miss_req_tag_o,output logic[PIXEL_ID_W-1:0]state_miss_req_pixel_id_o,input logic state_miss_rsp_valid_i,
    output logic state_miss_rsp_ready_o,input logic[1:0]state_miss_rsp_tag_i,input logic state_miss_rsp_error_i,
    input logic[127:0]state_miss_rsp_data_i,output logic state_cache_error_o,state_cache_idle_o,
    output logic r_pe_req_valid_o,input logic r_pe_req_ready_i,
    output logic signed[31:0]r_pe_lhs_o,r_pe_rhs_o,
    input logic r_pe_rsp_valid_i,output logic r_pe_rsp_ready_o,
    input logic signed[64:0]r_pe_result_i
);
    localparam int unsigned META_W=EPOCH_W+GID_W+BLOCK_W+TASK_W+3*13+15+16+15+6+6+13;
    logic[META_W-1:0]block_meta,pixel_meta;logic[BLOCK_W-1:0]input_block_id;
    logic[2*PIXEL_COORD_W-1:0]blocks_per_row,block_linear;
    logic pixel_valid,pixel_ready,expand_block_ready,expand_empty_pulse,shape_reject_proof,shape_reject_accept;
    logic[PIXEL_COORD_W-1:0]pixel_x,pixel_y;
    logic[PIXEL_ID_W-1:0]pixel_id;logic[5:0]pixel_in_block;logic signed[15:0]pixel_dx,pixel_dy;
    logic[EPOCH_W-1:0]pixel_epoch;logic[GID_W-1:0]pixel_gid;logic[BLOCK_W-1:0]pixel_block_id;
    logic[TASK_W-1:0]pixel_task;logic[12:0]pixel_r,pixel_g,pixel_b,pixel_opacity;
    logic[14:0]pixel_l00,pixel_l11;logic signed[15:0]pixel_l10;logic raster_idle;
    logic signed[5:0]pixel_coordinate_shift,pixel_factor_shift;
    assign blocks_per_row=({{PIXEL_COORD_W{1'b0}},cfg_image_width_i}+7)>>3;
    assign block_linear=block_y_i*blocks_per_row+block_x_i;
    assign input_block_id=block_linear[BLOCK_W-1:0];
    assign block_meta={epoch_id_i,gid_i,input_block_id,task_id_i,color_r_q12_i,color_g_q12_i,color_b_q12_i,
      l00_q12_i,l10_q12_i,l11_q12_i,coordinate_shift_i,factor_shift_i,opacity_q12_i};
    if(ENABLE_SHAPE_BLOCK_REJECT)begin:gen_shape_reject
      gaussian_shape_block_reject #(.TILE_W(TILE_W),.PIXEL_W(PIXEL_COORD_W),.SCREEN_W(COORD_W))u_shape_reject(
        .block_x_i(block_x_i),.block_y_i(block_y_i),
        .bbox_x0_i(bbox_x0_i),.bbox_x1_i(bbox_x1_i),.bbox_y0_i(bbox_y0_i),.bbox_y1_i(bbox_y1_i),
        .image_width_i(cfg_image_width_i),.image_height_i(cfg_image_height_i),.mean_y_q8_i(mean_y_q8_i),
        .coordinate_shift_i(coordinate_shift_i),.factor_shift_i(factor_shift_i),
        .l11_q12_i(l11_q12_i),.opacity_q12_i(opacity_q12_i),.reject_o(shape_reject_proof));
      assign shape_reject_accept=block_valid_i&&!culled_i&&shape_reject_proof;
      always_ff@(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)shape_rejected_pulse_o<=1'b0;
        else shape_rejected_pulse_o<=shape_reject_accept;
      end
    end else begin:gen_no_shape_reject
      assign shape_reject_proof=1'b0;
      assign shape_reject_accept=1'b0;
      assign shape_rejected_pulse_o=1'b0;
    end
    assign block_ready_o=shape_reject_accept?1'b1:expand_block_ready;
    gaussian_block_pixel_expander #(.META_W(META_W),.TILE_W(TILE_W),.PIXEL_W(PIXEL_COORD_W),
      .SCREEN_W(COORD_W),.LINEAR_W(PIXEL_ID_W))u_expand(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(block_valid_i&&!shape_reject_accept),.s_ready_o(expand_block_ready),.s_meta_i(block_meta),
      .s_block_x_i(block_x_i),.s_block_y_i(block_y_i),.s_bbox_x0_i(bbox_x0_i),.s_bbox_y0_i(bbox_y0_i),
      .s_bbox_x1_i(bbox_x1_i),.s_bbox_y1_i(bbox_y1_i),.s_mean_x_q8_i(mean_x_q8_i),.s_mean_y_q8_i(mean_y_q8_i),
      .s_coordinate_shift_i(coordinate_shift_i),.s_gaussian_first_block_i(gaussian_first_block_i),
      .s_gaussian_last_block_i(gaussian_last_block_i),.s_culled_i(culled_i),
      .cfg_image_width_i(cfg_image_width_i),.cfg_image_height_i(cfg_image_height_i),
      .m_valid_o(pixel_valid),.m_ready_i(pixel_ready),.m_meta_o(pixel_meta),.m_pixel_x_o(pixel_x),.m_pixel_y_o(pixel_y),
      .m_pixel_id_o(pixel_id),.m_pixel_in_block_o(pixel_in_block),.m_dx_q10_o(pixel_dx),.m_dy_q10_o(pixel_dy),
      .m_first_pixel_o(),.m_last_pixel_o(),.m_gaussian_first_block_o(),.m_gaussian_last_block_o(),
      .empty_or_culled_pulse_o(expand_empty_pulse));
    assign empty_or_culled_pulse_o=expand_empty_pulse||shape_rejected_pulse_o;
    assign {pixel_epoch,pixel_gid,pixel_block_id,pixel_task,pixel_r,pixel_g,pixel_b,
      pixel_l00,pixel_l10,pixel_l11,pixel_coordinate_shift,pixel_factor_shift,pixel_opacity}=pixel_meta;
    raster_pair_shell #(.LANES(LANES),.TASK_W(TASK_W),.BLOCK_W(BLOCK_W),.GID_W(GID_W),.EPOCH_W(EPOCH_W),
      .PIXEL_W(PIXEL_ID_W),.STATE_ENTRIES(STATE_ENTRIES),.STATE_WINDOW_ENTRIES(STATE_WINDOW_ENTRIES),
      .STATE_MSHR_COUNT(STATE_MSHR_COUNT),
      .ENABLE_RESPONSE_BLEND_BYPASS(ENABLE_RESPONSE_BLEND_BYPASS),
      .ENABLE_BLEND_COMMIT_BYPASS(ENABLE_BLEND_COMMIT_BYPASS),
      .ENABLE_OPERAND_ISOLATION(ENABLE_OPERAND_ISOLATION),
      .USE_STATE_CACHE_BACKEND(USE_STATE_CACHE_BACKEND),
      .USE_SHARED_RASTER_PE(USE_SHARED_RASTER_PE),
      .ENABLE_ALPHA_ZERO_SKIP(ENABLE_ALPHA_ZERO_SKIP))u_raster(
      .clk_i(clk_i),.rst_ni(rst_ni),.cfg_active_lanes_i(cfg_active_lanes_i),.task_valid_i(pixel_valid),.task_ready_o(pixel_ready),
      .task_id_i(pixel_task),.block_id_i(pixel_block_id),.gid_i(pixel_gid),.epoch_id_i(pixel_epoch),
      .pixel_id_i(pixel_id),.pixel_in_block_i(pixel_in_block),.color_r_q12_i(pixel_r),.color_g_q12_i(pixel_g),.color_b_q12_i(pixel_b),
      .alpha_dx_q10_i(pixel_dx),.alpha_dy_q10_i(pixel_dy),.alpha_l00_q12_i(pixel_l00),.alpha_l10_q12_i(pixel_l10),
      .alpha_l11_q12_i(pixel_l11),.alpha_coordinate_shift_i(pixel_coordinate_shift),.alpha_factor_shift_i(pixel_factor_shift),
      .alpha_opacity_q12_i(pixel_opacity),.block_terminated_pulse_o(block_terminated_pulse_o),
      .skipped_terminated_pulse_o(skipped_terminated_pulse_o),.commit_valid_o(commit_valid_o),.commit_ready_i(commit_ready_i),
      .commit_task_id_o(commit_task_id_o),.commit_block_id_o(commit_block_id_o),.commit_gid_o(commit_gid_o),
      .commit_epoch_id_o(commit_epoch_id_o),.commit_alpha_q12_o(commit_alpha_q12_o),.commit_pass_alpha_o(commit_pass_alpha_o),
      .commit_pixel_id_o(commit_pixel_id_o),.commit_r_q12_o(commit_r_q12_o),.commit_g_q12_o(commit_g_q12_o),
      .commit_b_q12_o(commit_b_q12_o),.commit_t_q16_o(commit_t_q16_o),.commit_newly_terminated_o(commit_newly_terminated_o),
      .result_occupancy_o(result_occupancy_o),.active_mask_o(active_mask_o),.retire_wait_o(retire_wait_o),
      .protocol_error_o(protocol_error_o),.idle_o(raster_idle),
      .state_miss_req_valid_o(state_miss_req_valid_o),.state_miss_req_ready_i(state_miss_req_ready_i),
      .state_miss_req_tag_o(state_miss_req_tag_o),.state_miss_req_pixel_id_o(state_miss_req_pixel_id_o),.state_miss_rsp_valid_i(state_miss_rsp_valid_i),
      .state_miss_rsp_tag_i(state_miss_rsp_tag_i),
      .state_miss_rsp_ready_o(state_miss_rsp_ready_o),.state_miss_rsp_error_i(state_miss_rsp_error_i),
      .state_miss_rsp_data_i(state_miss_rsp_data_i),.state_cache_error_o(state_cache_error_o),
      .state_cache_idle_o(state_cache_idle_o),
      .r_pe_req_valid_o(r_pe_req_valid_o),.r_pe_req_ready_i(r_pe_req_ready_i),
      .r_pe_lhs_o(r_pe_lhs_o),.r_pe_rhs_o(r_pe_rhs_o),
      .r_pe_rsp_valid_i(r_pe_rsp_valid_i),.r_pe_rsp_ready_o(r_pe_rsp_ready_o),.r_pe_result_i(r_pe_result_i));
    // block_ready_o means the pixel expander holds no block. Raster latency is
    // represented by its result occupancy; mode commits also require upstream
    // to have retired every source Gaussian before using this idle indication.
    // External ready may acknowledge a proven-empty look-ahead block while
    // the current block is still expanding; only the expander's own ready is
    // a valid idle indication for mode/epoch completion.
    assign idle_o=expand_block_ready&&raster_idle;
endmodule
