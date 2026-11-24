`timescale 1ns/1ps
module tb_t07_shape_vectors;
  logic[11:0]block_x_i,block_y_i;
  logic[15:0]bbox_x0_i,bbox_x1_i,bbox_y0_i,bbox_y1_i,image_width_i,image_height_i;
  logic signed[26:0]mean_y_q8_i;logic signed[5:0]coordinate_shift_i,factor_shift_i;
  logic[14:0]l11_q12_i;logic[12:0]opacity_q12_i;logic reject_o,expected;
  logic[187:0]vectors[0:19999];string path;integer rejected=0;
  gaussian_shape_block_reject dut(.*);
  initial begin
    if(!$value$plusargs("INPUT=%s",path))$fatal(1,"INPUT required");
    $readmemh(path,vectors);
    for(integer i=0;i<20000;i=i+1)begin
      {block_x_i,block_y_i,bbox_x0_i,bbox_x1_i,bbox_y0_i,bbox_y1_i,image_width_i,image_height_i,
       mean_y_q8_i,coordinate_shift_i,factor_shift_i,l11_q12_i,opacity_q12_i,expected}=vectors[i];
      #1;if(reject_o!==expected)$fatal(1,"shape reference mismatch vector=%0d",i);
      if(reject_o)rejected=rejected+1;
    end
    if(rejected==0)$fatal(1,"no rejected cases");
    $display("PASS T07_SHAPE vectors=20000 rejected=%0d",rejected);$finish;
  end
endmodule
