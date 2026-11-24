`timescale 1ns/1ps
module tb_gaussian_sorted_render_pipeline;
  localparam GID_W=8,SEQ_W=8,COEFF_W=18,FLAT_W=3*16*COEFF_W;
  logic clk_i=0,rst_ni=0,attr_clear_valid_i=0,attr_clear_errors_i=0,attr_write_en_i=0;
  logic[GID_W-1:0]attr_write_gid_i=8'h04;
  logic signed[26:0]attr_write_world_x_q16_i=0,attr_write_world_y_q16_i=0,attr_write_world_z_q16_i=131072;
  logic signed[21:0]attr_write_qw_q20_i=1048576,attr_write_qx_q20_i=0,attr_write_qy_q20_i=0,attr_write_qz_q20_i=0;
  logic[23:0]attr_write_scale_x_q20_i=1048576,attr_write_scale_y_q20_i=1048576,attr_write_scale_z_q20_i=1048576;
  logic[12:0]attr_write_opacity_q12_i=4096;logic[FLAT_W-1:0]attr_write_coeff_q12_flat_i='0;
  logic sorted_valid_i=0,sorted_ready_o;logic signed[26:0]sorted_depth_i=131072;logic[GID_W-1:0]sorted_gid_i=8'h04;
  logic[SEQ_W-1:0]sorted_seq_i=8'h05;logic[1:0]sorted_group_i=0;logic sorted_group_first_i=1,sorted_group_last_i=1;
  logic shadow_mode_we_i=0;logic[1:0]shadow_mode_i=0;logic mode_commit_i=0,epoch_boundary_i=0;logic[1:0]active_mode_o;
  logic[15:0]epoch_id_o;logic mode_pending_o,mode_commit_pulse_o,mode_overrun_o;
  logic signed[21:0]cfg_r00_q20_i=1048576,cfg_r01_q20_i=0,cfg_r02_q20_i=0,cfg_r10_q20_i=0,cfg_r11_q20_i=1048576,cfg_r12_q20_i=0;
  logic signed[21:0]cfg_r20_q20_i=0,cfg_r21_q20_i=0,cfg_r22_q20_i=1048576;
  logic signed[26:0]cfg_tx_q16_i=0,cfg_ty_q16_i=0,cfg_tz_q16_i=0,cfg_camera_x_q16_i=0,cfg_camera_y_q16_i=0,cfg_camera_z_q16_i=0;
  logic signed[32:0]cfg_fx_q16_i=262144,cfg_fy_q16_i=262144,cfg_cx_q16_i=1048576,cfg_cy_q16_i=1048576;
  logic signed[26:0]cfg_near_q16_i=13107,cfg_far_q16_i=65536000;logic[31:0]cfg_regularizer_q8_i=77;
  logic[15:0]cfg_image_width_i=64,cfg_image_height_i=48;
  logic commit_valid_o,commit_ready_i=1;logic[31:0]commit_task_id_o,commit_block_id_o;logic[GID_W-1:0]commit_gid_o;
  logic[15:0]commit_epoch_id_o;logic[12:0]commit_alpha_q12_o;logic commit_pass_alpha_o;logic[31:0]commit_pixel_id_o;
  logic[12:0]commit_r_q12_o,commit_g_q12_o,commit_b_q12_o;logic[15:0]commit_t_q16_o;logic commit_newly_terminated_o;
  logic block_terminated_pulse_o,skipped_terminated_pulse_o,empty_or_culled_pulse_o,shape_rejected_pulse_o,all_idle_o,retire_wait_o,protocol_error_o;
  logic stage_projection_busy_o,stage_raster_busy_o,block_candidate_pulse_o;
  logic[0:0]projection_active_mask_o,sh_active_mask_o,raster_active_mask_o;logic attribute_read_pulse_o,attribute_invalid_sticky_o,attribute_unloaded_sticky_o,attribute_write_invalid_sticky_o;
  localparam ATTR_W=3*27+4*22+3*24+13+FLAT_W;
  logic attr_req_valid_o,attr_req_ready_i=0;logic[GID_W-1:0]attr_req_gid_o;
  logic attr_rsp_valid_i=0,attr_rsp_ready_o,attr_rsp_error_i=0;logic[ATTR_W-1:0]attr_rsp_data_i='0;
  logic state_miss_req_valid_o,state_miss_req_ready_i=0,state_miss_req_tag_o;
  logic state_miss_rsp_valid_i=0,state_miss_rsp_ready_o,state_miss_rsp_tag_i=0;
  logic[31:0]state_miss_req_pixel_id_o;logic state_miss_rsp_error_i=0;
  logic[127:0]state_miss_rsp_data_i=0;logic state_cache_error_o,state_cache_idle_o;
  always#5 clk_i=~clk_i;
  gaussian_sorted_render_pipeline #(.ATTR_DEPTH(8),.LANES(1),.GID_W(GID_W),.SEQ_W(SEQ_W))dut(
   .pe_req_valid_o(),.pe_req_ready_i(1'b0),.pe_lhs_o(),.pe_rhs_o(),.pe_acc_o(),
   .pe_rsp_valid_i(1'b0),.pe_rsp_ready_o(),.pe_result_i(65'sd0),
   .r_pe_req_valid_o(),.r_pe_req_ready_i(1'b0),.r_pe_lhs_o(),.r_pe_rhs_o(),
   .r_pe_rsp_valid_i(1'b0),.r_pe_rsp_ready_o(),.r_pe_result_i(65'sd0),.*);
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  initial begin integer commits,reads,timeout,nonzero;
    repeat(2)tick();rst_ni=1;tick();
    attr_write_coeff_q12_flat_i='0;attr_write_coeff_q12_flat_i[0+:COEFF_W]=18'sd4096;
    attr_write_en_i=1;tick();attr_write_en_i=0;
    while(!sorted_ready_o)tick();sorted_valid_i=1;tick();sorted_valid_i=0;
    // The source handshake above is the single architectural attribute read.
    reads=1;
    // Freeze sorted issue and request a new resource epoch while the fetched
    // record or rendering work is still in flight.
    shadow_mode_i=1;shadow_mode_we_i=1;mode_commit_i=1;epoch_boundary_i=1;tick();
    shadow_mode_we_i=0;mode_commit_i=0;
    if(!mode_pending_o||epoch_id_o!==0)$fatal(1,"pipeline committed epoch before attribute/render drain");
    commits=0;nonzero=0;timeout=0;
    while(commits<225&&timeout<4500)begin
      commit_ready_i=(timeout%7!=3);
      if(attribute_read_pulse_o)reads=reads+1;
      if(commit_valid_o&&commit_ready_i)begin
        if(commit_gid_o!==8'h04||commit_task_id_o!==8'h05||commit_epoch_id_o!==0)$fatal(1,"sorted render tag mismatch");
        if(commit_r_q12_o!=0)nonzero=nonzero+1;
        commits=commits+1;
      end
      tick();timeout=timeout+1;
    end
    if(commits!=225||nonzero==0||reads!=1)$fatal(1,"integration count/read failure commits=%0d nonzero=%0d reads=%0d",commits,nonzero,reads);
    if(attribute_invalid_sticky_o||attribute_unloaded_sticky_o||attribute_write_invalid_sticky_o||protocol_error_o)
      $fatal(1,"unexpected pipeline error");
    timeout=0;while(epoch_id_o!=1&&timeout<30)begin tick();timeout=timeout+1;end
    if(epoch_id_o!==1||mode_pending_o||active_mode_o!==1)$fatal(1,"safe mode commit did not complete");
    epoch_boundary_i=0;timeout=0;while(!all_idle_o&&timeout<10)begin tick();timeout=timeout+1;end
    if(!all_idle_o)$fatal(1,"integrated pipeline did not become idle");
    $display("PASS: tb_gaussian_sorted_render_pipeline");$finish;
  end
endmodule
