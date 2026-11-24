`timescale 1ns/1ps
module tb_raw_gaussian_projection_array;
 logic[248:0]s_attr_aux_i='0;
 localparam LANES=2,META_W=16,COORD_W=27,COV2_W=35,SCREEN_W=27,PIXEL_W=16;
 localparam RAW_DESC_W=META_W+13+COORD_W+3*COV2_W+2*SCREEN_W+4*PIXEL_W+1;
 localparam DESC_W=RAW_DESC_W+15+16+15+6+6+1;
 logic clk_i=0,rst_ni=0,shadow_mode_we_i=0,mode_commit_i=0,epoch_boundary_i=0;
 logic[1:0]shadow_mode_i=0,active_mode_o;logic[1:0]active_lanes_o;logic[15:0]epoch_id_o;
 logic mode_pending_o,mode_commit_pulse_o,mode_overrun_o;
 logic s_valid_i=0,s_ready_o;logic[15:0]s_meta_i;logic signed[26:0]s_world_x_q16_i=0,s_world_y_q16_i=0,s_world_z_q16_i=27'sd131072;
 logic signed[21:0]s_qw_q20_i=22'sd1048576,s_qx_q20_i=0,s_qy_q20_i=0,s_qz_q20_i=0;
 logic[23:0]s_scale_x_q20_i=24'd1048576,s_scale_y_q20_i=24'd1048576,s_scale_z_q20_i=24'd1048576;logic[12:0]s_opacity_q12_i=13'd4096;
 logic signed[21:0]cfg_r00_q20_i=22'sd1048576,cfg_r01_q20_i=0,cfg_r02_q20_i=0,cfg_r10_q20_i=0,cfg_r11_q20_i=22'sd1048576,cfg_r12_q20_i=0,cfg_r20_q20_i=0,cfg_r21_q20_i=0,cfg_r22_q20_i=22'sd1048576;
 logic signed[26:0]cfg_tx_q16_i=0,cfg_ty_q16_i=0,cfg_tz_q16_i=0;
 logic signed[32:0]cfg_fx_q16_i=33'sd262144,cfg_fy_q16_i=33'sd262144,cfg_cx_q16_i=33'sd1048576,cfg_cy_q16_i=33'sd1048576;
 logic signed[26:0]cfg_near_q16_i=27'sd13107,cfg_far_q16_i=27'sd65536000;logic[34:0]cfg_regularizer_q8_i=77;logic[15:0]cfg_image_width_i=64,cfg_image_height_i=48;
 logic m_task_valid_o,m_task_ready_i=1;logic[DESC_W-1:0]m_task_desc_o;logic[11:0]m_task_tile_x_o,m_task_tile_y_o;
 logic m_task_first_o,m_task_last_o,m_task_culled_o,culled_pulse_o;logic[1:0]active_mask_o;
 logic all_idle_o,retire_wait_o,retire_protocol_error_o;
 always#5 clk_i=~clk_i;
 raw_gaussian_projection_array #(.LANES(LANES),.META_W(META_W))dut(
   .pe_req_valid_o(),.pe_req_ready_i(1'b0),.pe_lhs_o(),.pe_rhs_o(),.pe_acc_o(),
   .pe_rsp_valid_i(1'b0),.pe_rsp_ready_o(),.pe_result_i(65'sd0),.*);
 task automatic tick;begin@(posedge clk_i);#1;end endtask
 task automatic send(input logic[15:0]meta);begin
   while(!s_ready_o)tick();s_meta_i=meta;s_valid_i=1;tick();s_valid_i=0;
 end endtask
 initial begin integer count,timeout;logic[15:0]meta;
   repeat(2)tick();rst_ni=1;tick();if(active_mask_o!==2'b01)$fatal(1,"reset G-mode mask mismatch");
   shadow_mode_i=1;shadow_mode_we_i=1;mode_commit_i=1;epoch_boundary_i=1;tick();
   shadow_mode_we_i=0;mode_commit_i=0;epoch_boundary_i=0;
   if(active_mask_o!==2'b11||active_lanes_o!==2||epoch_id_o!==1)$fatal(1,"2-lane commit failed");
   send(16'ha001);send(16'hb002);
   // Request one lane while both transactions are in flight. The commit must
   // remain pending even though the epoch marker is asserted.
   shadow_mode_i=3;shadow_mode_we_i=1;mode_commit_i=1;epoch_boundary_i=1;tick();
   shadow_mode_we_i=0;mode_commit_i=0;
   if(!mode_pending_o||active_lanes_o!==2)$fatal(1,"busy array committed early");
   count=0;timeout=0;
   while(count<8&&timeout<700)begin
     if(m_task_valid_o&&m_task_ready_i)begin
       meta=m_task_desc_o[DESC_W-1 -: META_W];
       if((count<4&&meta!==16'ha001)||(count>=4&&meta!==16'hb002))
         $fatal(1,"array interleaved Gaussian tasks n=%0d meta=%h",count,meta);
       if(m_task_first_o!==(count==0||count==4)||m_task_last_o!==(count==3||count==7))
         $fatal(1,"array first/last mismatch n=%0d flags=%b,%b",count,m_task_first_o,m_task_last_o);
       count=count+1;
     end
     tick();timeout=timeout+1;
   end
   if(count!=8)$fatal(1,"array output timeout count=%0d",count);
   timeout=0;while(!mode_commit_pulse_o&&timeout<10)begin tick();timeout=timeout+1;end
   if(active_lanes_o!==1||epoch_id_o!==2||mode_pending_o||active_mask_o!==2'b01)
     $fatal(1,"drained mode commit failed lanes=%0d epoch=%0d",active_lanes_o,epoch_id_o);
   epoch_boundary_i=0;tick();$display("PASS: tb_raw_gaussian_projection_array");$finish;
 end
endmodule
