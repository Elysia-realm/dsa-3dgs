`timescale 1ns/1ps
module tb_gaussian_frame_error_control;
`include "verification/rtl/t06_frame_signals.svh"
  logic[383:0]sort_work_totals_o;
  logic source_end_valid_i=0,source_end_ready_o;
  logic attr_req_valid_o,attr_req_ready_i=0;logic[7:0]attr_req_gid_o;
  logic attr_rsp_valid_i=0,attr_rsp_ready_o,attr_rsp_error_i=0;logic[1117:0]attr_rsp_data_i=0;
  localparam GID_W=8,COEFF_W=18,FLAT_W=3*16*COEFF_W;logic clk_i=0,rst_ni=0,frame_start_i=0,frame_continue_i=0;logic[1:0]frame_mode_i=3;logic frame_ready_o,frame_busy_o,frame_done_pulse_o,frame_error_o;logic[9:0]frame_error_status_o;
  logic source_valid_i=0,source_ready_o;logic[GID_W-1:0]source_gid_i=7;logic signed[26:0]source_world_x_q16_i=0,source_world_y_q16_i=0,source_world_z_q16_i=131072;logic source_last_i=1;
  logic runtime_mode_valid_i=0;logic[1:0]runtime_mode_i=0,active_mode_o;logic[15:0]epoch_id_o;logic mode_pending_o,mode_commit_pulse_o;
  logic attr_clear_valid_i=0,attr_write_en_i=0;logic[GID_W-1:0]attr_write_gid_i=0;logic signed[26:0]attr_write_world_x_q16_i=0,attr_write_world_y_q16_i=0,attr_write_world_z_q16_i=0;
  logic signed[21:0]attr_write_qw_q20_i=0,attr_write_qx_q20_i=0,attr_write_qy_q20_i=0,attr_write_qz_q20_i=0;logic[23:0]attr_write_scale_x_q20_i=0,attr_write_scale_y_q20_i=0,attr_write_scale_z_q20_i=0;logic[12:0]attr_write_opacity_q12_i=0;logic[FLAT_W-1:0]attr_write_coeff_q12_flat_i=0;
  logic signed[21:0]cfg_r00_q20_i=1048576,cfg_r01_q20_i=0,cfg_r02_q20_i=0,cfg_r10_q20_i=0,cfg_r11_q20_i=1048576,cfg_r12_q20_i=0,cfg_r20_q20_i=0,cfg_r21_q20_i=0,cfg_r22_q20_i=1048576;
  logic signed[26:0]cfg_tx_q16_i=0,cfg_ty_q16_i=0,cfg_tz_q16_i=0,cfg_camera_x_q16_i=0,cfg_camera_y_q16_i=0,cfg_camera_z_q16_i=0;logic signed[32:0]cfg_fx_q16_i=131072,cfg_fy_q16_i=131072,cfg_cx_q16_i=1048576,cfg_cy_q16_i=1048576;
  logic signed[26:0]cfg_near_q16_i=13107,cfg_far_q16_i=65536000;logic[31:0]cfg_regularizer_q8_i=77;logic signed[26:0]cfg_depth_pivot0_q16_i=196608,cfg_depth_pivot1_q16_i=262144,cfg_depth_pivot2_q16_i=327680;logic[15:0]cfg_image_width_i=64,cfg_image_height_i=48;
  logic commit_valid_o,commit_ready_i=1;logic[31:0]commit_task_id_o,commit_block_id_o;logic[GID_W-1:0]commit_gid_o;logic[15:0]commit_epoch_id_o;logic[12:0]commit_alpha_q12_o;logic commit_pass_alpha_o;logic[31:0]commit_pixel_id_o;logic[12:0]commit_r_q12_o,commit_g_q12_o,commit_b_q12_o;logic[15:0]commit_t_q16_o;logic commit_newly_terminated_o;logic[0:0]projection_active_mask_o,sh_active_mask_o,raster_active_mask_o;logic attribute_read_pulse_o;
  logic event_group_pressure_o,event_sort_busy_o,event_projection_busy_o,event_raster_busy_o,event_block_candidate_o,event_shape_block_reject_o,event_terminated_skip_o;
  logic shared_pe_group_grant_o,shared_pe_projection_grant_o,shared_pe_raster_grant_o;
  logic shared_pe_group_stall_o,shared_pe_projection_stall_o,shared_pe_raster_stall_o;
  logic shared_pe_utilization_o,shared_pe_clock_enable_o,shared_pe_busy_o;
  logic state_miss_req_valid_o,state_miss_req_ready_i=0,state_miss_req_tag_o;
  logic state_miss_rsp_valid_i=0,state_miss_rsp_ready_o,state_miss_rsp_tag_i=0;
  logic[31:0]state_miss_req_pixel_id_o;logic state_miss_rsp_error_i=0;
  logic[127:0]state_miss_rsp_data_i=0;logic state_cache_error_o,state_cache_idle_o;
  always#5 clk_i=~clk_i;gaussian_frame_render_pipeline #(.ATTR_DEPTH(8),.LANES(1),.GROUP_CAPACITY(2),.SORT_CAPACITY(2),.GID_W(GID_W),.SEQ_W(8))dut(.*);
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  initial begin integer timeout;repeat(2)tick();rst_ni=1;tick();frame_start_i=1;tick();frame_start_i=0;
    // Busy re-start is sticky error bit 8. GID 7 is in range but deliberately
    // unloaded, which must be consumed as an error without undefined rendering.
    timeout=0;while(!source_ready_o&&timeout<30)begin tick();timeout=timeout+1;end
    frame_start_i=1;tick();frame_start_i=0;source_valid_i=1;tick();source_valid_i=0;
    timeout=0;while(!frame_done_pulse_o&&timeout<200)begin tick();timeout=timeout+1;end
    if(timeout>=200||!frame_error_o)$fatal(1,"error frame did not terminate");
    if(!frame_error_status_o[8]||!frame_error_status_o[4])$fatal(1,"missing busy-start/unloaded errors %b",frame_error_status_o);
    if(commit_valid_o)$fatal(1,"unloaded Gaussian reached raster commit");
    // No backing-store writeback exists yet, so an image larger than the
    // configured on-chip state capacity must fail immediately, never alias.
    cfg_image_width_i=65;cfg_image_height_i=64;tick();frame_start_i=1;tick();frame_start_i=0;
    if(!frame_done_pulse_o||!frame_error_status_o[9]||frame_busy_o)
      $fatal(1,"oversized image capacity error missing %b",frame_error_status_o);
    $display("PASS: tb_gaussian_frame_error_control");$finish;
  end
endmodule
