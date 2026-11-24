`timescale 1ns/1ps
module tb_gaussian_shape_block_reject;
  logic[11:0]block_x_i=0,block_y_i=0;
  logic[15:0]bbox_x0_i=0,bbox_x1_i=8,bbox_y0_i=0,bbox_y1_i=8,image_width_i=64,image_height_i=64;
  logic signed[26:0]mean_y_q8_i=0;logic signed[5:0]coordinate_shift_i=0,factor_shift_i=0;
  logic[14:0]l11_q12_i=4096;logic[12:0]opacity_q12_i=4096;logic reject_o;
  gaussian_shape_block_reject dut(.*);
  initial begin
    #1;if(reject_o)$fatal(1,"near block falsely rejected");
    mean_y_q8_i=40*256;#1;if(!reject_o)$fatal(1,"positive far block not rejected");
    mean_y_q8_i=-32*256;#1;if(!reject_o)$fatal(1,"negative far block not rejected");
    mean_y_q8_i=3*256+128;opacity_q12_i=0;#1;if(!reject_o)$fatal(1,"zero-opacity block not rejected");
    opacity_q12_i=4096;l11_q12_i=0;#1;if(reject_o)$fatal(1,"zero-l11 block falsely rejected");
    opacity_q12_i=0;bbox_x0_i=8;#1;if(reject_o)$fatal(1,"empty x block counted as shape reject");
    bbox_x0_i=0;bbox_y0_i=8;#1;if(reject_o)$fatal(1,"empty y block counted as shape reject");
    $display("PASS: tb_gaussian_shape_block_reject");$finish;
  end
endmodule
