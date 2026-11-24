`timescale 1ns/1ps
module tb_axi4_pixel_state_write_engine;
  logic clk_i=0,rst_ni=0,clear_error_i=0;logic[63:0]base_addr_i;
  logic s_valid_i=0,s_ready_o;logic[31:0]s_pixel_id_i,s_gid_i;logic[15:0]s_epoch_id_i;
  logic[12:0]s_alpha_q12_i,s_r_q12_i,s_g_q12_i,s_b_q12_i;logic s_pass_alpha_i;
  logic[15:0]s_t_q16_i;logic s_newly_terminated_i,busy_o,error_sticky_o;logic[1:0]error_status_o;
  logic[1:0]m_axi_awid_o,m_axi_bid_i=0;logic[63:0]m_axi_awaddr_o;logic[7:0]m_axi_awlen_o;
  logic[2:0]m_axi_awsize_o;logic[1:0]m_axi_awburst_o;logic m_axi_awvalid_o,m_axi_awready_i=0;
  logic[127:0]m_axi_wdata_o;logic[15:0]m_axi_wstrb_o;logic m_axi_wlast_o,m_axi_wvalid_o,m_axi_wready_i=0;
  logic[1:0]m_axi_bresp_i=0;logic m_axi_bvalid_i=0,m_axi_bready_o;
  always#5 clk_i=~clk_i;axi4_pixel_state_write_engine dut(.*);
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic submit(input[31:0]pixel,input[12:0]r);begin
    while(!s_ready_o)tick();s_pixel_id_i=pixel;s_gid_i=32'h12345678;s_epoch_id_i=16'h55aa;
    s_alpha_q12_i=13'h345;s_pass_alpha_i=1;s_r_q12_i=r;s_g_q12_i=13'h222;s_b_q12_i=13'h333;
    s_t_q16_i=16'h4444;s_newly_terminated_i=1;s_valid_i=1;tick();s_valid_i=0;
  end endtask
  task automatic response(input[1:0]resp);begin
    while(!m_axi_bready_o)tick();m_axi_bresp_i=resp;m_axi_bvalid_i=1;tick();m_axi_bvalid_i=0;m_axi_bresp_i=0;
  end endtask
  initial begin logic[127:0]held;repeat(2)tick();rst_ni=1;tick();base_addr_i=64'h8000;
    submit(7,13'h111);if(m_axi_awaddr_o!==64'h8070||m_axi_awlen_o!=0||m_axi_awsize_o!=4)$fatal(1,"AW fields");
    held=m_axi_wdata_o;if(held[12:0]!=13'h111||held[25:13]!=13'h222||held[38:26]!=13'h333||
      held[54:39]!=16'h4444||held[70:55]!=16'h55aa||held[83:71]!=13'h345||held[117:86]!=32'h12345678)$fatal(1,"record pack");
    m_axi_awready_i=1;tick();m_axi_awready_i=0;repeat(2)begin tick();if(!m_axi_wvalid_o||m_axi_wdata_o!==held)$fatal(1,"W hold");end
    m_axi_wready_i=1;tick();m_axi_wready_i=0;response(0);if(busy_o||error_sticky_o)$fatal(1,"normal completion");
    submit(7,13'h777);m_axi_awready_i=1;m_axi_wready_i=1;tick();m_axi_awready_i=0;m_axi_wready_i=0;response(2'b10);
    if(error_status_o!==2'b01)$fatal(1,"BRESP missing");
    while(!s_ready_o)tick();base_addr_i=64'h8008;submit(0,0);tick();if(error_status_o!==2'b11||m_axi_awvalid_o)$fatal(1,"align error");
    $display("PASS: tb_axi4_pixel_state_write_engine");$finish;
  end
endmodule
