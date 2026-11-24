// Sorted-Gaussian to rendered-pixel integration boundary. Sorting transports
// only GID/sequence/depth metadata; the complete record is fetched exactly once
// per ordered Gaussian and then reused through projection, SH and all 8x8
// blocks. This is deliberately not a Gaussian-tile attribute table.
module gaussian_sorted_render_pipeline #(
    parameter bit ENABLE_COMPRESSED_ATTRIBUTES=1'b0,
    parameter int unsigned ATTR_DEPTH=1024,parameter int unsigned LANES=4,
    parameter int unsigned GID_W=32,parameter int unsigned SEQ_W=16,
    parameter int unsigned EPOCH_W=16,parameter int unsigned DEPTH_W=27,
    parameter int unsigned GROUP_W=2,parameter int unsigned COORD_W=27,
    parameter int unsigned QUAT_W=22,parameter int unsigned SCALE_W=24,
    parameter int unsigned ROT_W=22,parameter int unsigned COV2_W=35,
    parameter int unsigned PIXEL_COORD_W=16,parameter int unsigned STATE_ENTRIES=4096,
    parameter int unsigned STATE_WINDOW_ENTRIES=2,parameter int unsigned STATE_MSHR_COUNT=2,
    parameter bit ENABLE_RESPONSE_BLEND_BYPASS=1'b0,
    parameter bit ENABLE_BLEND_COMMIT_BYPASS=1'b0,
    parameter bit ENABLE_OPERAND_ISOLATION=1'b0,
    parameter bit ENABLE_SHAPE_BLOCK_REJECT=1'b0,
    parameter bit USE_SHARED_PROJECTION_PE=1'b0,
    parameter bit SHARED_P_DOT3=1'b0,
    parameter bit USE_SHARED_RASTER_PE=1'b0,
    parameter bit ENABLE_PIXEL_TERMINATION_SKIP=1'b0,
    parameter bit ENABLE_ALPHA_ZERO_SKIP=1'b0,
    parameter int unsigned PE_DATA_W=32,parameter int unsigned PE_RESULT_W=2*PE_DATA_W+1,
    parameter int unsigned COEFF_W=18,
    parameter bit USE_EXTERNAL_ATTR_BACKEND=1'b0,parameter bit USE_STATE_CACHE_BACKEND=1'b0,
    parameter int unsigned COEFFS=16,parameter int unsigned COEFF_FLAT_W=3*COEFFS*COEFF_W,
    parameter int unsigned ATTR_W=3*COORD_W+4*QUAT_W+3*SCALE_W+13+COEFF_FLAT_W+(ENABLE_COMPRESSED_ATTRIBUTES?249:0)
) (
    input logic new_frame_i,input logic cfg_cov_q24_i,
    input logic clk_i,input logic rst_ni,
    input logic attr_clear_valid_i,attr_clear_errors_i,input logic attr_write_en_i,
    input logic[GID_W-1:0]attr_write_gid_i,
    input logic signed[COORD_W-1:0]attr_write_world_x_q16_i,attr_write_world_y_q16_i,attr_write_world_z_q16_i,
    input logic signed[QUAT_W-1:0]attr_write_qw_q20_i,attr_write_qx_q20_i,attr_write_qy_q20_i,attr_write_qz_q20_i,
    input logic[SCALE_W-1:0]attr_write_scale_x_q20_i,attr_write_scale_y_q20_i,attr_write_scale_z_q20_i,
    input logic[12:0]attr_write_opacity_q12_i,input logic[COEFF_FLAT_W-1:0]attr_write_coeff_q12_flat_i,
    output logic attr_req_valid_o,input logic attr_req_ready_i,output logic[GID_W-1:0]attr_req_gid_o,
    input logic attr_rsp_valid_i,output logic attr_rsp_ready_o,input logic attr_rsp_error_i,
    input logic[ATTR_W-1:0]attr_rsp_data_i,
    input logic sorted_valid_i,output logic sorted_ready_o,input logic signed[DEPTH_W-1:0]sorted_depth_i,
    input logic[GID_W-1:0]sorted_gid_i,input logic[SEQ_W-1:0]sorted_seq_i,
    input logic[GROUP_W-1:0]sorted_group_i,input logic sorted_group_first_i,sorted_group_last_i,
    input logic shadow_mode_we_i,input logic[1:0]shadow_mode_i,input logic mode_commit_i,input logic epoch_boundary_i,
    output logic[1:0]active_mode_o,output logic[15:0]epoch_id_o,
    output logic mode_pending_o,mode_commit_pulse_o,mode_overrun_o,
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
    output logic commit_newly_terminated_o,block_terminated_pulse_o,skipped_terminated_pulse_o,empty_or_culled_pulse_o,
    output logic shape_rejected_pulse_o,
    output logic all_idle_o,retire_wait_o,protocol_error_o,
    output logic stage_projection_busy_o,stage_raster_busy_o,block_candidate_pulse_o,
    output logic[LANES-1:0]projection_active_mask_o,sh_active_mask_o,raster_active_mask_o,
    output logic attribute_read_pulse_o,attribute_invalid_sticky_o,attribute_unloaded_sticky_o,attribute_write_invalid_sticky_o,
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
    logic backend_req_valid,backend_req_ready,backend_rsp_valid,backend_rsp_ready,backend_rsp_error;
    logic backend_in_range,backend_loaded,store_invalid_read,store_unloaded,store_invalid_write;
    localparam int LEGACY_ATTR_W=3*COORD_W+4*QUAT_W+3*SCALE_W+13+COEFF_FLAT_W;
    logic[LEGACY_ATTR_W-1:0]local_backend_data;
    logic[248:0]issue_aux;
    logic[GID_W-1:0]backend_req_gid;logic[ATTR_W-1:0]backend_rsp_data,issue_attr_data;
    logic issue_valid,issue_ready,issue_source_ready,issue_idle,issue_invalid,issue_unloaded,issue_backend_error;
    logic signed[DEPTH_W-1:0]issue_depth;logic[GID_W-1:0]issue_gid;logic[SEQ_W-1:0]issue_seq;
    logic[GROUP_W-1:0]issue_group;logic issue_group_first,issue_group_last;
    logic signed[COORD_W-1:0]attr_wx,attr_wy,attr_wz;logic signed[QUAT_W-1:0]attr_qw,attr_qx,attr_qy,attr_qz;
    logic[SCALE_W-1:0]attr_sx,attr_sy,attr_sz;logic[12:0]attr_opacity;logic[COEFF_FLAT_W-1:0]attr_coeff;
    logic render_idle,render_pending,render_overrun,commit_hold_q,local_overrun_q,forward_commit,allow_sorted;

    generate
      if(USE_EXTERNAL_ATTR_BACKEND)begin:g_external_attr
        assign attr_req_valid_o=backend_req_valid;assign backend_req_ready=attr_req_ready_i;
        assign attr_req_gid_o=backend_req_gid;assign backend_rsp_valid=attr_rsp_valid_i;
        assign attr_rsp_ready_o=backend_rsp_ready;assign backend_rsp_error=attr_rsp_error_i;
        assign backend_rsp_data=attr_rsp_data_i;assign backend_in_range=1'b1;assign backend_loaded=1'b1;
        assign store_invalid_read=1'b0;assign store_unloaded=1'b0;assign store_invalid_write=1'b0;
      end else begin:g_sram_attr
        gaussian_attribute_sram_backend #(.DEPTH(ATTR_DEPTH),.GID_W(GID_W),.COORD_W(COORD_W),
          .QUAT_W(QUAT_W),.SCALE_W(SCALE_W),.COEFF_W(COEFF_W),.COEFFS(COEFFS))u_attr(
          .clk_i(clk_i),.rst_ni(rst_ni),.clear_valid_i(attr_clear_valid_i),.clear_errors_i(attr_clear_errors_i),
          .write_en_i(attr_write_en_i),.write_gid_i(attr_write_gid_i),
          .write_world_x_q16_i(attr_write_world_x_q16_i),.write_world_y_q16_i(attr_write_world_y_q16_i),
          .write_world_z_q16_i(attr_write_world_z_q16_i),.write_qw_q20_i(attr_write_qw_q20_i),
          .write_qx_q20_i(attr_write_qx_q20_i),.write_qy_q20_i(attr_write_qy_q20_i),
          .write_qz_q20_i(attr_write_qz_q20_i),.write_scale_x_q20_i(attr_write_scale_x_q20_i),
          .write_scale_y_q20_i(attr_write_scale_y_q20_i),.write_scale_z_q20_i(attr_write_scale_z_q20_i),
          .write_opacity_q12_i(attr_write_opacity_q12_i),.write_coeff_q12_flat_i(attr_write_coeff_q12_flat_i),
          .req_valid_i(backend_req_valid),.req_ready_o(backend_req_ready),.req_gid_i(backend_req_gid),
          .rsp_valid_o(backend_rsp_valid),.rsp_ready_i(backend_rsp_ready),.rsp_in_range_o(backend_in_range),
          .rsp_loaded_o(backend_loaded),.rsp_error_o(backend_rsp_error),.rsp_data_o(local_backend_data),
          .invalid_write_sticky_o(store_invalid_write),.invalid_read_sticky_o(store_invalid_read),
          .unloaded_read_sticky_o(store_unloaded));
        assign backend_rsp_data=ATTR_W'(local_backend_data);
        assign attr_req_valid_o=1'b0;assign attr_req_gid_o='0;assign attr_rsp_ready_o=1'b0;
      end
    endgenerate

    // A new commit request freezes sorted issue immediately. Any request that
    // was already accepted drains into the old epoch before forward_commit.
    assign allow_sorted=!commit_hold_q&&!mode_commit_i&&!render_pending;
    ordered_gaussian_attribute_issue #(.ATTR_W(ATTR_W),.GID_W(GID_W),.SEQ_W(SEQ_W),.DEPTH_W(DEPTH_W),.GROUP_W(GROUP_W),
      .COORD_W(COORD_W),.QUAT_W(QUAT_W),.SCALE_W(SCALE_W),.COEFF_W(COEFF_W),.COEFFS(COEFFS))u_issue(
      .clk_i(clk_i),.rst_ni(rst_ni),.clear_errors_i(attr_clear_errors_i),
      .s_valid_i(sorted_valid_i&&allow_sorted),.s_ready_o(issue_source_ready),.s_depth_i(sorted_depth_i),.s_gid_i(sorted_gid_i),
      .s_seq_i(sorted_seq_i),.s_group_i(sorted_group_i),.s_group_first_i(sorted_group_first_i),.s_group_last_i(sorted_group_last_i),
      .attr_req_valid_o(backend_req_valid),.attr_req_ready_i(backend_req_ready),.attr_req_gid_o(backend_req_gid),
      .attr_rsp_valid_i(backend_rsp_valid),.attr_rsp_ready_o(backend_rsp_ready),
      .attr_rsp_in_range_i(backend_in_range),.attr_rsp_loaded_i(backend_loaded),
      .attr_rsp_error_i(backend_rsp_error),.attr_rsp_data_i(backend_rsp_data),
      .m_valid_o(issue_valid),.m_ready_i(issue_ready),
      .m_depth_o(issue_depth),.m_gid_o(issue_gid),.m_seq_o(issue_seq),.m_group_o(issue_group),
      .m_group_first_o(issue_group_first),.m_group_last_o(issue_group_last),
      .m_attr_data_o(issue_attr_data),.invalid_gid_sticky_o(issue_invalid),
      .unloaded_gid_sticky_o(issue_unloaded),.backend_error_sticky_o(issue_backend_error),
      .read_pulse_o(attribute_read_pulse_o),.idle_o(issue_idle));
    assign {attr_wx,attr_wy,attr_wz,attr_qw,attr_qx,attr_qy,attr_qz,
      attr_sx,attr_sy,attr_sz,attr_opacity,attr_coeff}=issue_attr_data[LEGACY_ATTR_W-1:0];
    assign issue_aux=ENABLE_COMPRESSED_ATTRIBUTES?249'(issue_attr_data>>LEGACY_ATTR_W):249'd0;
    assign sorted_ready_o=issue_source_ready&&allow_sorted;
    assign forward_commit=commit_hold_q&&issue_idle;
    gaussian_ordered_render_frontend #(.ENABLE_COMPRESSED_ATTRIBUTES(ENABLE_COMPRESSED_ATTRIBUTES),.LANES(LANES),.GID_W(GID_W),.SEQ_W(SEQ_W),.EPOCH_W(EPOCH_W),
      .COORD_W(COORD_W),.QUAT_W(QUAT_W),.SCALE_W(SCALE_W),.ROT_W(ROT_W),.COV2_W(COV2_W),
      .PIXEL_COORD_W(PIXEL_COORD_W),.STATE_ENTRIES(STATE_ENTRIES),
      .STATE_WINDOW_ENTRIES(STATE_WINDOW_ENTRIES),.STATE_MSHR_COUNT(STATE_MSHR_COUNT),
      .ENABLE_RESPONSE_BLEND_BYPASS(ENABLE_RESPONSE_BLEND_BYPASS),
      .ENABLE_BLEND_COMMIT_BYPASS(ENABLE_BLEND_COMMIT_BYPASS),
      .ENABLE_OPERAND_ISOLATION(ENABLE_OPERAND_ISOLATION),
      .ENABLE_SHAPE_BLOCK_REJECT(ENABLE_SHAPE_BLOCK_REJECT),
      .USE_STATE_CACHE_BACKEND(USE_STATE_CACHE_BACKEND),
      .COEFF_W(COEFF_W),.COEFFS(COEFFS),.USE_SHARED_PROJECTION_PE(USE_SHARED_PROJECTION_PE),.SHARED_P_DOT3(SHARED_P_DOT3),
      .USE_SHARED_RASTER_PE(USE_SHARED_RASTER_PE),
      .ENABLE_PIXEL_TERMINATION_SKIP(ENABLE_PIXEL_TERMINATION_SKIP),
      .ENABLE_ALPHA_ZERO_SKIP(ENABLE_ALPHA_ZERO_SKIP),
      .PE_DATA_W(PE_DATA_W),.PE_RESULT_W(PE_RESULT_W))u_render(
      .new_frame_i(new_frame_i),.cfg_cov_q24_i(cfg_cov_q24_i),.clk_i(clk_i),.rst_ni(rst_ni),.shadow_mode_we_i(shadow_mode_we_i),.shadow_mode_i(shadow_mode_i),
      .mode_commit_i(forward_commit),.epoch_boundary_i(epoch_boundary_i),.active_mode_o(active_mode_o),.epoch_id_o(epoch_id_o),
      .mode_pending_o(render_pending),.mode_commit_pulse_o(mode_commit_pulse_o),.mode_overrun_o(render_overrun),
      .s_valid_i(issue_valid),.s_ready_o(issue_ready),.s_gid_i(issue_gid),.s_seq_i(issue_seq),
      .s_world_x_q16_i(attr_wx),.s_world_y_q16_i(attr_wy),.s_world_z_q16_i(attr_wz),
      .s_qw_q20_i(attr_qw),.s_qx_q20_i(attr_qx),.s_qy_q20_i(attr_qy),.s_qz_q20_i(attr_qz),
      .s_scale_x_q20_i(attr_sx),.s_scale_y_q20_i(attr_sy),.s_scale_z_q20_i(attr_sz),
      .s_attr_aux_i(issue_aux),.s_opacity_q12_i(attr_opacity),.s_coeff_q12_flat_i(attr_coeff),
      .cfg_r00_q20_i(cfg_r00_q20_i),.cfg_r01_q20_i(cfg_r01_q20_i),.cfg_r02_q20_i(cfg_r02_q20_i),
      .cfg_r10_q20_i(cfg_r10_q20_i),.cfg_r11_q20_i(cfg_r11_q20_i),.cfg_r12_q20_i(cfg_r12_q20_i),
      .cfg_r20_q20_i(cfg_r20_q20_i),.cfg_r21_q20_i(cfg_r21_q20_i),.cfg_r22_q20_i(cfg_r22_q20_i),
      .cfg_tx_q16_i(cfg_tx_q16_i),.cfg_ty_q16_i(cfg_ty_q16_i),.cfg_tz_q16_i(cfg_tz_q16_i),
      .cfg_camera_x_q16_i(cfg_camera_x_q16_i),.cfg_camera_y_q16_i(cfg_camera_y_q16_i),.cfg_camera_z_q16_i(cfg_camera_z_q16_i),
      .cfg_fx_q16_i(cfg_fx_q16_i),.cfg_fy_q16_i(cfg_fy_q16_i),.cfg_cx_q16_i(cfg_cx_q16_i),.cfg_cy_q16_i(cfg_cy_q16_i),
      .cfg_near_q16_i(cfg_near_q16_i),.cfg_far_q16_i(cfg_far_q16_i),.cfg_regularizer_q8_i(cfg_regularizer_q8_i),
      .cfg_image_width_i(cfg_image_width_i),.cfg_image_height_i(cfg_image_height_i),
      .commit_valid_o(commit_valid_o),.commit_ready_i(commit_ready_i),.commit_task_id_o(commit_task_id_o),.commit_block_id_o(commit_block_id_o),
      .commit_gid_o(commit_gid_o),.commit_epoch_id_o(commit_epoch_id_o),.commit_alpha_q12_o(commit_alpha_q12_o),
      .commit_pass_alpha_o(commit_pass_alpha_o),.commit_pixel_id_o(commit_pixel_id_o),.commit_r_q12_o(commit_r_q12_o),
      .commit_g_q12_o(commit_g_q12_o),.commit_b_q12_o(commit_b_q12_o),.commit_t_q16_o(commit_t_q16_o),
      .commit_newly_terminated_o(commit_newly_terminated_o),.block_terminated_pulse_o(block_terminated_pulse_o),
      .skipped_terminated_pulse_o(skipped_terminated_pulse_o),.empty_or_culled_pulse_o(empty_or_culled_pulse_o),
      .shape_rejected_pulse_o(shape_rejected_pulse_o),
      .all_idle_o(render_idle),.retire_wait_o(retire_wait_o),.protocol_error_o(protocol_error_o),
      .stage_projection_busy_o(stage_projection_busy_o),.stage_raster_busy_o(stage_raster_busy_o),
      .block_candidate_pulse_o(block_candidate_pulse_o),
      .projection_active_mask_o(projection_active_mask_o),.sh_active_mask_o(sh_active_mask_o),
      .raster_active_mask_o(raster_active_mask_o),
      .state_miss_req_valid_o(state_miss_req_valid_o),.state_miss_req_ready_i(state_miss_req_ready_i),
      .state_miss_req_tag_o(state_miss_req_tag_o),.state_miss_req_pixel_id_o(state_miss_req_pixel_id_o),.state_miss_rsp_valid_i(state_miss_rsp_valid_i),
      .state_miss_rsp_tag_i(state_miss_rsp_tag_i),
      .state_miss_rsp_ready_o(state_miss_rsp_ready_o),.state_miss_rsp_error_i(state_miss_rsp_error_i),
      .state_miss_rsp_data_i(state_miss_rsp_data_i),.state_cache_error_o(state_cache_error_o),
      .state_cache_idle_o(state_cache_idle_o),
      .pe_req_valid_o(pe_req_valid_o),.pe_req_ready_i(pe_req_ready_i),.pe_lhs_o(pe_lhs_o),.pe_rhs_o(pe_rhs_o),
      .pe_acc_o(pe_acc_o),.pe_rsp_valid_i(pe_rsp_valid_i),.pe_rsp_ready_o(pe_rsp_ready_o),.pe_result_i(pe_result_i),
      .r_pe_req_valid_o(r_pe_req_valid_o),.r_pe_req_ready_i(r_pe_req_ready_i),
      .r_pe_lhs_o(r_pe_lhs_o),.r_pe_rhs_o(r_pe_rhs_o),
      .r_pe_rsp_valid_i(r_pe_rsp_valid_i),.r_pe_rsp_ready_o(r_pe_rsp_ready_o),.r_pe_result_i(r_pe_result_i));

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin commit_hold_q<=0;local_overrun_q<=0;end
      else begin
        if(mode_commit_i)begin
          if(commit_hold_q||render_pending)local_overrun_q<=1;
          else commit_hold_q<=1;
        end
        if(forward_commit)commit_hold_q<=0;
        if(attr_clear_errors_i)local_overrun_q<=0;
      end
    end
    assign mode_pending_o=commit_hold_q||render_pending;
    assign mode_overrun_o=local_overrun_q||render_overrun;
    assign attribute_invalid_sticky_o=issue_invalid||issue_backend_error||store_invalid_read;
    assign attribute_unloaded_sticky_o=issue_unloaded||store_unloaded;
    assign attribute_write_invalid_sticky_o=store_invalid_write;
    assign all_idle_o=issue_idle&&render_idle&&!commit_hold_q&&!render_pending;
`ifndef SYNTHESIS
    assert property(@(posedge clk_i)disable iff(!rst_ni)forward_commit|->issue_idle);
`endif
endmodule
