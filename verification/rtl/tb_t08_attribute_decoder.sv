`timescale 1ns/1ps
module tb_t08_attribute_decoder;
  localparam MAX_N=8192;
  logic clk=0,rst_n=0,run_phase=0,s_valid=0,s_ready,m_valid,m_ready,m_error,precomputed;
  logic [1151:0] packet=0;
  logic [3:0] beats=0;
  logic [1117:0] legacy;
  logic [245:0] covariance;
  logic [1:0] degree;
  logic [1155:0] inputs[0:MAX_N-1];
  logic [1367:0] expected[0:MAX_N-1],actual,held_data;
  integer n,cycle=0,received=0,held=0;
  string input_path,expected_path;
  assign actual={m_error,precomputed,degree,legacy,covariance};
  assign m_ready=run_phase&&(cycle%23>=9);
  always #5 clk=~clk;
  t08_attribute_decoder dut(.clk_i(clk),.rst_ni(rst_n),.s_valid_i(s_valid),.s_ready_o(s_ready),
    .s_packet_i(packet),.s_beats_i(beats),.m_valid_o(m_valid),.m_ready_i(m_ready),.m_error_o(m_error),
    .m_legacy_o(legacy),.m_covariance_q20_o(covariance),.m_precomputed_o(precomputed),.m_degree_o(degree));
  always @(posedge clk)begin
    if(!rst_n)begin cycle<=0;received<=0;held<=0;end
    else begin
      cycle<=cycle+1;
      if(held&&(!m_valid||actual!==held_data))$fatal(1,"decoder changed stalled response");
      held<=m_valid&&!m_ready;
      if(m_valid&&!m_ready)held_data<=actual;
      if(m_valid&&m_ready)begin
        if(received>=n||actual!==expected[received])$fatal(1,"decoder mismatch i=%0d got=%h expected=%h",received,actual,expected[received]);
        received<=received+1;
      end
      if(cycle>100000)$fatal(1,"decoder timeout");
    end
  end
  initial begin
    if(!$value$plusargs("N=%d",n)||n<=0||n>MAX_N)$fatal;
    if(!$value$plusargs("INPUT=%s",input_path)||!$value$plusargs("EXPECTED=%s",expected_path))$fatal;
    $readmemh(input_path,inputs,0,n-1);$readmemh(expected_path,expected,0,n-1);
    repeat(3)@(negedge clk);rst_n=1;
    @(negedge clk);{beats,packet}=inputs[0];s_valid=1;
    @(negedge clk);s_valid=0;
    repeat(3)@(negedge clk);
    if(!m_valid)$fatal(1,"reset probe did not queue response");
    rst_n=0;@(negedge clk);if(m_valid)$fatal(1,"reset did not invalidate response");
    rst_n=1;run_phase=1;
    for(integer i=0;i<n;i=i+1)begin
      @(negedge clk);{beats,packet}=inputs[i];s_valid=1;
      while(!s_ready)@(negedge clk);
      @(posedge clk);#1;s_valid=0;
    end
    wait(received==n);@(negedge clk);
    $display("PASS T08 attribute decoder vectors=%0d cycles=%0d reset_pending=1",received,cycle);$finish;
  end
endmodule
