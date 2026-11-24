`timescale 1ns/1ps
module tb_t08_bbox_axis0;
  logic [15:0] x0_i,y0_i,x1_i,y1_i;
  logic signed [26:0] mean_x_i,mean_y_i;
  logic [14:0] l00_i;
  logic signed [15:0] l10_i;
  logic signed [5:0] coord_i,factor_i;
  logic [12:0] opacity_i;
  logic reject_o,expected;
  integer fd,n=0,rejected=0;
  string path;
  gaussian_bbox_axis0_reject dut(.*);
  initial begin
    if(!$value$plusargs("VECTORS=%s",path))$fatal;
    fd=$fopen(path,"r");if(!fd)$fatal;
    while($fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d %d",
        x0_i,y0_i,x1_i,y1_i,mean_x_i,mean_y_i,l00_i,l10_i,coord_i,factor_i,opacity_i,expected)==12)begin
      #1;
      if(reject_o!==expected)$fatal(1,"axis0 mismatch at %0d",n);
      n++;rejected+=int'(reject_o);
    end
    $display("AXIS0 counts %0d %0d",n,rejected);$finish;
  end
endmodule
