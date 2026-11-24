`timescale 1ns/1ps
module tb_axi4_pixel_state_write_buffer;
  localparam DEPTH=4;
  logic clk_i=0,rst_ni=0,clear_error_i=0;logic[63:0]base_addr_i=64'h100000;
  logic s_valid_i=0,s_ready_o;logic[31:0]s_pixel_id_i,s_gid_i;logic[15:0]s_epoch_id_i=1;
  logic[12:0]s_alpha_q12_i=1;logic s_pass_alpha_i=1;logic[12:0]s_r_q12_i,s_g_q12_i=2,s_b_q12_i=3;
  logic[15:0]s_t_q16_i=16'hffff;logic s_newly_terminated_i=0;
  logic[31:0]hazard_pixel_id_i;logic hazard_o,busy_o,error_sticky_o;logic[1:0]error_status_o;
  logic[$clog2(DEPTH+1)-1:0]occupancy_o;logic[1:0]m_axi_awid_o,m_axi_bid_i=0;
  logic[63:0]m_axi_awaddr_o;logic[7:0]m_axi_awlen_o;logic[2:0]m_axi_awsize_o;
  logic[1:0]m_axi_awburst_o;logic m_axi_awvalid_o,m_axi_awready_i=0;
  logic[127:0]m_axi_wdata_o;logic[15:0]m_axi_wstrb_o;logic m_axi_wlast_o,m_axi_wvalid_o,m_axi_wready_i=0;
  logic[1:0]m_axi_bresp_i=0;logic m_axi_bvalid_i=0,m_axi_bready_o;integer expected=0;
  always#5 clk_i=~clk_i;
  axi4_pixel_state_write_buffer #(.DEPTH(DEPTH))dut(.*);
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic submit(input[31:0]pixel);begin
    while(!s_ready_o)tick();s_pixel_id_i=pixel;s_gid_i=pixel+100;s_r_q12_i=pixel[12:0];s_valid_i=1;tick();s_valid_i=0;
  end endtask
  task automatic accept_write;begin
    while(!m_axi_awvalid_o||!m_axi_wvalid_o)tick();
    if(m_axi_awaddr_o!==64'h100000+(expected<<4)||m_axi_wdata_o[12:0]!==expected[12:0])
      $fatal(1,"write order/payload expected=%0d addr=%h r=%0d",expected,m_axi_awaddr_o,m_axi_wdata_o[12:0]);
    m_axi_awready_i=1;m_axi_wready_i=1;tick();m_axi_awready_i=0;m_axi_wready_i=0;
  end endtask
  task automatic respond;begin
    while(!m_axi_bready_o)tick();m_axi_bvalid_i=1;tick();m_axi_bvalid_i=0;expected=expected+1;
  end endtask
  initial begin integer i;
    repeat(2)tick();rst_ni=1;tick();
    // One entry may reside in the underlying writer while DEPTH remain queued.
    for(i=0;i<=DEPTH;i=i+1)submit(i);
    if(occupancy_o!=DEPTH||s_ready_o)$fatal(1,"FIFO full backpressure missing");
    hazard_pixel_id_i=2;#1;if(!hazard_o)$fatal(1,"queued same-pixel hazard missing");
    hazard_pixel_id_i=99;#1;if(hazard_o)$fatal(1,"unrelated pixel falsely blocked");
    for(i=0;i<=DEPTH;i=i+1)begin
      accept_write();hazard_pixel_id_i=i;#1;if(!hazard_o)$fatal(1,"active write hazard dropped before B");
      respond();tick();
    end
    if(busy_o||occupancy_o!=0||error_sticky_o)$fatal(1,"buffer did not drain cleanly");
    hazard_pixel_id_i=3;#1;if(hazard_o)$fatal(1,"drained hazard remained set");
    $display("PASS: tb_axi4_pixel_state_write_buffer");$finish;
  end
endmodule
