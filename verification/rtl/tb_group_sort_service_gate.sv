`timescale 1ns/1ps
module tb_group_sort_service_gate;
  logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o,m_valid_o,m_ready_i=1;
  logic[2:0]cfg_active_lanes_i=4;
  logic service_grant_o,service_stall_o;
  integer accepts;
  always #5 clk_i=~clk_i;

  group_sort_service_gate #(.PHYSICAL_LANES(4))dut(
    .clk_i(clk_i),.rst_ni(rst_ni),.cfg_active_lanes_i(cfg_active_lanes_i),
    .s_valid_i(s_valid_i),.s_ready_o(s_ready_o),.m_valid_o(m_valid_o),
    .m_ready_i(m_ready_i),.service_grant_o(service_grant_o),
    .service_stall_o(service_stall_o));

  task automatic tick;begin @(posedge clk_i);#1;end endtask
  task automatic measure(input integer lanes,input integer cycles,input integer expected);
    integer i;begin
      cfg_active_lanes_i=lanes;s_valid_i=0;tick();s_valid_i=1;#1;accepts=0;
      for(i=0;i<cycles;i=i+1)begin
        if(m_valid_o&&m_ready_i)accepts=accepts+1;
        tick();
      end
      if(accepts!=expected)$fatal(1,"lanes=%0d accepts=%0d expected=%0d",lanes,accepts,expected);
      s_valid_i=0;tick();
    end
  endtask

  initial begin
    repeat(2)tick();rst_ni=1;tick();
    measure(4,8,8);
    measure(2,8,4);
    measure(1,8,2);
    cfg_active_lanes_i=2;s_valid_i=1;m_ready_i=0;tick();
    if(!m_valid_o||!service_grant_o)$fatal(1,"granted beat not held under backpressure");
    repeat(3)begin tick();if(!m_valid_o||!service_grant_o)$fatal(1,"grant changed under backpressure");end
    m_ready_i=1;tick();s_valid_i=0;tick();
    cfg_active_lanes_i=0;s_valid_i=1;tick();
    if(m_valid_o||s_ready_o||!service_stall_o)$fatal(1,"zero-lane fail-closed behavior mismatch");
    $display("PASS: tb_group_sort_service_gate");$finish;
  end
endmodule
