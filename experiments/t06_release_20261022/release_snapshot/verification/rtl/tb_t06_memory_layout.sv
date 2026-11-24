`timescale 1ns/1ps
module tb_t06_memory_layout;
  parameter MAX_COUNT=7000000,MAX_PIXELS=16384;
  `include "verification/rtl/t06_memory_layout.svh"
  integer fault=0;
  initial begin
    if($value$plusargs("FAULT=%d",fault))begin end
    #1;
    case(fault)
      0:begin
        check_region(MEAN_BASE,16,MEAN_BASE,64'(MAX_COUNT)*16);
        check_region(ATTR_BASE+64'(MAX_COUNT)*144-16,16,ATTR_BASE,64'(MAX_COUNT)*144);
        check_region(QSU_BASE,64'(MAX_COUNT)*32,QSU_BASE,64'(MAX_COUNT)*32);
      end
      1:check_region(MEAN_BASE-16,16,MEAN_BASE,64'(MAX_COUNT)*16);
      2:check_region(ATTR_BASE+64'(MAX_COUNT)*144-16,32,ATTR_BASE,64'(MAX_COUNT)*144);
      3:check_region(64'hfffffffffffffff0,32,MEAN_BASE,64'(MAX_COUNT)*16);
      4:check_region(MEAN_BASE,0,MEAN_BASE,64'(MAX_COUNT)*16);
    endcase
    $display("PASS T06 common memory layout");$finish;
  end
endmodule
