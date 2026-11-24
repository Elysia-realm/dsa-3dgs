`timescale 1ns/1ps
module tb_sh_degree3_color_core;
  localparam META_W=8,COEFF_W=18,FLAT_W=3*16*COEFF_W;
  logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o;logic[META_W-1:0]s_meta_i='0;
  logic signed[21:0]s_x_q20_i=0,s_y_q20_i=0,s_z_q20_i=22'sd1048576;
  logic[FLAT_W-1:0]s_coeff_q12_flat_i='0;logic s_numeric_overflow_i=0;
  logic m_valid_o,m_ready_i=1;logic[META_W-1:0]m_meta_o;logic[12:0]m_r_q12_o,m_g_q12_o,m_b_q12_o;logic m_numeric_overflow_o;
  always#5 clk_i=~clk_i;
  sh_degree3_color_core #(.META_W(META_W))dut(.*);
  task automatic tick;begin @(posedge clk_i);#1;end endtask
  task automatic clear_coeff;begin s_coeff_q12_flat_i='0;end endtask
  task automatic coeff(input integer channel,basis,value);begin
    s_coeff_q12_flat_i[(channel*16+basis)*COEFF_W+:COEFF_W]=value;
  end endtask
  task automatic issue_check(input[7:0]meta,input integer er,eg,eb);
    integer timeout;begin while(!s_ready_o)tick();s_meta_i=meta;s_valid_i=1;tick();s_valid_i=0;
      timeout=0;while(!m_valid_o&&timeout<10)begin tick();timeout=timeout+1;end
      if(!m_valid_o||m_meta_o!==meta||m_r_q12_o!==er||m_g_q12_o!==eg||m_b_q12_o!==eb||m_numeric_overflow_o)
        $fatal(1,"SH mismatch meta=%h rgb=%0d,%0d,%0d expected=%0d,%0d,%0d",m_meta_o,m_r_q12_o,m_g_q12_o,m_b_q12_o,er,eg,eb);
      tick();end endtask
  initial begin
    repeat(2)tick();rst_ni=1;tick();
    clear_coeff();coeff(0,0,4096);coeff(1,0,4096);coeff(2,0,4096);issue_check(8'h01,3203,3203,3203);
    // At +Z, basis 2 is +C1; at +Y, basis 1 is -C1.
    clear_coeff();coeff(0,2,4096);s_x_q20_i=0;s_y_q20_i=0;s_z_q20_i=1048576;issue_check(8'h02,4049,2048,2048);
    clear_coeff();coeff(0,1,4096);s_y_q20_i=1048576;s_z_q20_i=0;issue_check(8'h03,47,2048,2048);
    clear_coeff();coeff(0,0,8*4096);coeff(1,0,-8*4096);issue_check(8'h04,4096,0,2048);
    // Result slice backpressure stability.
    clear_coeff();coeff(2,0,4096);s_y_q20_i=0;s_z_q20_i=1048576;
    while(!s_ready_o)tick();s_meta_i=8'h55;s_valid_i=1;tick();s_valid_i=0;m_ready_i=0;
    while(!m_valid_o)tick();repeat(3)begin if(m_meta_o!==8'h55||m_b_q12_o!==3203)$fatal(1,"SH changed under backpressure");tick();end
    m_ready_i=1;tick();$display("PASS: tb_sh_degree3_color_core");$finish;
  end
endmodule
