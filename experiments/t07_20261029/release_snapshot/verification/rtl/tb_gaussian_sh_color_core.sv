`timescale 1ns/1ps
module tb_gaussian_sh_color_core;
  localparam META_W=8,COORD_W=27,COEFF_W=18,FLAT_W=3*16*COEFF_W;
  logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o;logic[META_W-1:0]s_meta_i='0;
  logic signed[COORD_W-1:0]s_world_x_q16_i=0,s_world_y_q16_i=0,s_world_z_q16_i=0;
  logic signed[COORD_W-1:0]cfg_camera_x_q16_i=0,cfg_camera_y_q16_i=0,cfg_camera_z_q16_i=0;
  logic[FLAT_W-1:0]s_coeff_q12_flat_i='0;logic m_valid_o,m_ready_i=1;logic[META_W-1:0]m_meta_o;
  logic[12:0]m_r_q12_o,m_g_q12_o,m_b_q12_o;logic m_direction_fallback_o,m_numeric_overflow_o;
  always#5 clk_i=~clk_i;
  gaussian_sh_color_core #(.META_W(META_W),.COORD_W(COORD_W))dut(.*);
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic send_check(input[7:0]meta,input integer wx,wy,wz,cx,cy,cz,er,input logic fallback);
    integer timeout;begin while(!s_ready_o)tick();s_meta_i=meta;s_world_x_q16_i=wx;s_world_y_q16_i=wy;s_world_z_q16_i=wz;
      cfg_camera_x_q16_i=cx;cfg_camera_y_q16_i=cy;cfg_camera_z_q16_i=cz;s_valid_i=1;tick();s_valid_i=0;
      timeout=0;while(!m_valid_o&&timeout<110)begin tick();timeout=timeout+1;end
      if(!m_valid_o||m_meta_o!==meta||m_r_q12_o!==er||m_direction_fallback_o!==fallback||m_numeric_overflow_o)
        $fatal(1,"Gaussian SH mismatch meta=%h r=%0d fallback=%b overflow=%b",m_meta_o,m_r_q12_o,m_direction_fallback_o,m_numeric_overflow_o);
      tick();end endtask
  initial begin
    repeat(2)tick();rst_ni=1;tick();
    // R uses the +Z first-order basis; other channels remain at the 0.5 bias.
    s_coeff_q12_flat_i='0;s_coeff_q12_flat_i[2*COEFF_W+:COEFF_W]=18'sd4096;
    send_check(8'h61,0,0,2*65536,0,0,0,4049,0);
    send_check(8'h62,65536,0,3*65536,65536,0,65536,4049,0);
    send_check(8'h63,7*65536,0,3*65536,7*65536,0,3*65536,4049,1);
    $display("PASS: tb_gaussian_sh_color_core");$finish;
  end
endmodule
