`timescale 1ns/1ps
module tb_axi4_pixel_state_read_engine;
  logic clk_i=0,rst_ni=0,clear_error_i=0;
  logic[63:0]base_addr_i=64'h0000_0001_0000_1000;
  logic req_valid_i=0,req_ready_o;logic[31:0]req_pixel_id_i=0;
  logic rsp_valid_o,rsp_ready_i=0,rsp_error_o;logic[127:0]rsp_data_o;logic busy_o,error_sticky_o;
  logic[1:0]error_status_o,m_axi_arid_o,m_axi_rid_i=0;logic[63:0]m_axi_araddr_o;
  logic[7:0]m_axi_arlen_o;logic[2:0]m_axi_arsize_o;logic[1:0]m_axi_arburst_o;
  logic m_axi_arvalid_o,m_axi_arready_i=0;logic[127:0]m_axi_rdata_i=0;
  logic[1:0]m_axi_rresp_i=0;logic m_axi_rlast_i=1,m_axi_rvalid_i=0,m_axi_rready_o;
  always #5 clk_i=~clk_i;
  axi4_pixel_state_read_engine dut(.*);
  task automatic tick;begin @(posedge clk_i);#1;end endtask
  task automatic request(input[31:0]pixel);begin
    req_pixel_id_i=pixel;req_valid_i=1;tick();if(!busy_o)$fatal(1,"request not accepted");req_valid_i=0;
  end endtask
  task automatic accept_ar;begin
    if(!m_axi_arvalid_o||m_axi_arlen_o!=0||m_axi_arsize_o!=4||m_axi_arburst_o!=1)
      $fatal(1,"invalid AR attributes");
    m_axi_arready_i=1;tick();m_axi_arready_i=0;
  end endtask
  task automatic send_r(input[127:0]data,input[1:0]rid,input[1:0]resp,input last);begin
    m_axi_rdata_i=data;m_axi_rid_i=rid;m_axi_rresp_i=resp;m_axi_rlast_i=last;m_axi_rvalid_i=1;
    tick();m_axi_rvalid_i=0;
  end endtask
  task automatic consume_rsp(input expect_error);begin
    if(!rsp_valid_o||rsp_error_o!==expect_error)$fatal(1,"bad response error=%b",rsp_error_o);
    rsp_ready_i=1;tick();rsp_ready_i=0;
  end endtask
  initial begin
    repeat(2)tick();rst_ni=1;tick();
    request(32'd3);if(m_axi_araddr_o!==base_addr_i+48)$fatal(1,"bad address %h",m_axi_araddr_o);
    accept_ar();send_r(128'h0123456789abcdef_fedcba9876543210,0,0,1);
    if(!rsp_valid_o||rsp_data_o!==128'h0123456789abcdef_fedcba9876543210)$fatal(1,"bad normal data");
    repeat(2)begin tick();if(!rsp_valid_o||rsp_data_o!==128'h0123456789abcdef_fedcba9876543210)
      $fatal(1,"response not held");end
    consume_rsp(0);
    request(1);accept_ar();send_r(1,0,2'b10,1);consume_rsp(1);
    if(!error_status_o[0])$fatal(1,"RRESP error missing");
    clear_error_i=1;tick();clear_error_i=0;if(error_status_o!=0)$fatal(1,"clear failed");
    request(2);accept_ar();send_r(2,2'b01,0,1);consume_rsp(1);
    clear_error_i=1;tick();clear_error_i=0;
    request(4);accept_ar();send_r(3,0,0,0);consume_rsp(1);
    clear_error_i=1;tick();clear_error_i=0;base_addr_i=64'h1008;
    request(0);if(!rsp_valid_o||!rsp_error_o||!error_status_o[1]||m_axi_arvalid_o)
      $fatal(1,"alignment error missing");
    consume_rsp(1);
    $display("PASS: tb_axi4_pixel_state_read_engine");$finish;
  end
endmodule
