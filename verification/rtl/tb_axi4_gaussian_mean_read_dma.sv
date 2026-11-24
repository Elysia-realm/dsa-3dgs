`timescale 1ns/1ps
module tb_axi4_gaussian_mean_read_dma;
    logic clk_i=0,rst_ni=0,start_i=0,clear_error_i=0;
    logic[63:0]base_addr_i;logic[31:0]gaussian_count_i;
    logic busy_o,done_pulse_o,error_sticky_o;logic[1:0]error_status_o;
    logic m_valid_o,m_ready_i=1,m_last_o,end_valid_o,end_ready_i=1;
    logic[31:0]m_gid_o;logic signed[26:0]m_world_x_q16_o,m_world_y_q16_o,m_world_z_q16_o;
    logic[1:0]m_axi_arid_o,m_axi_rid_i=0;logic[63:0]m_axi_araddr_o;
    logic[7:0]m_axi_arlen_o;logic[2:0]m_axi_arsize_o;logic[1:0]m_axi_arburst_o;
    logic m_axi_arvalid_o,m_axi_arready_i=0,m_axi_rlast_i,m_axi_rvalid_i=0,m_axi_rready_o;
    logic[127:0]m_axi_rdata_i;logic[1:0]m_axi_rresp_i=0;
    integer received;

    always #5 clk_i=~clk_i;
    axi4_gaussian_mean_read_dma dut(.*);
    task automatic tick;begin @(posedge clk_i);#1;end endtask
    task automatic launch(input[63:0]addr,input[31:0]count);begin
      base_addr_i=addr;gaussian_count_i=count;start_i=1;tick();start_i=0;
    end endtask
    task automatic accept_ar(input[63:0]addr,input[7:0]len);begin
      while(!m_axi_arvalid_o)tick();
      if(m_axi_araddr_o!==addr||m_axi_arlen_o!==len||m_axi_arsize_o!==3'd4||m_axi_arburst_o!==2'b01)
        $fatal(1,"AR mismatch addr=%h len=%0d",m_axi_araddr_o,m_axi_arlen_o);
      m_axi_arready_i=1;tick();m_axi_arready_i=0;
    end endtask
    task automatic send_r(input[31:0]gid,input last,input[1:0]resp);begin
      @(negedge clk_i);
      m_axi_rdata_i='0;m_axi_rdata_i[31:0]=gid;
      m_axi_rdata_i[58:32]=$signed(gid+100);m_axi_rdata_i[85:59]=-$signed(gid+20);
      m_axi_rdata_i[112:86]=$signed(gid+300);
      m_axi_rlast_i=last;m_axi_rresp_i=resp;
      m_axi_rvalid_i=1;
      do @(posedge clk_i); while(!m_axi_rready_o);
      #1;m_axi_rvalid_i=0;m_axi_rresp_i=0;
    end endtask
    always@(posedge clk_i)if(rst_ni&&m_valid_o&&m_ready_i)begin
      if(m_gid_o!==received)$fatal(1,"GID/order mismatch got=%0d exp=%0d",m_gid_o,received);
      if(m_world_x_q16_o!==received+100||m_world_y_q16_o!==-(received+20)||m_world_z_q16_o!==received+300)
        $fatal(1,"record decode mismatch");
      if(m_last_o!==(received==19))$fatal(1,"stream last mismatch at %0d",received);
      received=received+1;
    end
    initial begin
      base_addr_i=0;gaussian_count_i=0;m_axi_rlast_i=0;m_axi_rdata_i=0;received=0;
      repeat(2)tick();rst_ni=1;tick();

      // 20 records at 0xFF0: first burst is shortened to one beat at 4-KiB,
      // followed by the configured 16-beat maximum and a final 3-beat burst.
      launch(64'hff0,20);accept_ar(64'hff0,0);
      send_r(0,1,0);
      accept_ar(64'h1000,15);
      fork
        begin integer i;for(i=1;i<=16;i=i+1)send_r(i,i==16,0);end
        begin
          while(!m_valid_o)tick();m_ready_i=0;
          repeat(3)begin
            tick();if(!m_valid_o||m_gid_o!==1)$fatal(1,"output changed under backpressure");
          end
          m_ready_i=1;
        end
      join
      accept_ar(64'h1100,2);
      send_r(17,0,0);send_r(18,0,0);send_r(19,1,0);
      while(!done_pulse_o)tick();
      if(received!=20||error_sticky_o||busy_o)$fatal(1,"normal DMA completion mismatch");

      // Empty input ends by handshake without fabricating a record.
      launch(64'h2000,0);if(!end_valid_o)tick();
      if(!end_valid_o||m_valid_o)$fatal(1,"empty frame termination mismatch");
      tick();if(!done_pulse_o||error_sticky_o)$fatal(1,"empty completion mismatch");

      // Misalignment is a configuration error and issues no AXI request.
      launch(64'h2008,1);if(!end_valid_o)tick();
      if(error_status_o!==2'b10||m_axi_arvalid_o)$fatal(1,"alignment error mismatch");
      tick();

      // AXI SLVERR is reported; remaining responses are drained through RLAST.
      launch(64'h3000,3);accept_ar(64'h3000,2);
      send_r(0,0,2'b10);
      if(!error_sticky_o||end_valid_o)$fatal(1,"AXI error/drain state mismatch");
      send_r(99,0,0);send_r(99,1,0);
      if(!end_valid_o)tick();
      if(error_status_o!==2'b01)$fatal(1,"AXI error status mismatch");
      tick();

      // Early RLAST is a protocol error and can terminate immediately.
      launch(64'h4000,2);accept_ar(64'h4000,1);send_r(0,1,0);
      if(!end_valid_o)tick();if(error_status_o!==2'b01)$fatal(1,"RLAST error missing");tick();

      // A response with the wrong ID is rejected before reaching the stream.
      launch(64'h5000,1);accept_ar(64'h5000,0);m_axi_rid_i=1;send_r(0,1,0);m_axi_rid_i=0;
      if(!end_valid_o)tick();if(error_status_o!==2'b01)$fatal(1,"RID error missing");tick();

      // Missing RLAST on the final expected beat is also a protocol error;
      // recovery requires no unbounded wait for a malformed slave.
      launch(64'h6000,1);accept_ar(64'h6000,0);send_r(0,0,0);
      if(!end_valid_o)tick();if(error_status_o!==2'b01)$fatal(1,"late RLAST error missing");tick();
      $display("PASS: tb_axi4_gaussian_mean_read_dma");$finish;
    end
endmodule
