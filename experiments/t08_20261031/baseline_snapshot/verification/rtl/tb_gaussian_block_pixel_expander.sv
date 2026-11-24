`timescale 1ns/1ps
module tb_gaussian_block_pixel_expander;
  logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o;logic[15:0]s_meta_i='0;logic[11:0]s_block_x_i=0,s_block_y_i=0;
  logic[15:0]s_bbox_x0_i=0,s_bbox_y0_i=0,s_bbox_x1_i=0,s_bbox_y1_i=0;
  logic signed[26:0]s_mean_x_q8_i=0,s_mean_y_q8_i=0;logic signed[5:0]s_coordinate_shift_i=0;
  logic s_gaussian_first_block_i=0,s_gaussian_last_block_i=0,s_culled_i=0;logic[15:0]cfg_image_width_i=20,cfg_image_height_i=20;
  logic m_valid_o,m_ready_i=1;logic[15:0]m_meta_o;logic[15:0]m_pixel_x_o,m_pixel_y_o;logic[31:0]m_pixel_id_o;
  logic[5:0]m_pixel_in_block_o;logic signed[15:0]m_dx_q10_o,m_dy_q10_o;logic m_first_pixel_o,m_last_pixel_o;
  logic m_gaussian_first_block_o,m_gaussian_last_block_o,empty_or_culled_pulse_o;
  always#5 clk_i=~clk_i;gaussian_block_pixel_expander #(.META_W(16))dut(.*);
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic issue(input[15:0]meta,input integer bx,by,x0,y0,x1,y1,mx,my,input logic culled);begin
    while(!s_ready_o)tick();s_meta_i=meta;s_block_x_i=bx;s_block_y_i=by;s_bbox_x0_i=x0;s_bbox_y0_i=y0;s_bbox_x1_i=x1;s_bbox_y1_i=y1;
    s_mean_x_q8_i=mx;s_mean_y_q8_i=my;s_culled_i=culled;s_gaussian_first_block_i=1;s_gaussian_last_block_i=1;s_valid_i=1;tick();s_valid_i=0;end endtask
  initial begin integer count,timeout,ex,ey;repeat(2)tick();rst_ni=1;tick();
    issue(16'ha501,1,1,10,9,15,12,12*256+64,10*256+128,0);count=0;timeout=0;
    while(count<15&&timeout<80)begin m_ready_i=(timeout%4!=1);
      if(m_valid_o&&m_ready_i)begin ex=10+(count%5);ey=9+(count/5);
        if(m_meta_o!==16'ha501||m_pixel_x_o!==ex||m_pixel_y_o!==ey||m_pixel_id_o!==(ey*20+ex)
          ||m_pixel_in_block_o!==((ey-8)*8+ex-8)||m_dx_q10_o!==((ex*256-(12*256+64))*4)
          ||m_dy_q10_o!==((ey*256-(10*256+128))*4)||m_first_pixel_o!==(count==0)||m_last_pixel_o!==(count==14)
          ||!m_gaussian_first_block_o||!m_gaussian_last_block_o)$fatal(1,"expander mismatch count=%0d xy=%0d,%0d",count,m_pixel_x_o,m_pixel_y_o);
        count=count+1;end tick();timeout=timeout+1;end
    if(count!=15)$fatal(1,"expander output timeout count=%0d",count);
    // Image bounds clip tile (1,1) down to four pixels: (8..9,8..9).
    cfg_image_width_i=10;cfg_image_height_i=10;m_ready_i=1;issue(16'ha502,1,1,0,0,20,20,0,0,0);count=0;
    while(count<4)begin if(m_valid_o)begin ex=8+(count%2);ey=8+(count/2);if(m_pixel_x_o!==ex||m_pixel_y_o!==ey)$fatal(1,"image clip mismatch");count=count+1;end tick();end
    // Empty and explicitly culled blocks retire at their input handshake with no pixel output.
    issue(16'ha503,2,2,0,0,20,20,0,0,0);if(!empty_or_culled_pulse_o||m_valid_o)$fatal(1,"empty block not consumed");
    issue(16'ha504,0,0,0,0,8,8,0,0,1);if(!empty_or_culled_pulse_o||m_valid_o)$fatal(1,"culled block not consumed");
    // Large screen coordinates catch a narrow-before-shift Q8 implementation.
    cfg_image_width_i=16'd50000;cfg_image_height_i=16'd50000;
    issue(16'ha505,12'd3750,12'd2500,16'd30000,16'd20000,16'd30001,16'd20001,
      30000*256-128,20000*256+64,0);
    while(!m_valid_o)tick();
    if(m_pixel_x_o!==16'd30000||m_pixel_y_o!==16'd20000||m_dx_q10_o!==16'sd512||m_dy_q10_o!==-16'sd256)
      $fatal(1,"large-coordinate delta mismatch xy=%0d,%0d d=%0d,%0d",m_pixel_x_o,m_pixel_y_o,m_dx_q10_o,m_dy_q10_o);
    tick();
    $display("PASS: tb_gaussian_block_pixel_expander");$finish;
  end
endmodule
