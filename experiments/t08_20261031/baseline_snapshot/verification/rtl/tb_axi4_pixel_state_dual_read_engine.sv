`timescale 1ns/1ps
module tb_axi4_pixel_state_dual_read_engine;
  logic clk_i=0,rst_ni=0,clear_error_i=0;logic[63:0]base_addr_i=64'h1000;
  logic req_valid_i=0,req_ready_o,req_tag_i=0;logic[31:0]req_pixel_id_i=0;
  logic rsp_valid_o,rsp_ready_i=0,rsp_tag_o,rsp_error_o;logic[127:0]rsp_data_o;
  logic busy_o,error_sticky_o;logic[1:0]error_status_o,m_axi_arid_o,m_axi_rid_i=0;
  logic[63:0]m_axi_araddr_o;logic[7:0]m_axi_arlen_o;logic[2:0]m_axi_arsize_o;
  logic[1:0]m_axi_arburst_o;logic m_axi_arvalid_o,m_axi_arready_i=0;
  logic[127:0]m_axi_rdata_i=0;logic[1:0]m_axi_rresp_i=0;
  logic m_axi_rlast_i=1,m_axi_rvalid_i=0,m_axi_rready_o;
  always#5 clk_i=~clk_i;axi4_pixel_state_dual_read_engine dut(.*);
  initial begin #5000;$fatal(1,"dual reader timeout ar=%b out=%b rsp=%b",dut.ar_valid_q,dut.outstanding_q,dut.rsp_valid_q);end
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic request(input tag,input[31:0]pixel);begin
    req_tag_i=tag;req_pixel_id_i=pixel;req_valid_i=1;
    #1;while(!req_ready_o)tick();tick();req_valid_i=0;
    if(!m_axi_arvalid_o||m_axi_arid_o!==tag||m_axi_araddr_o!==base_addr_i+pixel*16)
      $fatal(1,"bad AR tag=%0d pixel=%0d",tag,pixel);
    m_axi_arready_i=1;tick();m_axi_arready_i=0;
  end endtask
  task automatic send_r(input tag,input[127:0]data,input[1:0]resp,input last);begin
    m_axi_rid_i=tag;m_axi_rdata_i=data;m_axi_rresp_i=resp;m_axi_rlast_i=last;m_axi_rvalid_i=1;
    tick();m_axi_rvalid_i=0;
  end endtask
  task automatic expect_rsp(input tag,input[127:0]data,input err);begin
    if(!rsp_valid_o||rsp_tag_o!==tag||rsp_data_o!==data||rsp_error_o!==err)
      $fatal(1,"bad rsp tag=%0d data=%h err=%b",rsp_tag_o,rsp_data_o,rsp_error_o);
    rsp_ready_i=1;tick();rsp_ready_i=0;
  end endtask
  initial begin
    repeat(2)tick();rst_ni=1;tick();request(0,3);request(1,7);
    // AXI is allowed to return ID1 before ID0.
    send_r(1,128'h71,0,1);
    // ID1 became externally visible first. While downstream ready is low, a
    // later ID0 return must not preempt that stable ready/valid payload.
    expect_rsp(1,128'h71,0);send_r(0,128'h30,0,1);expect_rsp(0,128'h30,0);
    request(1,9);send_r(1,128'h91,2'b10,1);expect_rsp(1,128'h91,1);
    if(!error_status_o[0]||!error_sticky_o)$fatal(1,"error status missing");
    clear_error_i=1;tick();clear_error_i=0;if(error_status_o!=0)$fatal(1,"clear failed");
    if(busy_o)$fatal(1,"reader not idle");
    $display("PASS: tb_axi4_pixel_state_dual_read_engine");$finish;
  end
endmodule
