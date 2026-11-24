`timescale 1ns/1ps
module tb_gaussian_ordered_render_frontend;
 localparam LANES=4,GID_W=16,SEQ_W=8,COEFF_W=18,FLAT_W=3*16*COEFF_W;
 logic clk_i=0,rst_ni=0,shadow_mode_we_i=0,mode_commit_i=0,epoch_boundary_i=0;logic[1:0]shadow_mode_i=0,active_mode_o;
 logic[15:0]epoch_id_o;logic mode_pending_o,mode_commit_pulse_o,mode_overrun_o,s_valid_i=0,s_ready_o;
 logic[GID_W-1:0]s_gid_i=16'h44;logic[SEQ_W-1:0]s_seq_i=8'h05;logic signed[26:0]s_world_x_q16_i=0,s_world_y_q16_i=0,s_world_z_q16_i=131072;
 logic signed[21:0]s_qw_q20_i=1048576,s_qx_q20_i=0,s_qy_q20_i=0,s_qz_q20_i=0;logic[23:0]s_scale_x_q20_i=1048576,s_scale_y_q20_i=1048576,s_scale_z_q20_i=1048576;
 logic[12:0]s_opacity_q12_i=4096;logic[FLAT_W-1:0]s_coeff_q12_flat_i='0;
 logic signed[21:0]cfg_r00_q20_i=1048576,cfg_r01_q20_i=0,cfg_r02_q20_i=0,cfg_r10_q20_i=0,cfg_r11_q20_i=1048576,cfg_r12_q20_i=0,cfg_r20_q20_i=0,cfg_r21_q20_i=0,cfg_r22_q20_i=1048576;
 logic signed[26:0]cfg_tx_q16_i=0,cfg_ty_q16_i=0,cfg_tz_q16_i=0,cfg_camera_x_q16_i=0,cfg_camera_y_q16_i=0,cfg_camera_z_q16_i=0;
 logic signed[32:0]cfg_fx_q16_i=262144,cfg_fy_q16_i=262144,cfg_cx_q16_i=1048576,cfg_cy_q16_i=1048576;
 logic signed[26:0]cfg_near_q16_i=13107,cfg_far_q16_i=65536000;logic[31:0]cfg_regularizer_q8_i=77;logic[15:0]cfg_image_width_i=64,cfg_image_height_i=48;
 logic commit_valid_o,commit_ready_i=1;logic[31:0]commit_task_id_o,commit_block_id_o;logic[GID_W-1:0]commit_gid_o;logic[15:0]commit_epoch_id_o;
 logic[12:0]commit_alpha_q12_o;logic commit_pass_alpha_o;logic[31:0]commit_pixel_id_o;logic[12:0]commit_r_q12_o,commit_g_q12_o,commit_b_q12_o;
 logic[15:0]commit_t_q16_o;logic commit_newly_terminated_o,block_terminated_pulse_o,skipped_terminated_pulse_o,empty_or_culled_pulse_o,shape_rejected_pulse_o,all_idle_o,retire_wait_o,protocol_error_o;
 logic stage_projection_busy_o,stage_raster_busy_o,block_candidate_pulse_o;
 logic[LANES-1:0]projection_active_mask_o,sh_active_mask_o,raster_active_mask_o;
 logic state_miss_req_valid_o,state_miss_req_ready_i=0,state_miss_req_tag_o;
 logic state_miss_rsp_valid_i=0,state_miss_rsp_ready_o,state_miss_rsp_tag_i=0;
 logic[31:0]state_miss_req_pixel_id_o;logic state_miss_rsp_error_i=0;
 logic[127:0]state_miss_rsp_data_i=0;logic state_cache_error_o,state_cache_idle_o;
 always#5 clk_i=~clk_i;gaussian_ordered_render_frontend #(.LANES(LANES),.GID_W(GID_W),.SEQ_W(SEQ_W))dut(
   .pe_req_valid_o(),.pe_req_ready_i(1'b0),.pe_lhs_o(),.pe_rhs_o(),.pe_acc_o(),
   .pe_rsp_valid_i(1'b0),.pe_rsp_ready_o(),.pe_result_i(65'sd0),
   .r_pe_req_valid_o(),.r_pe_req_ready_i(1'b0),.r_pe_lhs_o(),.r_pe_rhs_o(),
   .r_pe_rsp_valid_i(1'b0),.r_pe_rsp_ready_o(),.r_pe_result_i(65'sd0),.*);
 task automatic tick;begin@(posedge clk_i);#1;end endtask
 initial begin integer commits,timeout,nonzero;repeat(2)tick();rst_ni=1;tick();s_coeff_q12_flat_i='0;s_coeff_q12_flat_i[0+:COEFF_W]=18'sd4096;
   if(projection_active_mask_o!==4'b0011||sh_active_mask_o!==4'b0011||raster_active_mask_o!==4'b0011)
     $fatal(1,"G-mode active masks mismatch p=%b sh=%b r=%b",projection_active_mask_o,sh_active_mask_o,raster_active_mask_o);
   while(!s_ready_o)tick();s_valid_i=1;tick();s_valid_i=0;
   // Request a mode change while this Gaussian is in flight. It must remain
   // pending until projection, SH, all four blocks and every raster pixel drain.
   shadow_mode_i=2;shadow_mode_we_i=1;mode_commit_i=1;epoch_boundary_i=1;tick();
   shadow_mode_we_i=0;mode_commit_i=0;
   if(!mode_pending_o||epoch_id_o!==0)$fatal(1,"busy render mode committed early");
   commits=0;nonzero=0;timeout=0;
   while(commits<225&&timeout<4000)begin commit_ready_i=(timeout%7!=3);
     if(commit_valid_o&&commit_ready_i)begin
       if(commit_gid_o!==16'h44||commit_epoch_id_o!==0||commit_task_id_o!==8'h05)
         $fatal(1,"render tag mismatch c=%0d gid=%h task=%h epoch=%h",commits,commit_gid_o,commit_task_id_o,commit_epoch_id_o);
       if(commit_r_q12_o!=0)begin nonzero=nonzero+1;
         if(commit_r_q12_o<=commit_g_q12_o||commit_g_q12_o!==commit_b_q12_o)$fatal(1,"SH color ratio/order lost rgb=%0d,%0d,%0d",commit_r_q12_o,commit_g_q12_o,commit_b_q12_o);end
       commits=commits+1;end tick();timeout=timeout+1;end
   // bbox is [9,24)x[9,24), exactly 225 covered pixels over four internal blocks.
   if(commits!=225||nonzero==0||protocol_error_o)$fatal(1,"render chain timeout/count commits=%0d nonzero=%0d error=%b",commits,nonzero,protocol_error_o);
   timeout=0;while(!all_idle_o&&timeout<30)begin tick();timeout=timeout+1;end
   if(!all_idle_o)$fatal(1,"render chain not idle");
   timeout=0;while(!mode_commit_pulse_o&&timeout<20)begin tick();timeout=timeout+1;end
   if(epoch_id_o!==1||mode_pending_o||active_mode_o!==2)$fatal(1,"drained render mode did not commit epoch=%0d pending=%b mode=%0d",epoch_id_o,mode_pending_o,active_mode_o);
   if(projection_active_mask_o!==4'b0011||sh_active_mask_o!==4'b0011||raster_active_mask_o!==4'b1111)
     $fatal(1,"R-mode active masks mismatch p=%b sh=%b r=%b",projection_active_mask_o,sh_active_mask_o,raster_active_mask_o);
   epoch_boundary_i=0;$display("PASS: tb_gaussian_ordered_render_frontend");$finish;
 end
endmodule
