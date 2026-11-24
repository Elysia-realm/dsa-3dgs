// One common, non-overlapping physical address space for all AXI ports.
// Separate arrays model disjoint regions, never overlapping aliases.
localparam logic [63:0] CAMERA_BASE=64'h00002000;
localparam logic [63:0] MEAN_BASE=64'h01000000;
localparam logic [63:0] ATTR_BASE=64'h10000000;
localparam logic [63:0] QSU_BASE=64'h60000000;
localparam logic [63:0] OUTPUT_BASE=64'h70000000;
task automatic check_region(input logic [63:0] addr, bytes, base, size);
  if(bytes==0 || addr<base || addr+bytes<addr || addr+bytes>base+size)
    $fatal(1,"AXI region violation addr=%h bytes=%0d base=%h size=%0d",addr,bytes,base,size);
endtask
initial begin
  if(CAMERA_BASE+224>MEAN_BASE ||
     MEAN_BASE+64'(MAX_COUNT)*16>ATTR_BASE ||
     ATTR_BASE+64'(MAX_COUNT)*144>QSU_BASE ||
     QSU_BASE+64'(MAX_COUNT)*32>OUTPUT_BASE ||
     OUTPUT_BASE+64'(MAX_PIXELS)*32>64'h80000000)
    $fatal(1,"overlapping or overflowing common DMA address layout");
  $display("REAL_ADDRESS_LAYOUT camera=%h mean=%h attr=%h scratch=%h output=%h max_count=%0d max_pixels=%0d disjoint=1",CAMERA_BASE,MEAN_BASE,ATTR_BASE,QSU_BASE,OUTPUT_BASE,MAX_COUNT,MAX_PIXELS);
end
