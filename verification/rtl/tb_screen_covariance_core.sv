`timescale 1ns/1ps

module tb_screen_covariance_core;
    localparam integer TESTS=4;
    logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o;
    logic [15:0] s_meta_i='0;
    logic signed [26:0] s_camera_x_q16_i=0,s_camera_y_q16_i=0,s_camera_z_q16_i=27'sd131072;
    logic signed [40:0] s_cov_xx_q16_i=41'sd1048576,s_cov_xy_q16_i=0,s_cov_xz_q16_i=0;
    logic signed [40:0] s_cov_yy_q16_i=41'sd1048576,s_cov_yz_q16_i=0,s_cov_zz_q16_i=41'sd1048576;
    logic signed [32:0] cfg_fx_q16_i=33'sd262144,cfg_fy_q16_i=33'sd262144;
    localparam integer COV2_W=35;
    logic [COV2_W-1:0] cfg_regularizer_q8_i=COV2_W'(77);
    logic [15:0] cfg_image_width_i=640,cfg_image_height_i=480;
    logic m_valid_o,m_ready_i=1;
    logic [15:0] m_meta_o;
    logic [COV2_W-1:0] m_cov00_q8_o,m_cov11_q8_o;
    logic signed [COV2_W-1:0] m_cov01_q8_o;
    logic m_numeric_overflow_o;
    logic [15:0]expected_meta[0:TESTS-1];
    logic[COV2_W-1:0]expected_cov00[0:TESTS-1],expected_cov11[0:TESTS-1];
    logic signed[COV2_W-1:0]expected_cov01[0:TESTS-1];logic expected_overflow[0:TESTS-1];
    integer accepted=0,received=0,cycles=0;
    always #5 clk_i=~clk_i;
    screen_covariance_core #(.META_W(16)) dut(.*);
    task automatic tick;begin @(posedge clk_i);#1;end endtask
    task automatic send(input logic[15:0]meta,input logic signed[26:0]x,y,z,
      input logic signed[40:0]xx,xy,xz,yy,yz,zz,input logic[COV2_W-1:0]e00,
      input logic signed[COV2_W-1:0]e01,input logic[COV2_W-1:0]e11,input logic eov);
      begin
        while(!s_ready_o)tick();
        expected_meta[accepted]=meta;expected_cov00[accepted]=e00;
        expected_cov01[accepted]=e01;expected_cov11[accepted]=e11;
        expected_overflow[accepted]=eov;
        s_meta_i=meta;s_camera_x_q16_i=x;s_camera_y_q16_i=y;s_camera_z_q16_i=z;
        s_cov_xx_q16_i=xx;s_cov_xy_q16_i=xy;s_cov_xz_q16_i=xz;
        s_cov_yy_q16_i=yy;s_cov_yz_q16_i=yz;s_cov_zz_q16_i=zz;
        s_valid_i=1;accepted=accepted+1;tick();s_valid_i=0;
      end
    endtask
    always@(posedge clk_i)begin
      if(rst_ni&&m_valid_o&&m_ready_i)begin
        if(m_meta_o!==expected_meta[received]||m_numeric_overflow_o!==expected_overflow[received]||
          (!expected_overflow[received]&&(m_cov00_q8_o!==expected_cov00[received]||
          m_cov01_q8_o!==expected_cov01[received]||m_cov11_q8_o!==expected_cov11[received])))
          $fatal(1,"screen covariance[%0d] mismatch meta=%h cov=%0d,%0d,%0d overflow=%b",
            received,m_meta_o,m_cov00_q8_o,m_cov01_q8_o,m_cov11_q8_o,m_numeric_overflow_o);
        received<=received+1;
      end
    end
    initial begin
        // Direct saturation helpers cover signed/unsigned output boundaries.
        if(dut.saturate_unsigned(-111'sd1)!==0||
           dut.saturate_unsigned(111'sd34359738367)!==35'h7_ffff_ffff)
          $fatal(1,"unsigned covariance saturation boundary mismatch");
        if(dut.saturate_signed(111'sd17179869183)!==$signed(35'h3_ffff_ffff)||
           dut.saturate_signed(-111'sd17179869184)!==$signed(35'h4_0000_0000))
          $fatal(1,"signed covariance saturation boundary mismatch");
        repeat(2)tick();rst_ni=1;tick();
        // f=4,z=2, identity covariance -> diag=(4,4)+0.30078125.
        send(16'h3344,0,0,27'sd131072,41'sd1048576,0,0,41'sd1048576,0,41'sd1048576,
          32'd1101,0,32'd1101,0);
        // x=1 activates j02=-fx*x/z^2=-1. Identity covariance then gives
        // cov00=2^2+(-1)^2=5, cov11=4 before regularization.
        send(16'h7788,27'sd65536,0,27'sd131072,41'sd1048576,0,0,41'sd1048576,0,41'sd1048576,
          32'd1357,0,32'd1101,0);
        // x=y=1 gives j02=j12=-1. Identity covariance produces off-diagonal 1.
        send(16'h99aa,27'sd65536,27'sd65536,27'sd131072,41'sd1048576,0,0,
          41'sd1048576,0,41'sd1048576,35'd1357,35'sd256,35'd1357,0);
        // Behind-camera/zero denominator must retire with a visible error.
        send(16'hbbcc,0,0,0,41'sd1048576,0,0,41'sd1048576,0,41'sd1048576,0,0,0,1);
        m_ready_i=0;repeat(7)tick();m_ready_i=1;
        while(received<TESTS&&cycles<300)begin m_ready_i=(cycles%5)!=2;tick();cycles=cycles+1;end
        if(received!=TESTS)$fatal(1,"screen covariance timeout received=%0d",received);
        m_ready_i=1;tick();$display("PASS: tb_screen_covariance_core transactions=%0d",received);$finish;
    end
endmodule
