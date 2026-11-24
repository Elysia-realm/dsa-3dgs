`timescale 1ns/1ps
module tb_raw_gaussian_projection_lane;
 localparam META_W=16,COORD_W=27,COV2_W=35,SCREEN_W=27,PIXEL_W=16;
 localparam RAW_DESC_W=META_W+13+COORD_W+3*COV2_W+2*SCREEN_W+4*PIXEL_W+1;
 localparam DESC_W=RAW_DESC_W+15+16+15+6+6+1;
 logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o;
 logic[15:0]s_meta_i=16'h1111;logic signed[26:0]s_world_x_q16_i=0,s_world_y_q16_i=0,s_world_z_q16_i=27'sd131072;
 logic signed[21:0]s_qw_q20_i=22'sd1048576,s_qx_q20_i=0,s_qy_q20_i=0,s_qz_q20_i=0;
 logic[23:0]s_scale_x_q20_i=24'd1048576,s_scale_y_q20_i=24'd1048576,s_scale_z_q20_i=24'd1048576;
 logic[12:0]s_opacity_q12_i=13'd4096;
 logic signed[21:0]cfg_r00_q20_i=22'sd1048576,cfg_r01_q20_i=0,cfg_r02_q20_i=0;
 logic signed[21:0]cfg_r10_q20_i=0,cfg_r11_q20_i=22'sd1048576,cfg_r12_q20_i=0;
 logic signed[21:0]cfg_r20_q20_i=0,cfg_r21_q20_i=0,cfg_r22_q20_i=22'sd1048576;
 logic signed[26:0]cfg_tx_q16_i=0,cfg_ty_q16_i=0,cfg_tz_q16_i=0;
 logic signed[32:0]cfg_fx_q16_i=33'sd262144,cfg_fy_q16_i=33'sd262144,cfg_cx_q16_i=33'sd1048576,cfg_cy_q16_i=33'sd1048576;
 logic signed[26:0]cfg_near_q16_i=27'sd13107,cfg_far_q16_i=27'sd65536000;
 logic[34:0]cfg_regularizer_q8_i=35'd77;logic[15:0]cfg_image_width_i=64,cfg_image_height_i=48;
 logic m_task_valid_o,m_task_ready_i=0;logic[DESC_W-1:0]m_task_desc_o;
 logic[11:0]m_task_tile_x_o,m_task_tile_y_o;logic m_task_first_o,m_task_last_o,m_task_culled_o,culled_pulse_o,idle_o;
 always#5 clk_i=~clk_i;
 raw_gaussian_projection_lane #(.META_W(META_W))dut(.s_mean_overflow_i(1'b0),.*);
 task automatic tick;begin@(posedge clk_i);#1;end endtask
 task automatic send(input logic[15:0]meta,input logic signed[26:0]z);begin
   while(!s_ready_o)tick();s_meta_i=meta;s_world_z_q16_i=z;s_valid_i=1;tick();s_valid_i=0;
 end endtask
 initial begin integer count,timeout;logic[15:0]desc_meta;
   repeat(2)tick();rst_ni=1;tick();if(!idle_o)$fatal(1,"lane not idle after reset");
   send(16'h5a5a,27'sd131072);if(idle_o)$fatal(1,"idle asserted with accepted Gaussian");
   timeout=0;while(!m_task_valid_o&&timeout<500)begin tick();timeout=timeout+1;end
   if(!m_task_valid_o)$fatal(1,"raw lane initial task timeout");
   count=0;while(count<4&&timeout<550)begin
     m_task_ready_i=(timeout[1:0]!=2'b01);
     if(m_task_valid_o&&m_task_ready_i)begin
       desc_meta=m_task_desc_o[DESC_W-1 -: META_W];
       if(desc_meta!==16'h5a5a||m_task_tile_x_o!==(1+count%2)||m_task_tile_y_o!==(1+count/2)
          ||m_task_first_o!==(count==0)||m_task_last_o!==(count==3))
         $fatal(1,"raw task mismatch n=%0d meta=%h xy=%0d,%0d",count,desc_meta,m_task_tile_x_o,m_task_tile_y_o);
       count=count+1;
     end
     tick();timeout=timeout+1;
   end
   if(count!=4)$fatal(1,"raw task enumeration timeout count=%0d",count);
   tick();if(!idle_o)$fatal(1,"raw lane did not drain");
   send(16'hdead,27'sd6553);timeout=0;
   while(!culled_pulse_o&&timeout<500)begin
     if(m_task_valid_o&&(!m_task_culled_o||!m_task_first_o||!m_task_last_o))
       $fatal(1,"near-cull did not preserve a tagged single-beat event");
     tick();timeout=timeout+1;
   end
   if(!culled_pulse_o)$fatal(1,"raw cull timeout");
   // culled_pulse_o reports the same accepted last beat one cycle later.  The
   // lane must stay drained after that notification and must not retire twice.
   tick();
   timeout=0;while(!idle_o&&timeout<10)begin tick();timeout=timeout+1;end
   if(!idle_o)$fatal(1,"raw lane not idle after cull");
   $display("PASS: tb_raw_gaussian_projection_lane");$finish;
 end
endmodule
