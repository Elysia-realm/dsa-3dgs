`timescale 1ns/1ps
module tb_gaussian_projection_sh_array;
 localparam LANES=2,GID_W=16,SEQ_W=8,EPOCH_W=16,COORD_W=27,COV2_W=35,SCREEN_W=27,PIXEL_W=16;
 localparam META_W=EPOCH_W+GID_W+SEQ_W,RAW_DESC_W=META_W+13+COORD_W+3*COV2_W+2*SCREEN_W+4*PIXEL_W+1;
 localparam DESC_W=RAW_DESC_W+15+16+15+6+6+1,COEFF_W=18,FLAT_W=3*16*COEFF_W;
 logic clk_i=0,rst_ni=0,shadow_mode_we_i=0,mode_commit_i=0,epoch_boundary_i=0,downstream_empty_i=1;
 logic[1:0]shadow_mode_i=0,active_mode_o;logic[15:0]epoch_id_o;logic mode_pending_o,mode_commit_pulse_o,mode_overrun_o;
 logic s_valid_i=0,s_ready_o;logic[GID_W-1:0]s_gid_i=0;logic[SEQ_W-1:0]s_seq_i=0;
 logic signed[26:0]s_world_x_q16_i=0,s_world_y_q16_i=0,s_world_z_q16_i=27'sd131072;
 logic signed[21:0]s_qw_q20_i=22'sd1048576,s_qx_q20_i=0,s_qy_q20_i=0,s_qz_q20_i=0;
 logic[23:0]s_scale_x_q20_i=24'd1048576,s_scale_y_q20_i=24'd1048576,s_scale_z_q20_i=24'd1048576;logic[12:0]s_opacity_q12_i=4096;
 logic[FLAT_W-1:0]s_coeff_q12_flat_i='0;
 logic signed[21:0]cfg_r00_q20_i=1048576,cfg_r01_q20_i=0,cfg_r02_q20_i=0,cfg_r10_q20_i=0,cfg_r11_q20_i=1048576,cfg_r12_q20_i=0,cfg_r20_q20_i=0,cfg_r21_q20_i=0,cfg_r22_q20_i=1048576;
 logic signed[26:0]cfg_tx_q16_i=0,cfg_ty_q16_i=0,cfg_tz_q16_i=0,cfg_camera_x_q16_i=0,cfg_camera_y_q16_i=0,cfg_camera_z_q16_i=0;
 logic signed[32:0]cfg_fx_q16_i=262144,cfg_fy_q16_i=262144,cfg_cx_q16_i=1048576,cfg_cy_q16_i=1048576;
 logic signed[26:0]cfg_near_q16_i=13107,cfg_far_q16_i=65536000;logic[34:0]cfg_regularizer_q8_i=77;logic[15:0]cfg_image_width_i=64,cfg_image_height_i=48;
 logic m_valid_o,m_ready_i=1;logic[DESC_W-1:0]m_desc_o;logic[11:0]m_block_x_o,m_block_y_o;logic[12:0]m_r_q12_o,m_g_q12_o,m_b_q12_o;
 logic m_first_o,m_last_o,m_culled_o,m_sh_fallback_o,m_numeric_overflow_o;logic[LANES-1:0]projection_active_mask_o,sh_active_mask_o;
 logic all_idle_o,retire_wait_o,protocol_error_o,stage_projection_busy_o;
 always#5 clk_i=~clk_i;gaussian_projection_sh_array #(.LANES(LANES),.GID_W(GID_W),.SEQ_W(SEQ_W),.EPOCH_W(EPOCH_W))dut(
   .pe_req_valid_o(),.pe_req_ready_i(1'b0),.pe_lhs_o(),.pe_rhs_o(),.pe_acc_o(),
   .pe_rsp_valid_i(1'b0),.pe_rsp_ready_o(),.pe_result_i(65'sd0),.*);
 task automatic tick;begin@(posedge clk_i);#1;end endtask
 task automatic send(input[15:0]gid,input[7:0]seq,input integer basis);begin
   while(!s_ready_o)tick();s_gid_i=gid;s_seq_i=seq;s_coeff_q12_flat_i='0;s_coeff_q12_flat_i[basis*COEFF_W+:COEFF_W]=18'sd4096;
   s_valid_i=1;tick();s_valid_i=0;end endtask
 initial begin integer count,timeout;logic[15:0]gid;logic[7:0]seq;logic[META_W-1:0]meta;repeat(2)tick();rst_ni=1;tick();
   // Atomically switch to two identical projection lanes before issuing work.
   shadow_mode_i=1;shadow_mode_we_i=1;mode_commit_i=1;epoch_boundary_i=1;tick();shadow_mode_we_i=0;mode_commit_i=0;epoch_boundary_i=0;
   if(projection_active_mask_o!==2'b11||epoch_id_o!==1)$fatal(1,"array mode setup failed");
   // Both Gaussians see +Z. First uses DC (R=3203), second basis2 (R=4049).
   send(16'h1001,8'h01,0);send(16'h1002,8'h02,2);count=0;timeout=0;
   while(count<8&&timeout<900)begin m_ready_i=(timeout%5!=2);
     if(m_valid_o&&m_ready_i)begin meta=m_desc_o[DESC_W-1-:META_W];{gid,seq}=meta[GID_W+SEQ_W-1:0];
       if((count<4&&(gid!==16'h1001||seq!==8'h01||m_r_q12_o!==3203))||
          (count>=4&&(gid!==16'h1002||seq!==8'h02||m_r_q12_o!==4049)))
         $fatal(1,"projection/SH join order/color mismatch n=%0d gid=%h seq=%h r=%0d",count,gid,seq,m_r_q12_o);
       if(m_g_q12_o!==2048||m_b_q12_o!==2048||m_sh_fallback_o||protocol_error_o||
          m_first_o!==(count==0||count==4)||m_last_o!==(count==3||count==7))$fatal(1,"array flags mismatch n=%0d",count);
       count=count+1;end tick();timeout=timeout+1;end
   if(count!=8)$fatal(1,"projection/SH array timeout count=%0d",count);
   timeout=0;while(!all_idle_o&&timeout<20)begin tick();timeout=timeout+1;end
   if(!all_idle_o)$fatal(1,"array did not drain");
   // Unified G/P/R/E mapping: mode P used above enables all P and SH lanes;
   // E mode must atomically gate both arrays down to one lane after drain.
   shadow_mode_i=3;shadow_mode_we_i=1;mode_commit_i=1;epoch_boundary_i=1;tick();
   shadow_mode_we_i=0;mode_commit_i=0;epoch_boundary_i=0;
   if(projection_active_mask_o!==2'b01||sh_active_mask_o!==2'b01||epoch_id_o!==2)
     $fatal(1,"joint E-mode lane gating failed p=%b sh=%b epoch=%0d",projection_active_mask_o,sh_active_mask_o,epoch_id_o);
   send(16'h1003,8'h03,2);count=0;timeout=0;
   while(count<4&&timeout<900)begin
     if(m_valid_o&&m_ready_i)begin
       if(m_r_q12_o!==4049||m_g_q12_o!==2048||m_b_q12_o!==2048||m_desc_o[DESC_W-1-:META_W]!=={16'd2,16'h1003,8'h03})
         $fatal(1,"E-mode bit equivalence/tag failed");count=count+1;
     end tick();timeout=timeout+1;
   end
   if(count!=4)$fatal(1,"E-mode array timeout");
   $display("PASS: tb_gaussian_projection_sh_array");$finish;
 end
endmodule
