`timescale 1ns/1ps
module tb_t08_attribute_dma;
  logic clk_i=0,rst_ni=0,clear_error_i=0;
  logic [63:0] base_addr_i=0;logic [1:0] format_i=0;
  logic req_valid_i=0,req_ready_o;logic [31:0] req_gid_i=0;
  logic rsp_valid_o,rsp_ready_i=0,rsp_error_o,busy_o,error_sticky_o;
  logic [1117:0] rsp_data_o;logic [245:0] rsp_covariance_q20_o;
  logic rsp_precomputed_o;logic [1:0] rsp_degree_o,error_status_o;
  logic [1:0] m_axi_arid_o,m_axi_rid_i=0;logic [63:0] m_axi_araddr_o;
  logic [7:0] m_axi_arlen_o;logic [2:0] m_axi_arsize_o;logic [1:0] m_axi_arburst_o;
  logic m_axi_arvalid_o,m_axi_arready_i=0;
  logic [127:0] m_axi_rdata_i=0;logic [1:0] m_axi_rresp_i=0;
  logic m_axi_rlast_i=0,m_axi_rvalid_i=0,m_axi_rready_o;
  logic [1157:0] inputs[0:8191];logic [1367:0] expected[0:8191];
  logic [1367:0] actual,held;
  logic [1151:0] packet;
  integer n,beats,offset,burst,formats,tests=0;longint unsigned transferred=0,bursts=0;
  logic [63:0] addr;string input_path,expected_path;
  assign actual={rsp_error_o,rsp_precomputed_o,rsp_degree_o,rsp_data_o,rsp_covariance_q20_o};
  always #5 clk_i=~clk_i;
  axi4_t08_attribute_read_engine #(.ENABLE_Q24(1'b1),.EARLY_ADVANCE(1'b0)) dut(.*);
  task automatic tick;@(posedge clk_i);#1;endtask
  task automatic request(input logic[63:0] base,input logic[31:0] gid,input logic[1:0] fmt);
    begin
      while(!req_ready_o)tick();@(negedge clk_i);
      base_addr_i=base;req_gid_i=gid;format_i=fmt;req_valid_i=1;tick();req_valid_i=0;
      // Shadows may change immediately after acceptance; request is immutable.
      base_addr_i=64'hfffffffffffffff8;req_gid_i=32'hffffffff;format_i=fmt^2'd3;
    end
  endtask
  task automatic accept_ar(input logic[63:0] address,input integer count);
    begin
      while(!m_axi_arvalid_o)tick();
      repeat(2)begin
        if(m_axi_araddr_o!==address||int'(m_axi_arlen_o)+1!=count||m_axi_arid_o!=0||
           m_axi_arsize_o!=4||m_axi_arburst_o!=1||int'(address[11:0])+count*16>4096)
          $fatal(1,"invalid AR addr=%h/%h beats=%0d/%0d",m_axi_araddr_o,address,m_axi_arlen_o+1,count);
        tick();
      end
      m_axi_arready_i=1;tick();m_axi_arready_i=0;bursts++;
    end
  endtask
  task automatic send_r(input logic[127:0] value,input logic last,input logic[1:0] response,input logic[1:0] id);
    begin
      @(negedge clk_i);m_axi_rdata_i=value;m_axi_rlast_i=last;m_axi_rresp_i=response;m_axi_rid_i=id;m_axi_rvalid_i=1;
      do @(posedge clk_i);while(!m_axi_rready_o);
      #1;m_axi_rvalid_i=0;m_axi_rresp_i=0;m_axi_rid_i=0;transferred++;
    end
  endtask
  task automatic finish_response(input logic want_error,input logic[1367:0] wanted);
    begin
      while(!rsp_valid_o)tick();
      if(rsp_error_o!==want_error||(!want_error&&actual!==wanted))$fatal(1,"response mismatch test=%0d got=%h want=%h",tests,actual,wanted);
      held=actual;
      repeat(3)begin tick();if(!rsp_valid_o||actual!==held||req_ready_o)$fatal(1,"response hold/ownership");end
      rsp_ready_i=1;tick();rsp_ready_i=0;tests++;
      if(busy_o||!req_ready_o)$fatal(1,"not idle after response");
    end
  endtask
  task automatic clear_error;
    begin clear_error_i=1;tick();clear_error_i=0;if(error_sticky_o)$fatal(1,"clear failed");end
  endtask
  initial begin
    if(!$value$plusargs("N=%d",n)||n<=0||n>8192)$fatal;
    if(!$value$plusargs("INPUT=%s",input_path)||!$value$plusargs("EXPECTED=%s",expected_path))$fatal;
    $readmemh(input_path,inputs,0,n-1);$readmemh(expected_path,expected,0,n-1);
    repeat(3)tick();rst_ni=1;tick();
    for(integer i=0;i<n;i++)begin
      {formats[1:0],beats[3:0],packet}=inputs[i];formats=formats&3;beats=beats&15;
      addr=((i/32)%2==0)?(64'h1000-16*(1+(i/4)%8)):(64'h2000+16*((i/4)%8));
      request(addr-64'(i%7)*144,32'(i%7),2'(formats));offset=0;
      while(offset<beats)begin
        burst=offset==0&&formats==2 ? 8 : (offset==0&&formats==1?1:beats-offset);
        if(burst>(4096-int'(addr[11:0]))/16)burst=(4096-int'(addr[11:0]))/16;
        accept_ar(addr,burst);
        for(integer j=0;j<burst;j++)begin
          if((i+j)%3==0)tick();
          send_r(offset+j>=beats ? {128{1'b1}} : packet[(offset+j)*128+:128],j==burst-1,0,0);
        end
        offset+=burst;addr+=64'(burst)*16;
      end
      finish_response(0,expected[i]);if(error_sticky_o)$fatal(1,"unexpected sticky error");
    end
    $display("T08_DMA_DATA records=%0d beats=%0d bursts=%0d",n,transferred,bursts);
    request(64'h2008,0,0);finish_response(1,'0);if(error_status_o!=2) $fatal;clear_error();
    request(64'h2000,0,2);accept_ar(64'h2000,8);send_r(128'h01c8,0,0,0);for(int k=0;k<7;k++)begin if(rsp_valid_o||req_ready_o)$fatal;send_r(0,k==6,0,0);end finish_response(1,'0);clear_error();
    request(64'hfffffffffffffff0,1,0);finish_response(1,'0);clear_error();
    request(64'h2000,0,1);accept_ar(64'h2000,1);send_r(0,1,0,0);finish_response(1,'0);clear_error();
    request(64'h2000,0,1);accept_ar(64'h2000,1);send_r(128'h2c8,1,0,0);finish_response(1,'0);if(error_status_o!=2)$fatal;clear_error();
    request(64'h2000,0,1);accept_ar(64'h2000,1);send_r(128'h3ec8,1,0,0);finish_response(1,'0);if(error_status_o!=2)$fatal;clear_error();
    request(64'h2000,0,2);accept_ar(64'h2000,8);send_r(128'h3dc8,0,0,0);for(int k=0;k<7;k++)begin if(rsp_valid_o||req_ready_o)$fatal;send_r(0,k==6,0,0);end finish_response(1,'0);if(error_status_o!=2)$fatal;clear_error();
    request(64'h2000,0,2);accept_ar(64'h2000,8);send_r(128'h6c8,0,0,0);for(int k=0;k<7;k++)begin if(rsp_valid_o||req_ready_o)$fatal;send_r(0,k==6,0,0);end finish_response(1,'0);if(error_status_o!=2)$fatal;clear_error();
    request(64'h2000,0,1);accept_ar(64'h2000,1);send_r(128'h5c8,1,0,0);finish_response(1,'0);if(error_status_o!=2)$fatal;clear_error();
    // Faults on a partially consumed v2 burst, including the padding beat.
    for(int fault=0;fault<4;fault++)begin
      request(64'h2000,0,2);accept_ar(64'h2000,8);
      send_r(128'h02c8,0,0,0);
      if(fault==0)send_r(0,1,0,0);
      else begin
        send_r(0,0,0,fault==1?1:0);send_r(0,0,0,0);
        repeat(4)send_r(0,0,0,0);send_r(0,fault!=3,fault==2?2:0,0);
        if(fault==3)begin if(rsp_valid_o||req_ready_o)$fatal;send_r(0,1,0,0);end
      end
      finish_response(1,'0);if(!error_status_o[0])$fatal;clear_error();
    end
    // Early RLAST, wrong RID, bus error, and a missing/late terminator.
    for(integer fault=0;fault<4;fault++)begin
      request(64'h2000,0,0);accept_ar(64'h2000,9);
      if(fault==0)send_r(0,1,0,0);
      else begin
        for(integer j=0;j<(fault==3?10:9);j++)begin
          if(fault==3&&j==9)begin
            req_valid_i=1;
            if(rsp_valid_o||req_ready_o||!m_axi_rready_o)$fatal(1,"released before actual RLAST");
          end
          send_r(0,j==(fault==3?9:8),(fault==2&&j==2)?2:0,(fault==1&&j==2)?1:0);
          req_valid_i=0;
        end
      end
      finish_response(1,'0);if(!error_status_o[0])$fatal;clear_error();
    end
    // Successful request after all errors, including idle reset.
    rst_ni=0;tick();rst_ni=1;tick();
    request(64'h2000,0,0);accept_ar(64'h2000,9);
    for(integer j=0;j<9;j++)send_r(0,j==8,0,0);
    finish_response(0,1368'(3)<<1364);
    $display("PASS T08 attribute DMA data_records=%0d control_cases=%0d",n,tests-n);$finish;
  end
  initial begin #100000000;$fatal(1,"DMA test watchdog");end
endmodule
