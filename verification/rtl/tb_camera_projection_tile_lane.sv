`timescale 1ns/1ps
module tb_camera_projection_tile_lane;
 localparam META_W=16,COORD_W=27,COV3_W=41,COV2_W=35,SCREEN_W=27,PIXEL_W=16,RAW_DESC_W=META_W+13+COORD_W+3*COV2_W+2*SCREEN_W+4*PIXEL_W+1,DESC_W=RAW_DESC_W+15+16+15+6+6+1;
 logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o;logic[META_W-1:0]s_meta_i='0;
 logic signed[26:0]s_camera_x_q16_i=0,s_camera_y_q16_i=0,s_camera_z_q16_i=27'sd131072;
 logic signed[40:0]s_cov_xx_q16_i=41'sd65536,s_cov_xy_q16_i=0,s_cov_xz_q16_i=0,s_cov_yy_q16_i=41'sd65536,s_cov_yz_q16_i=0,s_cov_zz_q16_i=41'sd65536;
 logic[12:0]s_opacity_q12_i=13'd4096;
 logic s_transform_overflow_i=0;logic signed[32:0]cfg_fx_q16_i=33'sd262144,cfg_fy_q16_i=33'sd262144,cfg_cx_q16_i=33'sd1048576,cfg_cy_q16_i=33'sd1048576;
 logic signed[26:0]cfg_near_q16_i=27'sd13107,cfg_far_q16_i=27'sd65536000;logic[34:0]cfg_regularizer_q8_i=77;logic[15:0]cfg_image_width_i=64,cfg_image_height_i=48;
 logic m_task_valid_o,m_task_ready_i=1;logic[DESC_W-1:0]m_task_desc_o;logic[11:0]m_task_tile_x_o,m_task_tile_y_o;logic m_task_first_o,m_task_last_o,m_task_culled_o,culled_pulse_o;
 always#5 clk_i=~clk_i;
 camera_projection_tile_lane #(.META_W(META_W))dut(.*);
 task automatic tick;begin@(posedge clk_i);#1;end endtask
 initial begin integer count,timeout;repeat(2)tick();rst_ni=1;tick();
   // Camera mean (0,0,2), f=4, principal point=(16,16), identity covariance.
   // Projected covariance=4.3, conservative radius=7 -> bbox[9,24), tiles1..2.
   s_meta_i=16'h5a5a;s_valid_i=1;tick();s_valid_i=0;count=0;timeout=0;m_task_ready_i=0;
   while(!m_task_valid_o&&timeout<350)begin tick();timeout=timeout+1;end
   if(!m_task_valid_o)$fatal(1,"front-end lane initial result timeout");
   while(count<4&&timeout<350)begin
     m_task_ready_i=(timeout[1:0]!=2'b01);
     if(m_task_valid_o&&m_task_ready_i)begin
       if(m_task_tile_x_o!==(1+count%2)||m_task_tile_y_o!==(1+count/2)
          ||m_task_first_o!==(count==0)||m_task_last_o!==(count==3))
         $fatal(1,"front-end lane tile mismatch n=%0d xy=%0d,%0d",count,m_task_tile_x_o,m_task_tile_y_o);
       count=count+1;
     end
     tick();timeout=timeout+1;
   end
   if(count!=4)$fatal(1,"front-end lane timeout count=%0d",count);
   // Behind-near input is consumed and reported as a cull, never a tile.
   while(!s_ready_o)tick();s_meta_i=16'hdead;s_camera_z_q16_i=27'sd6553;s_valid_i=1;tick();s_valid_i=0;
   timeout=0;while(!culled_pulse_o&&timeout<350)begin
     if(m_task_valid_o&&(!m_task_culled_o||!m_task_first_o||!m_task_last_o))
       $fatal(1,"culled input did not issue a tagged single-beat event");
     tick();timeout=timeout+1;
   end
   if(!culled_pulse_o)$fatal(1,"culled pulse timeout");
   $display("PASS: tb_camera_projection_tile_lane");$finish;
 end
endmodule
