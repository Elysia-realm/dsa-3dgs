`timescale 1ns/1ps
module tb_axi4_final_rgb_frame_dma;
  localparam int W=83,H=2;localparam logic[63:0]BASE=64'h0000_0000_0000_0f20;
  localparam logic[63:0]STATE_BASE=64'h0000_0000_0000_2000;
  logic clk_i=0,rst_ni=0,start_i=0,clear_error_i=0;always #5 clk_i=~clk_i;
  logic[63:0]state_base_addr_i=STATE_BASE,rgb_base_addr_i=BASE;
  logic[15:0]width_i=W,height_i=H,epoch_id_i=16'h1234;
  logic busy_o,done_pulse_o,error_sticky_o;logic[2:0]error_status_o;logic[31:0]row_stride_bytes_o;
  logic[1:0]m_axi_arid_o,m_axi_rid_i=0;logic[63:0]m_axi_araddr_o;logic[7:0]m_axi_arlen_o;
  logic[2:0]m_axi_arsize_o;logic[1:0]m_axi_arburst_o;logic m_axi_arvalid_o,m_axi_arready_i=0;
  logic[127:0]m_axi_rdata_i=0;logic[1:0]m_axi_rresp_i=0;logic m_axi_rlast_i=1,m_axi_rvalid_i=0,m_axi_rready_o;
  logic[1:0]m_axi_awid_o,m_axi_bid_i=0;logic[63:0]m_axi_awaddr_o;logic[7:0]m_axi_awlen_o;
  logic[2:0]m_axi_awsize_o;logic[1:0]m_axi_awburst_o;logic m_axi_awvalid_o,m_axi_awready_i=0;
  logic[127:0]m_axi_wdata_o;logic[15:0]m_axi_wstrb_o;logic m_axi_wlast_o,m_axi_wvalid_o,m_axi_wready_i=0;
  logic[1:0]m_axi_bresp_i=0;logic m_axi_bvalid_i=0,m_axi_bready_o;
  logic[127:0]state_mem[0:W*H-1];logic[7:0]rgb_mem[0:511];
  integer cycle=0,b_delay=0,write_byte=0,burst_left=0,aw_count=0,i,timeout;
  logic[63:0]write_addr_q;
  logic inject_read_error=0,inject_write_error=0;

  always_comb begin
    m_axi_arready_i=(cycle%3)!=0;
    m_axi_awready_i=(cycle%4)!=0;
    m_axi_wready_i=(cycle%5)!=0;
  end

  axi4_final_rgb_frame_dma #(.BG_R_Q12(13'd4096),.BG_G_Q12(13'd2048),.BG_B_Q12(13'd0))dut(.*);

  task tick;begin @(posedge clk_i);#1;end endtask
  always_ff@(posedge clk_i)begin
    if(rst_ni)begin
      cycle<=cycle+1;b_delay<=b_delay+1;
      if(m_axi_arvalid_o&&m_axi_arready_i)begin
        m_axi_rdata_i<=state_mem[(m_axi_araddr_o-STATE_BASE)>>4];m_axi_rid_i<=m_axi_arid_o;
        m_axi_rresp_i<=inject_read_error?2'b10:2'b00;m_axi_rvalid_i<=1;
      end
      if(m_axi_rvalid_i&&m_axi_rready_o)m_axi_rvalid_i<=0;
      if(m_axi_awvalid_o&&m_axi_awready_i)begin
        write_addr_q<=m_axi_awaddr_o;write_byte<=m_axi_awaddr_o-BASE;
        burst_left<=m_axi_awlen_o+1;aw_count<=aw_count+1;
        if(m_axi_awaddr_o[11:0]+((m_axi_awlen_o+1)<<4)>4096)$fatal(1,"burst crossed 4KiB");
      end
      if(m_axi_wvalid_o&&m_axi_wready_i)begin
        for(i=0;i<16;i=i+1)if(m_axi_wstrb_o[i])rgb_mem[write_byte+i]<=m_axi_wdata_o[i*8+:8];
        write_byte<=write_byte+16;burst_left<=burst_left-1;
        if((burst_left==1)!==m_axi_wlast_o)$fatal(1,"WLAST mismatch");
        if(burst_left==1)b_delay<=0;
      end
      if(!m_axi_bvalid_i&&burst_left==0&&aw_count>0&&b_delay>=3)begin
        m_axi_bvalid_i<=1;m_axi_bid_i<=0;m_axi_bresp_i<=inject_write_error?2'b10:2'b00;
      end
      if(m_axi_bvalid_i&&m_axi_bready_o)begin m_axi_bvalid_i<=0;m_axi_bresp_i<=0;aw_count<=aw_count-1;end
    end
  end

  initial begin
    for(i=0;i<W*H;i=i+1)begin
      state_mem[i]=0;state_mem[i][70:55]=16'h1234;state_mem[i][54:39]=0;
      state_mem[i][12:0]=(i%5)*13'd1024;state_mem[i][25:13]=13'd0;state_mem[i][38:26]=13'd4096;
    end
    // Stale epoch must emit the configured background.
    state_mem[1][70:55]=16'h1222;
    // Current-epoch zero color plus full T must also compose to background.
    state_mem[2][12:0]=0;state_mem[2][25:13]=0;state_mem[2][38:26]=0;state_mem[2][54:39]=16'hffff;
    for(i=0;i<512;i=i+1)rgb_mem[i]=8'haa;
    repeat(3)tick();rst_ni=1;tick();start_i=1;tick();start_i=0;
    timeout=0;while(!done_pulse_o&&timeout<10000)begin tick();timeout=timeout+1;end
    if(timeout>=10000)$fatal(1,"timeout");
    if(error_sticky_o||error_status_o!=0)$fatal(1,"unexpected error %b",error_status_o);
    if(row_stride_bytes_o!=256)$fatal(1,"stride %0d",row_stride_bytes_o);
    if({rgb_mem[0],rgb_mem[1],rgb_mem[2]}!==24'h0000ff)$fatal(1,"pixel0 byte order/composite mismatch");
    if({rgb_mem[3],rgb_mem[4],rgb_mem[5]}!==24'hff8000)$fatal(1,"stale epoch background mismatch");
    if({rgb_mem[6],rgb_mem[7],rgb_mem[8]}!==24'hff8000)$fatal(1,"full-T background mismatch");
    if(rgb_mem[249]!==0||rgb_mem[250]!==0||rgb_mem[255]!==0)$fatal(1,"row padding not zero");
    if({rgb_mem[256],rgb_mem[257],rgb_mem[258]}!==24'hbf00ff)$fatal(1,"row stride pixel mismatch");
    if(aw_count!=0)$fatal(1,"done before final B response");
    if(aw_count<0)$fatal(1,"response accounting underflow");
    clear_error_i=1;tick();clear_error_i=0;width_i=1;height_i=1;
    inject_read_error=1;inject_write_error=1;start_i=1;tick();start_i=0;
    timeout=0;while(!done_pulse_o&&timeout<1000)begin tick();timeout=timeout+1;end
    if(timeout>=1000||error_status_o!==3'b110)$fatal(1,"read/write error reporting mismatch %b",error_status_o);
    clear_error_i=1;tick();clear_error_i=0;rgb_base_addr_i=BASE+1;start_i=1;tick();start_i=0;
    timeout=0;while(!done_pulse_o&&timeout<20)begin tick();timeout=timeout+1;end
    if(timeout>=20||error_status_o!==3'b001)$fatal(1,"config error reporting mismatch %b",error_status_o);
    $display("PASS: tb_axi4_final_rgb_frame_dma stride=%0d",row_stride_bytes_o);$finish;
  end
endmodule
