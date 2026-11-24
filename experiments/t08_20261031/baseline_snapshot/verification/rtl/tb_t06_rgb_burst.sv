`timescale 1ns/1ps
`ifndef TB_RGB_BURST
`define TB_RGB_BURST 16
`endif
module tb_t06_rgb_burst;
  logic clk_i=0,rst_ni=0,start_i=0,clear_error_i=0;always #5 clk_i=~clk_i;
  logic[63:0]state_base_addr_i=64'h01001ff0,rgb_base_addr_i=64'h70000f20;
  logic[15:0]width_i=83,height_i=2,epoch_id_i=16'h1234;
  logic busy_o,done_pulse_o,error_sticky_o;logic[2:0]error_status_o;logic[31:0]row_stride_bytes_o;
  logic[1:0]m_axi_arid_o,m_axi_rid_i;logic[63:0]m_axi_araddr_o;logic[7:0]m_axi_arlen_o;
  logic[2:0]m_axi_arsize_o;logic[1:0]m_axi_arburst_o;logic m_axi_arvalid_o,m_axi_arready_i;
  logic[127:0]m_axi_rdata_i;logic[1:0]m_axi_rresp_i;logic m_axi_rlast_i,m_axi_rvalid_i,m_axi_rready_o;
  logic[1:0]m_axi_awid_o,m_axi_bid_i;logic[63:0]m_axi_awaddr_o;logic[7:0]m_axi_awlen_o;
  logic[2:0]m_axi_awsize_o;logic[1:0]m_axi_awburst_o;logic m_axi_awvalid_o,m_axi_awready_i;
  logic[127:0]m_axi_wdata_o;logic[15:0]m_axi_wstrb_o;logic m_axi_wlast_o,m_axi_wvalid_o,m_axi_wready_i;
  logic[1:0]m_axi_bresp_i;logic m_axi_bvalid_i,m_axi_bready_o;
  integer cycle=0,rd_left=0,rd_index=0,rd_delay=0,wr_left=0,wr_byte=0,b_delay=0;
  integer ar_count=0,read_count=0,aw_count=0,write_count=0,b_count=0,fault=0,profile=0;
  logic b_pending=0;logic[1:0]rd_id=0,wr_id=0;
  axi4_final_rgb_frame_dma #(.READ_BURST_BEATS(`TB_RGB_BURST),.BG_R_Q12(4096),.BG_G_Q12(2048))dut(.*);
  function automatic [127:0]state_word(input integer i);
    logic[127:0]v;
    begin
      v=0;v[70:55]=(i%17==0)?16'h1233:16'h1234;
      v[54:39]=(i%19==0)?16'hffff:((i%23==0)?16'd32768:16'd0);
      if(i%19!=0)begin v[12:0]=(i%5)*1024;v[25:13]=((i/5)%5)*1024;v[38:26]=((i/25)%5)*1024;end
      state_word=v;
    end
  endfunction
  function automatic [7:0]expected_byte(input integer offset);
    integer stride,row,col,pixel,ch,color,bg,t,value;
    begin
      stride=((width_i*3+15)/16)*16;row=offset/stride;col=offset%stride;
      if(col>=width_i*3)expected_byte=0;
      else begin
        pixel=row*width_i+col/3;ch=col%3;bg=ch==0?4096:(ch==1?2048:0);
        color=(ch==0?pixel%5:(ch==1?(pixel/5)%5:(pixel/25)%5))*1024;
        if(pixel%17==0)value=bg;
        else if(pixel%19==0)value=bg;
        else begin t=pixel%23==0?32768:0;value=color+(t*bg+32768)/65536;end
        if(value>4096)value=4096;expected_byte=(value*255+2048)/4096;
      end
    end
  endfunction
  assign m_axi_arready_i=rd_left==0&&(!profile||cycle%3!=0);
  assign m_axi_rvalid_i=rd_left>0&&rd_delay==0;assign m_axi_rdata_i=state_word(rd_index);
  assign m_axi_rlast_i=rd_left==1;assign m_axi_rid_i=(fault==2&&read_count==2)?rd_id^2'b01:rd_id;
  assign m_axi_rresp_i=(fault==1&&read_count==2)?2'b10:2'b00;
  assign m_axi_awready_i=wr_left==0&&!b_pending&&(!profile||cycle%4!=0);
  assign m_axi_wready_i=!profile||cycle%5!=0;
  assign m_axi_bvalid_i=b_pending&&b_delay==0;assign m_axi_bid_i=fault==6?wr_id^2'b01:wr_id;
  assign m_axi_bresp_i=fault==5?2'b10:2'b00;
  always@(posedge clk_i)if(rst_ni)begin
    cycle<=cycle+1;if(rd_delay>0)rd_delay<=rd_delay-1;if(b_delay>0)b_delay<=b_delay-1;
    if(m_axi_arvalid_o&&m_axi_arready_i)begin
      if(m_axi_araddr_o<state_base_addr_i||m_axi_araddr_o+(m_axi_arlen_o+1)*16>state_base_addr_i+64'(width_i)*height_i*16||
         m_axi_araddr_o[3:0]!=0||m_axi_arsize_o!=4||m_axi_arburst_o!=1||m_axi_arlen_o>=`TB_RGB_BURST||
         {1'b0,m_axi_araddr_o[11:0]}+(m_axi_arlen_o+1)*16>4096)$fatal(1,"read burst bounds/alignment");
      rd_index<=(m_axi_araddr_o-state_base_addr_i)/16;rd_id<=m_axi_arid_o;
      rd_left<=(fault==3&&ar_count==1)?1:(m_axi_arlen_o+1+((fault==4&&ar_count==0)?1:0));
      rd_delay<=profile?2:0;ar_count<=ar_count+1;
    end
    if(m_axi_rvalid_i&&m_axi_rready_o)begin rd_index<=rd_index+1;rd_left<=rd_left-1;rd_delay<=profile?cycle%3:0;read_count<=read_count+1;end
    if(m_axi_awvalid_o&&m_axi_awready_i)begin
      if(m_axi_awaddr_o[3:0]!=0||m_axi_awsize_o!=4||m_axi_awburst_o!=1||
         {1'b0,m_axi_awaddr_o[11:0]}+(m_axi_awlen_o+1)*16>4096)$fatal(1,"write burst bounds/alignment");
      wr_left<=m_axi_awlen_o+1;wr_byte<=m_axi_awaddr_o-rgb_base_addr_i;wr_id<=m_axi_awid_o;aw_count<=aw_count+1;
    end
    if(m_axi_wvalid_o&&m_axi_wready_i)begin
      if(wr_left<=0||m_axi_wlast_o!=(wr_left==1)||m_axi_wstrb_o!=16'hffff)$fatal(1,"invalid W packet");
      for(integer lane=0;lane<16;lane=lane+1)begin
        if(wr_byte+lane>=row_stride_bytes_o*height_i)$fatal(1,"write outside frame");
        if(fault==0&&m_axi_wdata_o[lane*8+:8]!==expected_byte(wr_byte+lane))$fatal(1,"RGB byte mismatch offset=%0d got=%0d expected=%0d",wr_byte+lane,m_axi_wdata_o[lane*8+:8],expected_byte(wr_byte+lane));
      end
      wr_byte<=wr_byte+16;wr_left<=wr_left-1;write_count<=write_count+1;
      if(wr_left==1)begin b_pending<=1;b_delay<=profile?4:0;end
    end
    if(m_axi_bvalid_i&&m_axi_bready_o)begin b_pending<=0;b_count<=b_count+1;end
  end
  task automatic tick;begin @(posedge clk_i);#1;end endtask
  task automatic launch_and_check(input integer f);
    integer timeout,begin_cycle;logic[2:0]expected_error;
    begin
      @(negedge clk_i);fault=f;ar_count=0;read_count=0;aw_count=0;write_count=0;b_count=0;
      clear_error_i=1;tick();@(negedge clk_i);clear_error_i=0;start_i=1;begin_cycle=cycle;
      tick();@(negedge clk_i);start_i=0;timeout=0;
      while(!done_pulse_o&&timeout<20000000)begin tick();timeout=timeout+1;end
      if(timeout==20000000||busy_o||rd_left!=0||wr_left!=0||b_pending||aw_count!=b_count)$fatal(1,"completion before drain");
      expected_error=(f>=1&&f<=4)?3'b010:((f==5||f==6)?3'b100:((f==7)?3'b001:0));
      if(error_status_o!==expected_error)$fatal(1,"error status got=%b expected=%b fault=%0d",error_status_o,expected_error,f);
      if(f==0&&(read_count!=width_i*height_i||write_count*16!=row_stride_bytes_o*height_i))$fatal(1,"data loss/duplication");
      $display("PASS RGB_BURST burst=%0d width=%0d height=%0d profile=%0d fault=%0d cycles=%0d reads=%0d AR=%0d writes=%0d AW=%0d",`TB_RGB_BURST,width_i,height_i,profile,f,cycle-begin_cycle,read_count,ar_count,write_count,aw_count);
      tick();
    end
  endtask
  initial begin
    integer w,h,f;
    w=83;h=2;f=0;if($value$plusargs("WIDTH=%d",w))begin end;if($value$plusargs("HEIGHT=%d",h))begin end;
    if($value$plusargs("PROFILE=%d",profile))begin end;if($value$plusargs("FAULT=%d",f))begin end;
    width_i=16'(w);height_i=16'(h);repeat(3)tick();rst_ni=1;tick();
    if(state_base_addr_i+64'(width_i)*height_i*16>rgb_base_addr_i)$fatal(1,"overlapping unit-test regions");
    if(f==7)rgb_base_addr_i=64'h70000f21;
    launch_and_check(f);
    if(f!=0)begin rgb_base_addr_i=64'h70000f20;launch_and_check(0);end
    $finish;
  end
endmodule
