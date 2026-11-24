`timescale 1ns/1ps
module tb_gaussian_attribute_store;
  localparam GID_W=5,DEPTH=8,COORD_W=27,QUAT_W=22,SCALE_W=24,COEFF_W=18,FLAT_W=3*16*COEFF_W;
  logic clk_i=0,rst_ni=0,clear_valid_i=0,clear_errors_i=0,write_en_i=0,read_en_i=0;
  logic[GID_W-1:0]write_gid_i=0,read_gid_i=0;logic signed[COORD_W-1:0]write_world_x_q16_i=0,write_world_y_q16_i=0,write_world_z_q16_i=0;
  logic signed[QUAT_W-1:0]write_qw_q20_i=0,write_qx_q20_i=0,write_qy_q20_i=0,write_qz_q20_i=0;
  logic[SCALE_W-1:0]write_scale_x_q20_i=0,write_scale_y_q20_i=0,write_scale_z_q20_i=0;logic[12:0]write_opacity_q12_i=0;
  logic[FLAT_W-1:0]write_coeff_q12_flat_i=0;logic read_response_valid_o,read_in_range_o,read_loaded_o;
  logic signed[COORD_W-1:0]read_world_x_q16_o,read_world_y_q16_o,read_world_z_q16_o;
  logic signed[QUAT_W-1:0]read_qw_q20_o,read_qx_q20_o,read_qy_q20_o,read_qz_q20_o;
  logic[SCALE_W-1:0]read_scale_x_q20_o,read_scale_y_q20_o,read_scale_z_q20_o;logic[12:0]read_opacity_q12_o;
  logic[FLAT_W-1:0]read_coeff_q12_flat_o;logic invalid_write_sticky_o,invalid_read_sticky_o,unloaded_read_sticky_o;
  always#5 clk_i=~clk_i;
  gaussian_attribute_store #(.DEPTH(DEPTH),.GID_W(GID_W))dut(.*);
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic write_record(input integer gid,input integer marker);begin
    write_gid_i=gid;write_world_x_q16_i=marker;write_world_y_q16_i=-marker;write_world_z_q16_i=marker+2;
    write_qw_q20_i=marker+3;write_qx_q20_i=marker+4;write_qy_q20_i=marker+5;write_qz_q20_i=marker+6;
    write_scale_x_q20_i=marker+7;write_scale_y_q20_i=marker+8;write_scale_z_q20_i=marker+9;
    write_opacity_q12_i=marker+10;write_coeff_q12_flat_i='0;write_coeff_q12_flat_i[0+:COEFF_W]=marker+11;
    write_en_i=1;tick();write_en_i=0;
  end endtask
  task automatic read_record(input integer gid);begin read_gid_i=gid;read_en_i=1;tick();read_en_i=0;end endtask
  initial begin
    repeat(2)tick();rst_ni=1;tick();
    write_record(1,100);write_record(6,300);read_record(1);
    if(!read_response_valid_o||!read_in_range_o||!read_loaded_o||read_world_x_q16_o!==100||
       read_world_y_q16_o!==-100||read_scale_z_q20_o!==109||read_opacity_q12_o!==110||read_coeff_q12_flat_o[0+:COEFF_W]!==111)
      $fatal(1,"loaded record mismatch");
    // The bank wrapper contract is write-through on a same-address read/write.
    write_gid_i=1;read_gid_i=1;write_world_x_q16_i=777;write_world_y_q16_i=-777;write_world_z_q16_i=779;
    write_qw_q20_i=780;write_qx_q20_i=781;write_qy_q20_i=782;write_qz_q20_i=783;
    write_scale_x_q20_i=784;write_scale_y_q20_i=785;write_scale_z_q20_i=786;write_opacity_q12_i=787;
    write_coeff_q12_flat_i='0;write_coeff_q12_flat_i[0+:COEFF_W]=788;write_en_i=1;read_en_i=1;tick();write_en_i=0;read_en_i=0;
    if(!read_loaded_o||read_world_x_q16_o!==777||read_coeff_q12_flat_o[0+:COEFF_W]!==788)$fatal(1,"write-through failed");
    read_record(3);if(!read_in_range_o||read_loaded_o||!unloaded_read_sticky_o)$fatal(1,"unloaded GID not detected");
    read_record(9);if(read_in_range_o||read_loaded_o||!invalid_read_sticky_o)$fatal(1,"out-of-range read not detected");
    write_gid_i=12;write_en_i=1;tick();write_en_i=0;if(!invalid_write_sticky_o)$fatal(1,"out-of-range write not detected");
    clear_errors_i=1;tick();clear_errors_i=0;if(invalid_write_sticky_o||invalid_read_sticky_o||unloaded_read_sticky_o)$fatal(1,"error clear failed");
    clear_valid_i=1;tick();clear_valid_i=0;read_record(6);if(read_loaded_o)$fatal(1,"valid clear failed");
    $display("PASS: tb_gaussian_attribute_store");$finish;
  end
endmodule
