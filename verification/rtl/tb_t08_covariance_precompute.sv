`timescale 1ns/1ps
module tb_t08_covariance_precompute;
  localparam N=2048;
  logic clk=0,rst_n=0,s_valid=0,s_ready,m_valid,m_ready;
  logic [15:0] s_meta=0,m_meta;
  logic [159:0] data=0,inputs[0:N-1];
  logic [246:0] expected[0:N-1],actual;
  logic signed [40:0] xx,xy,xz,yy,yz,zz;
  logic overflow;
  integer cycle=0,received=0,held=0;
  logic [262:0] held_data;
  string input_path,expected_path;
  always #5 clk=~clk;
  assign m_ready=(cycle%17>=7);
  assign actual={xx,xy,xz,yy,yz,zz,overflow};
  quaternion_scale_covariance_core #(.META_W(16)) dut(
    .clk_i(clk),.rst_ni(rst_n),.s_valid_i(s_valid),.s_ready_o(s_ready),.s_meta_i(s_meta),
    .s_qw_q20_i(data[159:138]),.s_qx_q20_i(data[137:116]),.s_qy_q20_i(data[115:94]),.s_qz_q20_i(data[93:72]),
    .s_scale_x_q20_i(data[71:48]),.s_scale_y_q20_i(data[47:24]),.s_scale_z_q20_i(data[23:0]),
    .m_valid_o(m_valid),.m_ready_i(m_ready),.m_meta_o(m_meta),
    .m_cov_xx_q16_o(xx),.m_cov_xy_q16_o(xy),.m_cov_xz_q16_o(xz),
    .m_cov_yy_q16_o(yy),.m_cov_yz_q16_o(yz),.m_cov_zz_q16_o(zz),.m_numeric_overflow_o(overflow));
  always @(posedge clk) if(rst_n)begin
    cycle<=cycle+1;
    if(held && (!m_valid || {m_meta,actual}!==held_data))$fatal(1,"response changed while stalled");
    held<=m_valid&&!m_ready;
    if(m_valid&&!m_ready)held_data<={m_meta,actual};
    if(m_valid&&m_ready)begin
      if(received>=N||m_meta!==16'(received)||actual!==expected[received])
        $fatal(1,"precompute mismatch index=%0d meta=%0d got=%h expected=%h",received,m_meta,actual,expected[received]);
      received<=received+1;
    end
    if(cycle>30000)$fatal(1,"covariance test timeout");
  end
  initial begin
    if(!$value$plusargs("INPUT=%s",input_path)||!$value$plusargs("EXPECTED=%s",expected_path))$fatal;
    $readmemh(input_path,inputs);$readmemh(expected_path,expected);
    repeat(3)@(negedge clk);rst_n=1;
    for(integer i=0;i<N;i=i+1)begin
      @(negedge clk);data=inputs[i];s_meta=16'(i);s_valid=1;
      while(!s_ready)@(negedge clk);
      @(posedge clk);#1;s_valid=0;
    end
    wait(received==N);@(negedge clk);
    $display("PASS T08 covariance precompute vectors=%0d cycles=%0d",received,cycle);$finish;
  end
endmodule
