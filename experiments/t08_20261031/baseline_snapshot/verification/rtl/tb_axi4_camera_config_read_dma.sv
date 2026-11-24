`timescale 1ns/1ps
module tb_axi4_camera_config_read_dma;
  logic clk_i=0,rst_ni=0,start_i=0,clear_error_i=0;
  logic[63:0]base_addr_i=0;logic busy_o,done_pulse_o,result_valid_o,result_ready_i=0,result_error_o;
  logic[1:0]error_status_o;
  logic signed[21:0]cfg_r00_q20_o,cfg_r01_q20_o,cfg_r02_q20_o,cfg_r10_q20_o,cfg_r11_q20_o,cfg_r12_q20_o;
  logic signed[21:0]cfg_r20_q20_o,cfg_r21_q20_o,cfg_r22_q20_o;
  logic signed[26:0]cfg_tx_q16_o,cfg_ty_q16_o,cfg_tz_q16_o,cfg_camera_x_q16_o,cfg_camera_y_q16_o,cfg_camera_z_q16_o;
  logic signed[32:0]cfg_fx_q16_o,cfg_fy_q16_o,cfg_cx_q16_o,cfg_cy_q16_o;
  logic signed[26:0]cfg_near_q16_o,cfg_far_q16_o,cfg_depth_pivot0_q16_o,cfg_depth_pivot1_q16_o,cfg_depth_pivot2_q16_o;
  logic[34:0]cfg_regularizer_q8_o;logic[15:0]image_width_o,image_height_o;logic[31:0]gaussian_count_o;
  logic[1:0]m_axi_arid_o,m_axi_rid_i=1;logic[63:0]m_axi_araddr_o;logic[7:0]m_axi_arlen_o;
  logic[2:0]m_axi_arsize_o;logic[1:0]m_axi_arburst_o;logic m_axi_arvalid_o,m_axi_arready_i=1;
  logic[127:0]m_axi_rdata_i=0;logic[1:0]m_axi_rresp_i=0;logic m_axi_rlast_i=0,m_axi_rvalid_i=0,m_axi_rready_o;
  logic[63:0]words[0:27];integer cursor=0,burst_left=0,ar_count=0,inject_error_beat=-1;
  always#5 clk_i=~clk_i;

  axi4_camera_config_read_dma #(.AXI_ID(2'd1))dut(.*);

  always_ff@(posedge clk_i)begin
    if(!rst_ni)begin m_axi_rvalid_i<=0;m_axi_rlast_i<=0;m_axi_rresp_i<=0;burst_left<=0;end
    else begin
      if(m_axi_arvalid_o&&m_axi_arready_i)begin burst_left<=m_axi_arlen_o+1;ar_count<=ar_count+1;end
      if(!m_axi_rvalid_i&&burst_left>0)begin
        m_axi_rdata_i<={words[2*cursor+1],words[2*cursor]};
        m_axi_rlast_i<=burst_left==1;m_axi_rresp_i<=cursor==inject_error_beat?2'b10:2'b00;
        m_axi_rvalid_i<=1;
      end else if(m_axi_rvalid_i&&m_axi_rready_o)begin
        m_axi_rvalid_i<=0;cursor<=cursor+1;burst_left<=burst_left-1;
      end
    end
  end

  task automatic init_good;begin
    for(integer i=0;i<28;i=i+1)words[i]=0;
    words[0]=64'(22'sd1048576);words[4]=64'(22'sd1048576);words[8]=64'(22'sd1048576);
    words[9]=64'(-27'sd3);words[10]=64'(27'sd4);words[11]=64'(27'sd5);
    words[12]=64'(27'sd6);words[13]=64'(27'sd7);words[14]=64'(27'sd8);
    words[15]=64'(33'sd262144);words[16]=64'(33'sd262145);
    words[17]=64'(33'sd1048576);words[18]=64'(33'sd524288);
    words[19]=64'(27'sd13107);words[20]=64'(27'sd65536000);words[21]=77;
    words[22]=27'sd196608;words[23]=27'sd262144;words[24]=27'sd327680;
    words[25]=64;words[26]=48;words[27]={32'h47534301,32'd3};
  end endtask

  task automatic begin_read(input[63:0]address);begin
    cursor=0;burst_left=0;ar_count=0;base_addr_i=address;start_i=1;@(posedge clk_i);#1;start_i=0;
  end endtask
  task automatic await_result;integer timeout;begin
    timeout=0;while(!result_valid_o&&timeout<200)begin @(posedge clk_i);timeout=timeout+1;end
    if(!result_valid_o)$fatal(1,"camera DMA timeout");
  end endtask
  task automatic accept_result;begin result_ready_i=1;@(posedge clk_i);#1;result_ready_i=0;end endtask

  initial begin
    init_good();repeat(3)@(posedge clk_i);rst_ni=1;

    // 0xfe0 leaves only two beats before the 4-KiB boundary.
    begin_read(64'h0000_0000_0000_0fe0);await_result();
    if(result_error_o||error_status_o!=0||ar_count!=2)$fatal(1,"valid split descriptor failed status=%b bursts=%0d",error_status_o,ar_count);
    if(cfg_r00_q20_o!=1048576||cfg_tx_q16_o!=-3||cfg_fy_q16_o!=262145||
       image_width_o!=64||image_height_o!=48||gaussian_count_o!=3||cfg_depth_pivot2_q16_o!=327680)
      $fatal(1,"camera fields decoded incorrectly");
    repeat(2)@(posedge clk_i);if(!result_valid_o)$fatal(1,"result did not hold under backpressure");
    accept_result();@(posedge clk_i);

    init_good();words[27][63:32]=32'h0;inject_error_beat=-1;
    begin_read(64'h2000);await_result();
    if(!result_error_o||error_status_o!=2'b10)$fatal(1,"bad tag not rejected status=%b",error_status_o);
    accept_result();

    init_good();inject_error_beat=3;
    begin_read(64'h2000);await_result();
    if(!result_error_o||!error_status_o[0])$fatal(1,"AXI error not reported status=%b",error_status_o);
    accept_result();inject_error_beat=-1;

    init_good();begin_read(64'h2008);await_result();
    if(!result_error_o||error_status_o!=2'b10||ar_count!=0)$fatal(1,"misalignment not rejected");
    accept_result();
    $display("PASS: tb_axi4_camera_config_read_dma");$finish;
  end
endmodule
