`timescale 1ns/1ps
module tb_ordered_block_raster_frontend;
  localparam LANES=4;logic clk_i=0,rst_ni=0,block_valid_i=0,block_ready_o;logic[2:0]cfg_active_lanes_i=4;logic[31:0]task_id_i=32'h1234,gid_i=32'h5678;
  logic[15:0]epoch_id_i=16'h9abc;logic[11:0]block_x_i=0,block_y_i=0;logic[15:0]bbox_x0_i=0,bbox_y0_i=0,bbox_x1_i=1,bbox_y1_i=1;
  logic signed[26:0]mean_x_q8_i=0,mean_y_q8_i=0;logic[12:0]color_r_q12_i=4096,color_g_q12_i=2048,color_b_q12_i=1024;
  logic[14:0]l00_q12_i=4096,l11_q12_i=4096;logic signed[15:0]l10_q12_i=0;logic signed[5:0]coordinate_shift_i=0,factor_shift_i=0;
  logic[12:0]opacity_q12_i=4096;logic gaussian_first_block_i=1,gaussian_last_block_i=1,culled_i=0;
  logic[15:0]cfg_image_width_i=16,cfg_image_height_i=16;logic empty_or_culled_pulse_o,shape_rejected_pulse_o,block_terminated_pulse_o,skipped_terminated_pulse_o;
  logic commit_valid_o,commit_ready_i=1;logic[31:0]commit_task_id_o,commit_block_id_o,commit_gid_o;logic[15:0]commit_epoch_id_o;
  logic[12:0]commit_alpha_q12_o;logic commit_pass_alpha_o;logic[31:0]commit_pixel_id_o;logic[12:0]commit_r_q12_o,commit_g_q12_o,commit_b_q12_o;
  logic[15:0]commit_t_q16_o;logic commit_newly_terminated_o;logic[1:0]result_occupancy_o;logic[LANES-1:0]active_mask_o;logic retire_wait_o,protocol_error_o,idle_o;
  logic state_miss_req_valid_o,state_miss_req_ready_i=0,state_miss_req_tag_o;
  logic state_miss_rsp_valid_i=0,state_miss_rsp_ready_o,state_miss_rsp_tag_i=0;
  logic[31:0]state_miss_req_pixel_id_o;logic state_miss_rsp_error_i=0;
  logic[127:0]state_miss_rsp_data_i=0;logic state_cache_error_o,state_cache_idle_o;
  always#5 clk_i=~clk_i;ordered_block_raster_frontend #(.ENABLE_SHAPE_BLOCK_REJECT(1'b1))dut(.*,
    .r_pe_req_valid_o(),.r_pe_req_ready_i(1'b0),.r_pe_lhs_o(),.r_pe_rhs_o(),
    .r_pe_rsp_valid_i(1'b0),.r_pe_rsp_ready_o(),.r_pe_result_i(65'b0));
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  initial begin integer timeout;repeat(2)tick();rst_ni=1;tick();while(!block_ready_o)tick();block_valid_i=1;tick();block_valid_i=0;
    timeout=0;while(!commit_valid_o&&timeout<40)begin tick();timeout=timeout+1;end
    if(!commit_valid_o||commit_task_id_o!==task_id_i||commit_gid_o!==gid_i||commit_epoch_id_o!==epoch_id_i
      ||commit_block_id_o!==0||commit_pixel_id_o!==0||!commit_pass_alpha_o||commit_alpha_q12_o!==13'd4055
      ||commit_r_q12_o<13'd4000||commit_g_q12_o<13'd2000||commit_b_q12_o<13'd1000)
      $fatal(1,"ordered raster frontend mismatch task=%h block=%h pixel=%h alpha=%0d rgb=%0d,%0d,%0d",
        commit_task_id_o,commit_block_id_o,commit_pixel_id_o,commit_alpha_q12_o,commit_r_q12_o,commit_g_q12_o,commit_b_q12_o);
    tick();culled_i=1;while(!block_ready_o)tick();block_valid_i=1;tick();block_valid_i=0;
    if(!empty_or_culled_pulse_o)$fatal(1,"culled ordered block did not retire");
    culled_i=0;bbox_x1_i=8;bbox_y1_i=8;mean_y_q8_i=40*256;
    while(!block_ready_o)tick();block_valid_i=1;tick();block_valid_i=0;
    if(!empty_or_culled_pulse_o||!shape_rejected_pulse_o)$fatal(1,"shape-rejected block did not retire");
    $display("PASS: tb_ordered_block_raster_frontend");$finish;
  end
endmodule
