`timescale 1ns/1ps
module tb_bbox_tile_task;
 logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o;logic[15:0]s_meta_i='0;
 logic signed[26:0]s_mean_x_q8_i=0,s_mean_y_q8_i=0;logic[34:0]s_cov00_q8_i=0,s_cov11_q8_i=0;
 logic signed[34:0]s_cov01_q8_i=0;logic s_visible_i=1,s_numeric_overflow_i=0;
 logic[12:0]s_opacity_q12_i=13'd4096;
 logic[15:0]cfg_image_width_i=64,cfg_image_height_i=48;logic b_valid,b_ready;
 logic[15:0]b_meta;logic signed[26:0]bmx,bmy;logic[15:0]x0,y0,x1,y1;logic[11:0]tx0,ty0,tx1,ty1;
 logic keep,fullscreen;logic t_valid,t_ready=1;logic[15:0]t_desc;logic[11:0]tx,ty;logic first,last,culled_event,culled;
 always#5 clk_i=~clk_i;
 bbox_tile_bounds_core #(.META_W(16)) u_bbox(.clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i),
 .s_ready_o(s_ready_o),.s_meta_i(s_meta_i),.s_mean_x_q8_i(s_mean_x_q8_i),.s_mean_y_q8_i(s_mean_y_q8_i),
 .s_cov00_q8_i(s_cov00_q8_i),.s_cov01_q8_i(s_cov01_q8_i),.s_cov11_q8_i(s_cov11_q8_i),
 .s_opacity_q12_i(s_opacity_q12_i),
 .s_visible_i(s_visible_i),.s_numeric_overflow_i(s_numeric_overflow_i),.cfg_image_width_i(cfg_image_width_i),
 .cfg_image_height_i(cfg_image_height_i),.m_valid_o(b_valid),.m_ready_i(b_ready),.m_meta_o(b_meta),
 .m_mean_x_q8_o(bmx),.m_mean_y_q8_o(bmy),.m_x0_o(x0),.m_y0_o(y0),.m_x1_o(x1),.m_y1_o(y1),
 .m_tile_x0_o(tx0),.m_tile_y0_o(ty0),.m_tile_x1_o(tx1),.m_tile_y1_o(ty1),.m_keep_o(keep),
 .m_numeric_invalid_o(fullscreen));
 gaussian_tile_task_gen #(.DESC_W(16)) u_tasks(.clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(b_valid),
 .s_ready_o(b_ready),.s_desc_i(b_meta),.s_tile_x0_i(tx0),.s_tile_y0_i(ty0),.s_tile_x1_i(tx1),
 .s_tile_y1_i(ty1),.s_keep_i(keep),.m_valid_o(t_valid),.m_ready_i(t_ready),.m_desc_o(t_desc),
 .m_tile_x_o(tx),.m_tile_y_o(ty),.m_first_o(first),.m_last_o(last),.m_culled_o(culled_event),
 .culled_pulse_o(culled));
 task automatic tick;begin@(posedge clk_i);#1;end endtask
 initial begin integer count,timeout;repeat(2)tick();rst_ni=1;tick();
   // mean=(16,16), covariance diag=4 -> radius=6, bbox [10,23), tiles x/y 1..2.
   s_meta_i=16'habcd;s_mean_x_q8_i=27'sd4096;s_mean_y_q8_i=27'sd4096;
   s_cov00_q8_i=32'd1024;s_cov11_q8_i=32'd1024;s_valid_i=1;tick();s_valid_i=0;
   count=0;timeout=0;while(count<4&&timeout<30)begin
     if(t_valid&&t_ready)begin
       if(t_desc!==16'habcd||tx!==(1+(count%2))||ty!==(1+(count/2))||first!==(count==0)||last!==(count==3))
         $fatal(1,"tile sequence mismatch count=%0d xy=%0d,%0d flags=%b,%b",count,tx,ty,first,last);
       count=count+1;
     end
     if(count==1&&timeout<4)t_ready=0;else t_ready=1;
     tick();timeout=timeout+1;
   end
   if(count!=4)$fatal(1,"tile enumeration timeout");
   // Numeric overflow must retire as one culled event, not create a fake
   // full-screen traversal with an invalid conic.
   s_meta_i=16'hface;s_numeric_overflow_i=1;s_valid_i=1;while(!s_ready_o)tick();tick();s_valid_i=0;
   timeout=0;while(!t_valid&&timeout<20)begin tick();timeout=timeout+1;end
   if(!t_valid||!first||!last||!culled_event||tx!==0||ty!==0||!fullscreen)
     $fatal(1,"numeric invalid cull mismatch");
   $display("PASS: tb_bbox_tile_task");$finish;
 end
endmodule
