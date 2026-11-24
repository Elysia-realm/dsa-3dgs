`timescale 1ns/1ps
// Environment smoke only. These cell/pin names match the project's Nangate45 TT library.
module env_smoke(input clk_i, input d_i, output q_o);
  wire first_q;
  DFF_X1 u_first (.D(d_i), .CK(clk_i), .Q(first_q), .QN());
  DFF_X1 u_second (.D(first_q), .CK(clk_i), .Q(q_o), .QN());
endmodule
