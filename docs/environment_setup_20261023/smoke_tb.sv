`timescale 1ns/1ps
// Functional model for the installation smoke only; no cell delays are modeled.
module DFF_X1(input D, input CK, output reg Q, output QN);
  assign QN = ~Q;
  always @(posedge CK) Q <= D;
endmodule

module tb;
  reg clk_i = 0;
  reg d_i = 0;
  wire q_o;
  reg previous_d = 0;
  env_smoke dut(.clk_i(clk_i), .d_i(d_i), .q_o(q_o));
  always #2.5 clk_i = ~clk_i;
  initial begin
    $dumpfile("smoke.vcd");
    $dumpvars(0, tb);
    repeat (2) @(negedge clk_i);
    for (integer i = 0; i < 12; i = i + 1) begin
      d_i = ~d_i;
      @(posedge clk_i);
      #0.1;
      if (q_o !== previous_d) $fatal(1, "ENV_SIM_FAIL i=%0d", i);
      previous_d = d_i;
      @(negedge clk_i);
    end
    $display("ENV_SIM_PASS");
    $finish;
  end
endmodule
