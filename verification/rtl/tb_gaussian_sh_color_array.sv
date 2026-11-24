`timescale 1ns/1ps
module tb_gaussian_sh_color_array;
  localparam LANES=4,META_W=16,SEQ_W=8,COEFF_W=18,FLAT_W=3*16*COEFF_W;
  logic clk_i=0,rst_ni=0;logic[2:0]cfg_active_lanes_i=4;logic s_valid_i=0,s_ready_o;logic[META_W-1:0]s_meta_i=0;
  logic signed[26:0]s_world_x_q16_i=0,s_world_y_q16_i=0,s_world_z_q16_i=131072;
  logic signed[26:0]cfg_camera_x_q16_i=0,cfg_camera_y_q16_i=0,cfg_camera_z_q16_i=0;logic[FLAT_W-1:0]s_coeff_q12_flat_i='0;
  logic m_valid_o,m_ready_i=1;logic[META_W-1:0]m_meta_o;logic[12:0]m_r_q12_o,m_g_q12_o,m_b_q12_o;
  logic m_direction_fallback_o,m_numeric_overflow_o;logic[LANES-1:0]active_mask_o;logic all_idle_o,retire_wait_o,protocol_error_o;
  always#5 clk_i=~clk_i;
  gaussian_sh_color_array #(.LANES(LANES),.META_W(META_W),.SEQ_W(SEQ_W))dut(.*);
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic send(input integer seq,input integer basis);begin while(!s_ready_o)tick();s_meta_i={8'ha5,seq[7:0]};
    s_coeff_q12_flat_i='0;s_coeff_q12_flat_i[basis*COEFF_W+:COEFF_W]=18'sd4096;s_valid_i=1;tick();s_valid_i=0;end endtask
  initial begin integer expected,timeout;integer expected_r[1:4];expected_r[1]=3203;expected_r[2]=4049;expected_r[3]=2048;expected_r[4]=3203;
    repeat(2)tick();rst_ni=1;tick();if(active_mask_o!==4'b1111)$fatal(1,"SH array active mask mismatch");
    send(1,0);send(2,2);send(3,1);send(4,0);expected=1;timeout=0;
    while(expected<=4&&timeout<400)begin m_ready_i=(timeout%7!=2);
      if(m_valid_o&&m_ready_i)begin
        if(m_meta_o!=={8'ha5,expected[7:0]}||m_r_q12_o!==expected_r[expected]||m_g_q12_o!==2048||m_b_q12_o!==2048)
          $fatal(1,"SH array result/order mismatch seq=%0d rgb=%0d,%0d,%0d",m_meta_o[7:0],m_r_q12_o,m_g_q12_o,m_b_q12_o);
        if(m_direction_fallback_o||m_numeric_overflow_o||protocol_error_o)$fatal(1,"unexpected SH flags");expected=expected+1;
      end tick();timeout=timeout+1;
    end
    if(expected!=5)$fatal(1,"SH array timeout");timeout=0;while(!all_idle_o&&timeout<20)begin tick();timeout=timeout+1;end
    if(!all_idle_o)$fatal(1,"SH array did not drain");cfg_active_lanes_i=1;tick();if(active_mask_o!==4'b0001)$fatal(1,"SH E-mode mask mismatch");
    send(5,2);timeout=0;while(!(m_valid_o&&m_ready_i)&&timeout<200)begin tick();timeout=timeout+1;end
    if(m_meta_o[7:0]!==5||m_r_q12_o!==4049)$fatal(1,"SH single-lane equivalence failed");tick();
    $display("PASS: tb_gaussian_sh_color_array");$finish;
  end
endmodule
