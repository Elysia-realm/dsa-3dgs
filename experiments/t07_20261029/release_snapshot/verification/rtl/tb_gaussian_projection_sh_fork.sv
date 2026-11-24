`timescale 1ns/1ps
module tb_gaussian_projection_sh_fork;
  logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o;logic[15:0]s_projection_data_i=0;logic[23:0]s_sh_data_i=0;
  logic projection_valid_o,projection_ready_i=0;logic[15:0]projection_data_o;
  logic sh_valid_o,sh_ready_i=0;logic[23:0]sh_data_o;logic empty_o;logic[2:0]occupancy_o;
  always#5 clk_i=~clk_i;gaussian_projection_sh_fork #(.PROJ_W(16),.SH_W(24),.DEPTH(4))dut(.*);
  initial begin #200000;$fatal(1,"fork watchdog valid=%b,%b ready=%b,%b occ=%0d",projection_valid_o,sh_valid_o,projection_ready_i,sh_ready_i,occupancy_o);end
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic send(input integer n);begin while(!s_ready_o)tick();s_projection_data_i=16'h1000+n;s_sh_data_i=24'h200000+n;s_valid_i=1;tick();s_valid_i=0;end endtask
  initial begin integer n;repeat(2)tick();rst_ni=1;tick();
    // Projection drains immediately while SH stalls: four accepted records
    // must remain intact in the independent SH branch.
    projection_ready_i=1;sh_ready_i=0;for(n=0;n<4;n=n+1)send(n);
    if(s_ready_o||occupancy_o!==4)$fatal(1,"fork capacity/occupancy mismatch");
    sh_ready_i=1;for(n=0;n<4;n=n+1)begin while(!sh_valid_o)tick();if(sh_data_o!==(24'h200000+n))$fatal(1,"SH fork order mismatch n=%0d",n);tick();end
    // Reverse the branch rates and verify projection copies were not lost.
    projection_ready_i=0;send(8);send(9);sh_ready_i=1;repeat(2)tick();projection_ready_i=1;
    for(n=8;n<10;n=n+1)begin while(!projection_valid_o)tick();if(projection_data_o!==(16'h1000+n))$fatal(1,"projection fork mismatch");tick();end
    if(!empty_o)$fatal(1,"fork did not drain");$display("PASS: tb_gaussian_projection_sh_fork");$finish;
  end
endmodule
