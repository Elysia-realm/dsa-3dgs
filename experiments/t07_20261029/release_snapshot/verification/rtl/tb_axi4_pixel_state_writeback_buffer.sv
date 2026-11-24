`timescale 1ns/1ps
module tb_axi4_pixel_state_writeback_buffer;
  localparam DEPTH=2;logic clk_i=0,rst_ni=0,clear_error_i=0,flush_i=0;logic[63:0]base_addr_i=64'h100000;
  logic s_valid_i=0,s_ready_o;logic[31:0]s_pixel_id_i,s_gid_i;logic[15:0]s_epoch_id_i;
  logic[12:0]s_alpha_q12_i;logic s_pass_alpha_i;logic[12:0]s_r_q12_i,s_g_q12_i,s_b_q12_i;
  logic[15:0]s_t_q16_i;logic s_newly_terminated_i;logic[31:0]lookup_pixel_id_i;
  logic lookup_hit_o;logic[127:0]lookup_data_o;logic busy_o,flush_busy_o,error_sticky_o;logic[1:0]error_status_o;
  logic[$clog2(DEPTH+1)-1:0]occupancy_o;logic[63:0]coalesced_count_o;logic[1:0]m_axi_awid_o,m_axi_bid_i=0;
  logic[63:0]m_axi_awaddr_o;logic[7:0]m_axi_awlen_o;logic[2:0]m_axi_awsize_o;logic[1:0]m_axi_awburst_o;
  logic m_axi_awvalid_o,m_axi_awready_i=1;logic[127:0]m_axi_wdata_o;logic[15:0]m_axi_wstrb_o;
  logic m_axi_wlast_o,m_axi_wvalid_o,m_axi_wready_i=1;logic[1:0]m_axi_bresp_i=0;
  logic m_axi_bvalid_i=0,m_axi_bready_o;logic aw_seen=0,w_seen=0;logic[63:0]aw_q;logic[127:0]w_q;
  integer response_delay=-1,writes=0;logic[63:0]write_addr[0:7];logic[127:0]write_data[0:7];
  always#5 clk_i=~clk_i;
  axi4_pixel_state_writeback_buffer #(.DEPTH(DEPTH))dut(.*);
  always@(posedge clk_i)begin
    if(!rst_ni)begin aw_seen<=0;w_seen<=0;response_delay<=-1;m_axi_bvalid_i<=0;writes<=0;end
    else begin
      if(m_axi_awvalid_o&&m_axi_awready_i)begin aw_seen<=1;aw_q<=m_axi_awaddr_o;end
      if(m_axi_wvalid_o&&m_axi_wready_i)begin w_seen<=1;w_q<=m_axi_wdata_o;end
      if(response_delay<0&&(aw_seen||(m_axi_awvalid_o&&m_axi_awready_i))&&
          (w_seen||(m_axi_wvalid_o&&m_axi_wready_i)))begin
        write_addr[writes]<=aw_seen?aw_q:m_axi_awaddr_o;write_data[writes]<=w_seen?w_q:m_axi_wdata_o;
        writes<=writes+1;aw_seen<=0;w_seen<=0;response_delay<=3;
      end else if(response_delay>0)response_delay<=response_delay-1;
      else if(response_delay==0)begin m_axi_bvalid_i<=1;response_delay<=-1;end
      if(m_axi_bvalid_i&&m_axi_bready_o)m_axi_bvalid_i<=0;
    end
  end
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic submit(input[31:0]pixel,input[12:0]r);begin
    while(!s_ready_o)tick();s_pixel_id_i=pixel;s_gid_i=pixel+100;s_epoch_id_i=7;s_alpha_q12_i=r+1;
    s_pass_alpha_i=1;s_r_q12_i=r;s_g_q12_i=r+1;s_b_q12_i=r+2;s_t_q16_i=16'hf000-r;
    s_newly_terminated_i=r[0];s_valid_i=1;tick();s_valid_i=0;
  end endtask
  initial begin integer timeout;
    repeat(2)tick();rst_ni=1;tick();
    submit(3,10);submit(3,20);if(occupancy_o!=1||coalesced_count_o!=1)$fatal(1,"coalesce missing");
    lookup_pixel_id_i=3;#1;if(!lookup_hit_o||lookup_data_o[12:0]!=20||lookup_data_o[70:55]!=7)$fatal(1,"queued forward");
    submit(4,30);while(!dut.active_valid_q)tick();
    // Pixel 3 must remain forwardable while its delayed B response is pending.
    lookup_pixel_id_i=3;#1;if(!lookup_hit_o||lookup_data_o[12:0]!=20)$fatal(1,"active forward missing");
    submit(5,40);
    flush_i=1;tick();flush_i=0;timeout=0;while(busy_o&&timeout<200)begin tick();timeout=timeout+1;end
    if(timeout>=200||writes!=3||error_sticky_o)$fatal(1,"flush failure writes=%0d occ=%0d",writes,occupancy_o);
    if(write_addr[0]!==64'h100030||write_data[0][12:0]!==20||
       write_addr[1]!==64'h100040||write_data[1][12:0]!==30||
       write_addr[2]!==64'h100050||write_data[2][12:0]!==40)$fatal(1,"ordered final records mismatch");
    lookup_pixel_id_i=3;#1;if(lookup_hit_o)$fatal(1,"completed record remained forwardable");
    $display("PASS: tb_axi4_pixel_state_writeback_buffer");$finish;
  end
endmodule
