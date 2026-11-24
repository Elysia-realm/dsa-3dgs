`timescale 1ns/1ps
module tb_t08_bbox_serial;
  logic clk_i=0,rst_ni=0,valid_i=0,keep_i=0,ready_i=0,ready_o,valid_o,reject_o;
  logic [15:0] x0_i,y0_i,x1_i,y1_i;
  logic signed [26:0] mean_x_i,mean_y_i;
  logic [14:0] l00_i;logic signed[15:0]l10_i;
  logic signed[5:0]coord_i,factor_i;logic[12:0]opacity_i;
  logic comb,was_stalled=0,held;
  integer cycles=0,n=0,yes=0,backs=0;
  always #5 clk_i=~clk_i;
  gaussian_bbox_axis0_serial dut(.*);
  gaussian_bbox_axis0_reject reference_predicate(.reject_o(comb),.*);
  always @(posedge clk_i) if(rst_ni)begin
    cycles++;
    if(cycles>3000000)$fatal(1,"watchdog");
    if(was_stalled && (!valid_o || reject_o!==held))$fatal(1,"response changed");
    was_stalled=valid_o&&!ready_i;held=reject_o;
    if(valid_o&&!ready_i)backs++;
    if(valid_o&&ready_i)begin
      if(reject_o!==(keep_i&&x1_i>x0_i&&y1_i>y0_i&&int'(x1_i)-int'(x0_i)>=128&&
             int'(y1_i)-int'(y0_i)>=128&&comb))$fatal(1,"mismatch %d cs=%d fs=%d",n,coord_i,factor_i);
      n++;yes+=int'(reject_o);
    end
    if((valid_o&&ready_i)!==(valid_i&&ready_o))$fatal(1,"lost or duplicate transfer");
  end else was_stalled=0;
  task automatic send;
    valid_i=1;
    do begin
      ready_i=($urandom_range(4)!=0);
      @(posedge clk_i);
      if(ready_o)begin @(negedge clk_i);break;end
      @(negedge clk_i);
    end while(1);
    valid_i=0;
  endtask
  initial begin
    repeat(3)@(negedge clk_i);rst_ni=1;
    x0_i=0;y0_i=0;x1_i=1024;y1_i=1024;keep_i=1;coord_i=0;factor_i=0;opacity_i=4096;
    l00_i=8192;l10_i=-32768;mean_x_i=0;mean_y_i=0;valid_i=1;ready_i=1;
    repeat(5)@(negedge clk_i);rst_ni=0;valid_i=0;@(negedge clk_i);rst_ni=1;
    for(integer i=0;i<8192;i++)begin
      x0_i=$urandom_range(32000);y0_i=$urandom_range(32000);
      x1_i=x0_i+$urandom_range(32000);y1_i=y0_i+$urandom_range(32000);
      if(i%17==0)x1_i=x0_i+127;
      if(i%17==1)y1_i=y0_i+128;
      mean_x_i=(i%2==0)?int'(x0_i)*256+$signed($urandom_range(2000000))-1000000:$urandom;
      mean_y_i=(i%2==0)?int'(y0_i)*256+$signed($urandom_range(2000000))-1000000:$urandom;
      l00_i=$urandom;l10_i=$urandom;if(i%19==0)l10_i=-32768;
      coord_i=$urandom_range(31);factor_i=$signed($urandom_range(34))-32;
      opacity_i=$urandom;if(i%23==0)opacity_i=0;
      keep_i=(i%31!=0);send();
    end
    // Single-sign endpoint products right at the conservative threshold;
    // both signs, inclusive last coordinate and exact 128-pixel enable boundary.
    for(integer k=-5;k<=5;k++)for(integer side=0;side<2;side++)begin
      x0_i=200;y0_i=200;x1_i=328;y1_i=328;mean_y_i=0;coord_i=0;factor_i=0;
      opacity_i=2049;l00_i=1024;l10_i=0;keep_i=1;
      mean_x_i=side?327*256+3413+k:200*256-3413-k;
      send();
    end
    if(n!=8214||yes==0||backs==0)$fatal;
    $display("PASS SERIAL transactions=%0d rejected=%0d stalled_cycles=%0d cycles=%0d",n,yes,backs,cycles);
    $finish;
  end
endmodule
