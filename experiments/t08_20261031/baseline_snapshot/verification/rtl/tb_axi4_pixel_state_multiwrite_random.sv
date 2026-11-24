`timescale 1ns/1ps
module tb_axi4_pixel_state_multiwrite_random;
  localparam DEPTH=8,N=96;logic clk_i=0,rst_ni=0,clear_error_i=0;logic[63:0]base_addr_i=64'h200000;
  logic s_valid_i=0,s_ready_o;logic[31:0]s_pixel_id_i,s_gid_i;logic[15:0]s_epoch_id_i;
  logic[12:0]s_alpha_q12_i;logic s_pass_alpha_i;logic[12:0]s_r_q12_i,s_g_q12_i,s_b_q12_i;
  logic[15:0]s_t_q16_i;logic s_newly_terminated_i;logic[31:0]hazard_pixel_id_i=0;logic hazard_o;
  logic[31:0]lookup_pixel_id_i=0;logic lookup_hit_o;logic[127:0]lookup_data_o;
  logic busy_o,error_sticky_o;logic[1:0]error_status_o;logic[3:0]occupancy_o,outstanding_o,peak_outstanding_o;
  logic[1:0]m_axi_awid_o,m_axi_bid_i=0;logic[63:0]m_axi_awaddr_o;logic[7:0]m_axi_awlen_o;
  logic[2:0]m_axi_awsize_o;logic[1:0]m_axi_awburst_o;logic m_axi_awvalid_o,m_axi_awready_i=0;
  logic[127:0]m_axi_wdata_o;logic[15:0]m_axi_wstrb_o;logic m_axi_wlast_o,m_axi_wvalid_o,m_axi_wready_i=0;
  logic[1:0]m_axi_bresp_i=0;logic m_axi_bvalid_i=0,m_axi_bready_o;
  logic[63:0]expected_addr[0:N-1],seen_addr[0:N-1];logic[127:0]expected_data[0:N-1],seen_data[0:N-1];
  integer submitted=0,aw_seen=0,w_seen=0,b_seen=0,cycles=0;logic[31:0]lfsr=32'h6d2b79f5;
  always#5 clk_i=~clk_i;
  axi4_pixel_state_multiwrite_buffer #(.DEPTH(DEPTH))dut(.*);
  always@(posedge clk_i)begin
    if(!rst_ni)begin
      m_axi_awready_i<=0;m_axi_wready_i<=0;m_axi_bvalid_i<=0;lfsr<=32'h6d2b79f5;
      aw_seen<=0;w_seen<=0;b_seen<=0;cycles<=0;
    end else begin
      cycles<=cycles+1;lfsr<={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
      m_axi_awready_i<=lfsr[0]||lfsr[3];m_axi_wready_i<=lfsr[1]||lfsr[5];
      if(m_axi_awvalid_o&&m_axi_awready_i)begin seen_addr[aw_seen]<=m_axi_awaddr_o;aw_seen<=aw_seen+1;end
      if(m_axi_wvalid_o&&m_axi_wready_i)begin seen_data[w_seen]<=m_axi_wdata_o;w_seen<=w_seen+1;end
      // Exercise legal back-to-back ordered B responses as well as gaps.
      if(m_axi_bvalid_i&&m_axi_bready_o)begin
        b_seen<=b_seen+1;
        if(b_seen+1<aw_seen&&b_seen+1<w_seen&&(lfsr[2]||lfsr[7]))m_axi_bvalid_i<=1;
        else m_axi_bvalid_i<=0;
      end
      else if(!m_axi_bvalid_i&&b_seen<aw_seen&&b_seen<w_seen&&(lfsr[2]||lfsr[7]))m_axi_bvalid_i<=1;
    end
  end
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic submit(input integer n);logic[127:0]payload;logic[31:0]pixel;begin
    pixel=(n*13)%23;while(!s_ready_o)tick();
    s_pixel_id_i=pixel;s_gid_i=n+1000;s_epoch_id_i=16'h1200+n;s_alpha_q12_i=n+1;
    s_pass_alpha_i=n[0];s_r_q12_i=n;s_g_q12_i=n+1;s_b_q12_i=n+2;
    s_t_q16_i=16'he000-n;s_newly_terminated_i=n[1];
    payload='0;payload[12:0]=n;payload[25:13]=n+1;payload[38:26]=n+2;payload[54:39]=16'he000-n;
    payload[70:55]=16'h1200+n;payload[83:71]=n+1;payload[84]=n[0];payload[85]=n[1];payload[117:86]=n+1000;
    expected_addr[n]=64'h200000+(pixel<<4);expected_data[n]=payload;
    s_valid_i=1;tick();s_valid_i=0;submitted=submitted+1;
  end endtask
  initial begin integer i,timeout;
    repeat(3)tick();rst_ni=1;tick();
    // An unsolicited response is a protocol error and must not be consumed.
    m_axi_bvalid_i=1;tick();if(m_axi_bready_o||!error_status_o[0])$fatal(1,"unsolicited B not detected");
    m_axi_bvalid_i=0;clear_error_i=1;tick();clear_error_i=0;
    for(i=0;i<N;i=i+1)submit(i);
    timeout=0;while((busy_o||b_seen<N)&&timeout<10000)begin tick();timeout=timeout+1;end
    if(timeout>=10000||submitted!=N||aw_seen!=N||w_seen!=N||b_seen!=N||error_sticky_o)
      $fatal(1,"random drain/count failure sub=%0d aw=%0d w=%0d b=%0d",submitted,aw_seen,w_seen,b_seen);
    if(peak_outstanding_o<2)$fatal(1,"random test never formed multiple outstanding writes");
    for(i=0;i<N;i=i+1)begin
      if(seen_addr[i]!==expected_addr[i])$fatal(1,"random AW mismatch %0d",i);
      if(seen_data[i]!==expected_data[i])$fatal(1,"random W mismatch %0d",i);
    end
    $display("PASS: tb_axi4_pixel_state_multiwrite_random peak=%0d cycles=%0d",peak_outstanding_o,cycles);
    $finish;
  end
endmodule
