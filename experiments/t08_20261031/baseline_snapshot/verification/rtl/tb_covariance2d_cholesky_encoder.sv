`timescale 1ns/1ps
module tb_covariance2d_cholesky_encoder;
    logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o;
    logic [15:0] s_meta_i='0;
    logic [34:0] s_cov00_q8_i=35'd1024,s_cov11_q8_i=35'd2304;
    logic signed [34:0] s_cov01_q8_i=0;
    logic signed [26:0] s_mean_x_q8_i=27'sd4096,s_mean_y_q8_i=27'sd4096;
    logic [15:0] s_x0_i=16'd10,s_y0_i=16'd10,s_x1_i=16'd23,s_y1_i=16'd23;
    logic [12:0] s_opacity_q12_i=13'd3072;
    logic s_numeric_overflow_i=0;
    logic m_valid_o,m_ready_i=1;
    logic [15:0] m_meta_o;
    logic [14:0] m_l00_q12_o,m_l11_q12_o;
    logic signed [15:0] m_l10_q12_o;
    logic signed [5:0] m_coordinate_shift_o,m_factor_shift_o;
    logic [12:0] m_opacity_q12_o;
    logic m_numeric_overflow_o;

    always #5 clk_i=~clk_i;
    covariance2d_cholesky_encoder #(.META_W(16)) dut(.*);
    task automatic tick;begin @(posedge clk_i);#1;end endtask
    task automatic send;begin
        while(!s_ready_o)tick();s_valid_i=1;tick();s_valid_i=0;
    end endtask
    task automatic wait_result;integer timeout;begin
        timeout=0;while(!m_valid_o&&timeout<300)begin tick();timeout=timeout+1;end
        if(!m_valid_o)$fatal(1,"encoder timeout");
    end endtask

    initial begin
        repeat(2)tick();rst_ni=1;tick();
        // Covariance diag(4,9) -> conic diag(0.25,1/9).
        // factor_shift=-3 gives encoded factors 4.0 and about 2.6667.
        s_meta_i=16'h1234;send();
        repeat(20)tick();m_ready_i=0;repeat(7)tick();m_ready_i=1;
        wait_result();
        if(m_meta_o!==16'h1234||m_l00_q12_o!==15'd16384
           ||m_l10_q12_o!==0||m_l11_q12_o<15'd10920
           ||m_l11_q12_o>15'd10924||m_coordinate_shift_o!==0
           ||m_factor_shift_o!==-6'sd3||m_opacity_q12_o!==13'd3072
           ||m_numeric_overflow_o)
            $fatal(1,"diag mismatch meta=%h L=%0d,%0d,%0d shifts=%0d,%0d op=%0d err=%b",
              m_meta_o,m_l00_q12_o,m_l10_q12_o,m_l11_q12_o,
              m_coordinate_shift_o,m_factor_shift_o,m_opacity_q12_o,m_numeric_overflow_o);
        tick();
        // Large pixel-relative extent independently raises coordinate shift;
        // factor encoding must remain unchanged.
        s_meta_i=16'h5678;s_mean_x_q8_i=0;s_mean_y_q8_i=0;
        s_x0_i=0;s_y0_i=0;s_x1_i=16'd256;s_y1_i=16'd1;send();wait_result();
        if(m_meta_o!==16'h5678||m_coordinate_shift_o!==6'sd4
           ||m_factor_shift_o!==-6'sd3||m_l00_q12_o!==15'd16384
           ||m_numeric_overflow_o)
            $fatal(1,"coordinate shift mismatch meta=%h shifts=%0d,%0d err=%b",
                   m_meta_o,m_coordinate_shift_o,m_factor_shift_o,m_numeric_overflow_o);
        tick();
        // Singular covariance must complete with an error instead of hanging.
        s_meta_i=16'hdead;s_cov00_q8_i=32'd256;s_cov01_q8_i=32'sd256;
        s_cov11_q8_i=32'd256;s_numeric_overflow_i=0;send();wait_result();
        if(m_meta_o!==16'hdead||!m_numeric_overflow_o)
            $fatal(1,"singular covariance was not flagged meta=%h err=%b",
                   m_meta_o,m_numeric_overflow_o);
        tick();
        // Real Bonsai camera-146 stress point (GID 606379), Q27.8.  This used
        // to saturate the 32-bit covariance interface and collapse to the
        // meaningless factor tuple {11585,11585,0}, shift 0.
        s_meta_i=16'h0637;s_cov00_q8_i=35'd16095012864;
        s_cov01_q8_i=-35'sd867948544;s_cov11_q8_i=35'd47308700;
        send();wait_result();
        if(m_meta_o!==16'h0637||m_factor_shift_o!==-6'sd7
           ||m_l00_q12_o<15'd635||m_l00_q12_o>15'd650
           ||m_l10_q12_o<16'sd11740||m_l10_q12_o>16'sd11785
           ||m_l11_q12_o<15'd1150||m_l11_q12_o>15'd1300
           ||m_numeric_overflow_o)
            $fatal(1,"real GID 606379 mismatch meta=%h L=%0d,%0d,%0d shift=%0d err=%b",
              m_meta_o,m_l00_q12_o,m_l10_q12_o,m_l11_q12_o,
              m_factor_shift_o,m_numeric_overflow_o);
        tick();$display("PASS: tb_covariance2d_cholesky_encoder");$finish;
    end
endmodule
