`timescale 1ns/1ps
module tb_axi4_pixel_state_multiwrite_buffer;
  localparam DEPTH=4;logic clk_i=0,rst_ni=0,clear_error_i=0;logic[63:0]base_addr_i=64'h100000;
  logic s_valid_i=0,s_ready_o;logic[31:0]s_pixel_id_i,s_gid_i;logic[15:0]s_epoch_id_i;
  logic[12:0]s_alpha_q12_i;logic s_pass_alpha_i;logic[12:0]s_r_q12_i,s_g_q12_i,s_b_q12_i;
  logic[15:0]s_t_q16_i;logic s_newly_terminated_i;logic[31:0]hazard_pixel_id_i;logic hazard_o;
  logic[31:0]lookup_pixel_id_i;logic lookup_hit_o;logic[127:0]lookup_data_o;
  logic busy_o,error_sticky_o;logic[1:0]error_status_o;logic[2:0]occupancy_o,outstanding_o,peak_outstanding_o;
  logic[1:0]m_axi_awid_o,m_axi_bid_i=0;logic[63:0]m_axi_awaddr_o;logic[7:0]m_axi_awlen_o;
  logic[2:0]m_axi_awsize_o;logic[1:0]m_axi_awburst_o;logic m_axi_awvalid_o,m_axi_awready_i=0;
  logic[127:0]m_axi_wdata_o;logic[15:0]m_axi_wstrb_o;logic m_axi_wlast_o,m_axi_wvalid_o,m_axi_wready_i=0;
  logic[1:0]m_axi_bresp_i=0;logic m_axi_bvalid_i=0,m_axi_bready_o;
  logic[63:0]aw_fifo[0:15];logic[127:0]w_fifo[0:15];integer aw_put=0,w_put=0,b_sent=0;
  always#5 clk_i=~clk_i;
  axi4_pixel_state_multiwrite_buffer #(.DEPTH(DEPTH))dut(.*);
  always@(posedge clk_i)begin
    if(m_axi_awvalid_o&&m_axi_awready_i)begin aw_fifo[aw_put]<=m_axi_awaddr_o;aw_put<=aw_put+1;end
    if(m_axi_wvalid_o&&m_axi_wready_i)begin w_fifo[w_put]<=m_axi_wdata_o;w_put<=w_put+1;end
    if(m_axi_bvalid_i&&m_axi_bready_o)begin m_axi_bvalid_i<=0;b_sent<=b_sent+1;end
  end
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic submit(input[31:0]pixel,input[12:0]r);begin
    while(!s_ready_o)tick();s_pixel_id_i=pixel;s_gid_i=pixel+100;s_epoch_id_i=9;
    s_alpha_q12_i=r+1;s_pass_alpha_i=1;s_r_q12_i=r;s_g_q12_i=r+1;s_b_q12_i=r+2;
    s_t_q16_i=16'hf000-r;s_newly_terminated_i=r[0];s_valid_i=1;tick();s_valid_i=0;
  end endtask
  task automatic respond(input[1:0]resp,input[1:0]id);begin
    while(!m_axi_bready_o)tick();m_axi_bresp_i=resp;m_axi_bid_i=id;m_axi_bvalid_i=1;tick();
    m_axi_bresp_i=0;m_axi_bid_i=0;
  end endtask
  initial begin integer timeout;
    repeat(2)tick();rst_ni=1;tick();
    // Fill while both channels are blocked; full-tag hazards cover all queued entries.
    submit(3,10);submit(4,20);submit(3,30);submit(6,40);
    if(occupancy_o!=4||outstanding_o!=0||s_ready_o)$fatal(1,"input FIFO did not fill");
    hazard_pixel_id_i=3;#1;if(!hazard_o)$fatal(1,"queued same-pixel hazard missing");
    lookup_pixel_id_i=3;#1;
    if(!lookup_hit_o||lookup_data_o[12:0]!==30)$fatal(1,"youngest queued state was not forwarded");
    lookup_pixel_id_i=5;#1;if(lookup_hit_o)$fatal(1,"false lookup hit");
    hazard_pixel_id_i=5;#1;if(hazard_o)$fatal(1,"false hazard");
    // Exercise independent AW/W backpressure: addresses run first, then data.
    m_axi_awready_i=1;repeat(3)tick();m_axi_wready_i=1;
    timeout=0;while(outstanding_o!=4&&timeout<30)begin
      if(timeout==2)m_axi_awready_i=0;if(timeout==4)m_axi_awready_i=1;
      if(timeout==5)m_axi_wready_i=0;if(timeout==7)m_axi_wready_i=1;
      tick();timeout=timeout+1;
    end
    if(timeout>=30||peak_outstanding_o!=4||aw_put!=4||w_put!=4)$fatal(1,"multi issue failed");
    if(aw_fifo[0]!==64'h100030||aw_fifo[1]!==64'h100040||aw_fifo[2]!==64'h100030||aw_fifo[3]!==64'h100060)
      $fatal(1,"AW order/address mismatch");
    if(w_fifo[0][12:0]!==10||w_fifo[1][12:0]!==20||w_fifo[2][12:0]!==30||w_fifo[3][12:0]!==40)
      $fatal(1,"W order/data mismatch");
    // Hazard remains until each corresponding ordered B response retires.
    // Full-ring B retirement and replacement use the same physical slot.
    m_axi_bresp_i=0;m_axi_bid_i=0;m_axi_bvalid_i=1;
    while(!s_ready_o)tick();s_pixel_id_i=7;s_gid_i=107;s_epoch_id_i=9;s_alpha_q12_i=51;
    s_pass_alpha_i=1;s_r_q12_i=50;s_g_q12_i=51;s_b_q12_i=52;s_t_q16_i=16'hefce;
    s_newly_terminated_i=0;s_valid_i=1;tick();s_valid_i=0;m_axi_bvalid_i=0;
    if(occupancy_o!=4||!dut.valid_q[0])$fatal(1,"same-slot retire/refill lost replacement");
    hazard_pixel_id_i=7;#1;if(!hazard_o)$fatal(1,"replacement hazard missing");
    hazard_pixel_id_i=3;#1;if(!hazard_o)$fatal(1,"newer same-pixel hazard cleared early");
    lookup_pixel_id_i=3;#1;if(!lookup_hit_o||lookup_data_o[12:0]!==30)$fatal(1,"newest state changed before retirement");
    respond(0,0);#1;if(!hazard_o)$fatal(1,"second pixel3 write cleared early");
    if(!lookup_hit_o||lookup_data_o[12:0]!==30)$fatal(1,"newer matching state did not survive older B");
    respond(2'b10,0);#1;if(hazard_o)$fatal(1,"retired same-pixel hazard remained");
    respond(0,0);
    timeout=0;while(outstanding_o!=1&&timeout<20)begin tick();timeout=timeout+1;end
    if(timeout>=20)$fatal(1,"replacement was not issued");
    respond(0,0);tick();if(busy_o||occupancy_o!=0||outstanding_o!=0)$fatal(1,"drain failed");
    if(!error_sticky_o||!error_status_o[0])$fatal(1,"BRESP error not sticky");
    clear_error_i=1;tick();clear_error_i=0;if(error_sticky_o||peak_outstanding_o!=0)$fatal(1,"clear failed");
    // Misalignment is consumed as a deterministic configuration error without AXI traffic.
    base_addr_i=64'h100008;submit(9,50);tick();
    if(!error_status_o[1]||busy_o||aw_put!=5||w_put!=5)$fatal(1,"config error handling failed");
    $display("PASS: tb_axi4_pixel_state_multiwrite_buffer");$finish;
  end
endmodule
