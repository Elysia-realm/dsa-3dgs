// Legacy compatibility top for early APB/raster unit tests only.  It is not
// the production accelerator top and is deliberately excluded from
// verification/rtl/system_top_sources.f; gs_accel_system_top is authoritative.
// No Gaussian-tile bin or per-tile sorting belongs on either path.
module gs_accel_top #(
    parameter int unsigned APB_ADDR_W = 12
) (
    input  logic                 clk_i,
    input  logic                 rst_ni,
    input  logic                 psel_i,
    input  logic                 penable_i,
    input  logic                 pwrite_i,
    input  logic [APB_ADDR_W-1:0] paddr_i,
    input  logic [31:0]          pwdata_i,
    input  logic [3:0]           pstrb_i,
    output logic [31:0]          prdata_o,
    output logic                 pready_o,
    output logic                 pslverr_o,
    input  logic                 raster_task_valid_i,
    output logic                 raster_task_ready_o,
    input  logic [31:0]          raster_task_id_i,
    input  logic [23:0]          raster_block_id_i,
    input  logic [31:0]          raster_gid_i,
    input  logic [11:0]          raster_pixel_id_i,
    input  logic [5:0]           raster_pixel_in_block_i,
    input  logic [12:0]          raster_color_r_q12_i,
    input  logic [12:0]          raster_color_g_q12_i,
    input  logic [12:0]          raster_color_b_q12_i,
    input  logic signed [15:0]   raster_dx_q10_i,
    input  logic signed [15:0]   raster_dy_q10_i,
    input  logic [14:0]          raster_l00_q12_i,
    input  logic signed [15:0]   raster_l10_q12_i,
    input  logic [14:0]          raster_l11_q12_i,
    input  logic signed [5:0]    raster_coordinate_shift_i,
    input  logic signed [5:0]    raster_factor_shift_i,
    input  logic [12:0]          raster_opacity_q12_i,
    output logic                 raster_commit_valid_o,
    input  logic                 raster_commit_ready_i,
    output logic [31:0]          raster_commit_task_id_o,
    output logic [23:0]          raster_commit_block_id_o,
    output logic [31:0]          raster_commit_gid_o,
    output logic [11:0]          raster_commit_pixel_id_o,
    output logic [12:0]          raster_commit_r_q12_o,
    output logic [12:0]          raster_commit_g_q12_o,
    output logic [12:0]          raster_commit_b_q12_o,
    output logic [15:0]          raster_commit_t_q16_o,
    output logic                 raster_commit_newly_terminated_o
);
    logic start_pulse, soft_reset_pulse, mode_shadow_we, mode_commit;
    logic continue_pulse_unused,more_batches_pulse_unused;
    logic [1:0] shadow_mode, active_mode;
    logic [15:0] epoch_id;
    logic commit_pending, commit_overrun, commit_pulse;
    logic [63:0] gaussian_base, camera_base, output_base;
    logic [15:0] image_width, image_height;
    logic block_terminated_pulse, skipped_pulse;
    logic [15:0] commit_epoch_unused;
    logic [12:0] commit_alpha_unused;
    logic commit_pass_unused;
    logic [2:0] occupancy_unused;
    logic status_clear_unused;logic[1:0]irq_enable_unused;
    logic[31:0]gaussian_count_unused;
    logic[63:0]attribute_base_unused;
    logic auto_mode_enable_unused;

    apb_regfile u_regfile (
        .pclk_i(clk_i), .preset_ni(rst_ni), .psel_i(psel_i),
        .penable_i(penable_i), .pwrite_i(pwrite_i), .paddr_i(paddr_i),
        .pwdata_i(pwdata_i), .pstrb_i(pstrb_i), .prdata_o(prdata_o),
        .pready_o(pready_o), .pslverr_o(pslverr_o),
        .start_pulse_o(start_pulse),.continue_pulse_o(continue_pulse_unused),
        .more_batches_pulse_o(more_batches_pulse_unused), .soft_reset_pulse_o(soft_reset_pulse),
        .status_clear_pulse_o(status_clear_unused),
        .shadow_mode_o(shadow_mode), .mode_shadow_we_o(mode_shadow_we),
        .mode_commit_pulse_o(mode_commit), .gaussian_base_o(gaussian_base),
        .camera_base_o(camera_base), .output_base_o(output_base),
        .image_width_o(image_width), .image_height_o(image_height),
        .gaussian_count_o(gaussian_count_unused),
        .attribute_base_o(attribute_base_unused),
        .irq_enable_o(irq_enable_unused),.auto_mode_enable_o(auto_mode_enable_unused),
        .busy_i(1'b0), .done_i(1'b0), .active_mode_i(active_mode),
        .error_i(1'b0),.error_status_i(32'b0),.irq_pending_i(2'b0),.irq_i(1'b0),
        .epoch_id_i(epoch_id), .commit_pending_i(commit_pending),
        .commit_overrun_i(commit_overrun),.frame_open_i(1'b0),
        .advisor_recommendation_valid_i(1'b0),.advisor_recommendation_mode_i(2'b0),
        .advisor_window_winner_i(2'b0),.advisor_request_outstanding_i(1'b0),
        .advisor_window_index_i(32'b0),.advisor_window_group_i(32'b0),
         .advisor_window_sort_i(32'b0),.advisor_window_projection_i(32'b0),
         .advisor_window_raster_i(32'b0),.advisor_window_block_i(32'b0),
         .advisor_window_skip_i(32'b0),
         .shared_pe_group_grant_count_i(32'b0),.shared_pe_projection_grant_count_i(32'b0),
         .shared_pe_raster_grant_count_i(32'b0),.shared_pe_group_stall_count_i(32'b0),
         .shared_pe_projection_stall_count_i(32'b0),.shared_pe_raster_stall_count_i(32'b0),
         .shared_pe_utilization_count_i(32'b0),
         .sort_work_snapshot_i(384'b0),.sort_capabilities_i(32'b0),.sort_snapshot_sequence_i(32'b0),
         .sort_snapshot_pulse_o(),.sort_clear_pulse_o()
     );

    cfg_epoch_ctrl u_epoch (
        .clk_i(clk_i), .rst_ni(rst_ni), .shadow_we_i(mode_shadow_we),
        .shadow_mode_i(shadow_mode), .commit_i(mode_commit),
        .epoch_boundary_i(1'b1), .affected_empty_i(!raster_task_valid_i),
        .shadow_mode_o(), .active_mode_o(active_mode), .epoch_id_o(epoch_id),
        .commit_pending_o(commit_pending), .commit_pulse_o(commit_pulse),
        .commit_overrun_o(commit_overrun)
    );

    raster_pair_shell u_raster (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .cfg_active_lanes_i(3'd1),
        .task_valid_i(raster_task_valid_i), .task_ready_o(raster_task_ready_o),
        .task_id_i(raster_task_id_i), .block_id_i(raster_block_id_i),
        .gid_i(raster_gid_i), .epoch_id_i(epoch_id),
        .pixel_id_i(raster_pixel_id_i), .pixel_in_block_i(raster_pixel_in_block_i),
        .color_r_q12_i(raster_color_r_q12_i), .color_g_q12_i(raster_color_g_q12_i),
        .color_b_q12_i(raster_color_b_q12_i), .alpha_dx_q10_i(raster_dx_q10_i),
        .alpha_dy_q10_i(raster_dy_q10_i), .alpha_l00_q12_i(raster_l00_q12_i),
        .alpha_l10_q12_i(raster_l10_q12_i), .alpha_l11_q12_i(raster_l11_q12_i),
        .alpha_coordinate_shift_i(raster_coordinate_shift_i),
        .alpha_factor_shift_i(raster_factor_shift_i),
        .alpha_opacity_q12_i(raster_opacity_q12_i),
        .block_terminated_pulse_o(block_terminated_pulse),
        .skipped_terminated_pulse_o(skipped_pulse),
        .commit_valid_o(raster_commit_valid_o),
        .commit_ready_i(raster_commit_ready_i),
        .commit_task_id_o(raster_commit_task_id_o),
        .commit_block_id_o(raster_commit_block_id_o),
        .commit_gid_o(raster_commit_gid_o), .commit_epoch_id_o(commit_epoch_unused),
        .commit_alpha_q12_o(commit_alpha_unused),
        .commit_pass_alpha_o(commit_pass_unused),
        .commit_pixel_id_o(raster_commit_pixel_id_o),
        .commit_r_q12_o(raster_commit_r_q12_o),
        .commit_g_q12_o(raster_commit_g_q12_o),
        .commit_b_q12_o(raster_commit_b_q12_o),
        .commit_t_q16_o(raster_commit_t_q16_o),
        .commit_newly_terminated_o(raster_commit_newly_terminated_o),
        .result_occupancy_o(occupancy_unused),.active_mask_o(),.retire_wait_o(),.protocol_error_o(),.idle_o(),
        .state_miss_req_valid_o(),.state_miss_req_ready_i(1'b0),.state_miss_req_tag_o(),.state_miss_req_pixel_id_o(),
        .state_miss_rsp_valid_i(1'b0),.state_miss_rsp_ready_o(),.state_miss_rsp_tag_i(2'b0),.state_miss_rsp_error_i(1'b0),
        .state_miss_rsp_data_i(128'b0),.state_cache_error_o(),.state_cache_idle_o()
    );
endmodule
