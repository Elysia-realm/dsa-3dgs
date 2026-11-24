`timescale 1ns/1ps
module tb_t06_scratch_dma;
  logic clk_i=0,rst_ni=0;always #5 clk_i=~clk_i;
  localparam MAX_COUNT=512;integer workload_count=512;
  integer read_latency=4,read_gap=1,ready_period=5,ready_low=2,write_response_latency=13;
`include "verification/rtl/t06_scratch_signals.svh"
`include "verification/rtl/t06_scratch_memory.svh"
  logic clear=0;logic [63:0] base=64'h10000000;
  logic rd_valid=0,rd_ready,rd_bank=0,r_valid,r_ready=0,r_last,rd_busy;
  logic [31:0] rd_offset=0,rd_count=0;logic [127:0] r_data;
  logic wr_valid=0,wr_ready,wr_bank=0,wr_busy,error;
  logic [31:0] wr_offset=0;logic [127:0] wr_data=0;logic [1:0] status;
  integer got=0;logic check_data=0;
  axi4_qsu_scratch_dma dut(
    .clk_i(clk_i),.rst_ni(rst_ni),.clear_i(clear),.base_i(base),.capacity_i(32'd512),
    .rd_valid_i(rd_valid),.rd_ready_o(rd_ready),.rd_bank_i(rd_bank),.rd_offset_i(rd_offset),.rd_count_i(rd_count),
    .r_valid_o(r_valid),.r_ready_i(r_ready),.r_data_o(r_data),.r_last_o(r_last),.rd_busy_o(rd_busy),
    .wr_valid_i(wr_valid),.wr_ready_o(wr_ready),.wr_bank_i(wr_bank),.wr_offset_i(wr_offset),.wr_data_i(wr_data),
    .wr_busy_o(wr_busy),.error_o(error),.error_status_o(status),
    .m_axi_arid_o(m_axi_qsu_arid_o),.m_axi_araddr_o(m_axi_qsu_araddr_o),.m_axi_arlen_o(m_axi_qsu_arlen_o),.m_axi_arsize_o(m_axi_qsu_arsize_o),.m_axi_arburst_o(m_axi_qsu_arburst_o),.m_axi_arvalid_o(m_axi_qsu_arvalid_o),.m_axi_arready_i(m_axi_qsu_arready_i),
    .m_axi_rid_i(m_axi_qsu_rid_i),.m_axi_rdata_i(m_axi_qsu_rdata_i),.m_axi_rresp_i(m_axi_qsu_rresp_i),.m_axi_rlast_i(m_axi_qsu_rlast_i),.m_axi_rvalid_i(m_axi_qsu_rvalid_i),.m_axi_rready_o(m_axi_qsu_rready_o),
    .m_axi_awid_o(m_axi_qsu_awid_o),.m_axi_awaddr_o(m_axi_qsu_awaddr_o),.m_axi_awlen_o(m_axi_qsu_awlen_o),.m_axi_awsize_o(m_axi_qsu_awsize_o),.m_axi_awburst_o(m_axi_qsu_awburst_o),.m_axi_awvalid_o(m_axi_qsu_awvalid_o),.m_axi_awready_i(m_axi_qsu_awready_i),
    .m_axi_wdata_o(m_axi_qsu_wdata_o),.m_axi_wstrb_o(m_axi_qsu_wstrb_o),.m_axi_wlast_o(m_axi_qsu_wlast_o),.m_axi_wvalid_o(m_axi_qsu_wvalid_o),.m_axi_wready_i(m_axi_qsu_wready_i),
    .m_axi_bid_i(m_axi_qsu_bid_i),.m_axi_bresp_i(m_axi_qsu_bresp_i),.m_axi_bvalid_i(m_axi_qsu_bvalid_i),.m_axi_bready_o(m_axi_qsu_bready_o));
  task automatic write_one(input integer offset,input logic bank,input integer data);
    begin @(negedge clk_i);wr_valid=1;wr_offset=offset;wr_bank=bank;wr_data=128'(data);
      @(posedge clk_i);while(!wr_ready)@(posedge clk_i);@(negedge clk_i);wr_valid=0;
    end
  endtask
  task automatic read_start(input integer offset,input integer count,input logic bank);
    begin @(negedge clk_i);rd_valid=1;rd_offset=offset;rd_count=count;rd_bank=bank;
      @(posedge clk_i);while(!rd_ready)@(posedge clk_i);@(negedge clk_i);rd_valid=0;
    end
  endtask
  task automatic clear_error;
    begin wait(!rd_busy&&!wr_busy);@(negedge clk_i);clear=1;@(negedge clk_i);clear=0;end
  endtask
  always @(negedge clk_i)r_ready=qsu_tick%29<16;
  always @(posedge clk_i)if(rst_ni)begin
    if(r_valid&&r_ready&&check_data)begin
      if(r_data!=128'(240+got)||r_last!=(got==119))$fatal(1,"DMA data/order/last mismatch %0d",got);
      got<=got+1;
    end
    if(qsu_tick>20000)$fatal(1,"DMA timeout");
  end
  initial begin
    repeat(4)@(negedge clk_i);rst_ni=1;
    for(integer j=240;j<360;j=j+1)write_one(j,1,j);
    wait(!wr_busy);if(error)$fatal(1,"normal write error");
    check_data=1;read_start(240,120,1);wait(!rd_busy);@(negedge clk_i);check_data=0;
    if(error||got!=120)$fatal(1,"normal read error/count");
    // RRESP fault: drain the outstanding burst, never deadlock on backpressure.
    m_axi_qsu_rresp_i=2;read_start(240,40,1);wait(!rd_busy);@(negedge clk_i);
    if(status!=1)$fatal(1,"RRESP error not detected");m_axi_qsu_rresp_i=0;clear_error();
    // Wrong read ID follows the same protocol drain contract.
    m_axi_qsu_rid_i=1;read_start(240,40,1);wait(!rd_busy);@(negedge clk_i);
    if(status!=1)$fatal(1,"RID error not detected");m_axi_qsu_rid_i=0;clear_error();
    m_axi_qsu_bresp_i=2;write_one(10,0,77);wait(!wr_busy);@(negedge clk_i);
    if(status!=1)$fatal(1,"BRESP error not detected");m_axi_qsu_bresp_i=0;clear_error();
    base=64'h10000001;write_one(10,0,77);@(negedge clk_i);
    if(status!=2||wr_busy)$fatal(1,"alignment error not rejected");base=64'h10000000;clear_error();
    read_start(500,13,0);@(negedge clk_i);if(status!=2||rd_busy)$fatal(1,"range error not rejected");clear_error();
    got=0;check_data=1;read_start(240,120,1);wait(!rd_busy);@(negedge clk_i);
    if(error||got!=120||qsu_b_get!=qsu_aw_put||qsu_b_get!=qsu_w_put)$fatal(1,"recovery/drain error");
    $display("PASS T06 scratch DMA: independent AW/W, bank stride, 4KiB, backpressure, RRESP/RID/BRESP, alignment/range, recovery");$finish;
  end
endmodule
