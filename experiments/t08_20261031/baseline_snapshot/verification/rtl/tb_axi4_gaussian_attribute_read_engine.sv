`timescale 1ns/1ps
module tb_axi4_gaussian_attribute_read_engine;
  localparam ATTR_W=1118;logic clk_i=0,rst_ni=0,clear_error_i=0;
  logic[63:0]base_addr_i;logic req_valid_i=0,req_ready_o;logic[31:0]req_gid_i;
  logic rsp_valid_o,rsp_ready_i=1,rsp_error_o,busy_o,error_sticky_o;logic[1:0]error_status_o;
  logic[ATTR_W-1:0]rsp_data_o;logic[1:0]m_axi_arid_o,m_axi_rid_i=0;logic[63:0]m_axi_araddr_o;
  logic[7:0]m_axi_arlen_o;logic[2:0]m_axi_arsize_o;logic[1:0]m_axi_arburst_o;
  logic m_axi_arvalid_o,m_axi_arready_i=0;logic[127:0]m_axi_rdata_i;logic[1:0]m_axi_rresp_i=0;
  logic m_axi_rlast_i,m_axi_rvalid_i=0,m_axi_rready_o;integer beat_seed;
  always#5 clk_i=~clk_i;axi4_gaussian_attribute_read_engine dut(.*);
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic request(input[63:0]base,input[31:0]gid);begin
    while(!req_ready_o)tick();base_addr_i=base;req_gid_i=gid;req_valid_i=1;tick();req_valid_i=0;
  end endtask
  task automatic ar(input[63:0]addr,input[7:0]len);begin
    while(!m_axi_arvalid_o)tick();if(m_axi_araddr_o!==addr||m_axi_arlen_o!==len)$fatal(1,"AR mismatch");
    m_axi_arready_i=1;tick();m_axi_arready_i=0;
  end endtask
  task automatic rbeat(input integer n,input last,input[1:0]resp);begin
    @(negedge clk_i);m_axi_rdata_i={4{32'h10000000+n}};m_axi_rlast_i=last;m_axi_rresp_i=resp;m_axi_rvalid_i=1;
    do @(posedge clk_i);while(!m_axi_rready_o);#1;m_axi_rvalid_i=0;m_axi_rresp_i=0;
  end endtask
  initial begin integer i;base_addr_i=0;req_gid_i=0;m_axi_rdata_i=0;m_axi_rlast_i=0;
    repeat(2)tick();rst_ni=1;tick();
    request(64'h1000,2);ar(64'h1120,8);for(i=0;i<9;i=i+1)rbeat(i,i==8,0);
    if(!rsp_valid_o||rsp_error_o)$fatal(1,"normal attribute response missing");
    rsp_ready_i=0;repeat(3)begin tick();if(!rsp_valid_o)$fatal(1,"response not held");end
    for(i=0;i<8;i=i+1)if(rsp_data_o[i*128+:128]!=={4{32'h10000000+i}})$fatal(1,"beat assembly mismatch");
    rsp_ready_i=1;tick();
    // base 0xF80 and gid0: first 8 beats end exactly at 4 KiB, last beat resumes at 0x1000.
    request(64'hf80,0);ar(64'hf80,7);for(i=0;i<8;i=i+1)rbeat(i,i==7,0);
    ar(64'h1000,0);rbeat(8,1,0);if(!rsp_valid_o||rsp_error_o)$fatal(1,"4K split failed");tick();
    request(64'h2008,0);if(!rsp_valid_o)tick();if(!rsp_error_o||error_status_o!==2'b10)$fatal(1,"align error");tick();
    request(64'h3000,0);ar(64'h3000,8);rbeat(0,1,0);if(!rsp_valid_o)tick();
    if(!rsp_error_o||error_status_o[0]!==1)$fatal(1,"protocol error missing");tick();
    $display("PASS: tb_axi4_gaussian_attribute_read_engine");$finish;
  end
endmodule
