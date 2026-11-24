`timescale 1ns/1ps
module tb_raster_alpha_lane_array;
  localparam LANES=4,META_W=24;logic clk_i=0,rst_ni=0;logic[2:0]cfg_active_lanes_i=4;
  logic s_valid_i=0,s_ready_o;logic[31:0]s_seq_i=0;logic[META_W-1:0]s_meta_i=0;
  logic signed[15:0]s_dx_q10_i=0,s_dy_q10_i=0;logic[14:0]s_l00_q12_i=4096,s_l11_q12_i=4096;
  logic signed[15:0]s_l10_q12_i=0;logic signed[5:0]s_coordinate_shift_i=0,s_factor_shift_i=0;logic[12:0]s_opacity_q12_i=0;
  logic m_valid_o,m_ready_i=1;logic[31:0]m_seq_o;logic[META_W-1:0]m_meta_o;logic[12:0]m_alpha_q12_o;logic m_pass_alpha_o;
  logic[LANES-1:0]active_mask_o;logic all_idle_o,retire_wait_o,protocol_error_o;
  always#5 clk_i=~clk_i;raster_alpha_lane_array #(.LANES(LANES),.META_W(META_W))dut(.*);
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic send(input integer seq,input integer opacity);begin while(!s_ready_o)tick();s_seq_i=seq;s_meta_i={8'h5a,seq[15:0]};s_opacity_q12_i=opacity;s_valid_i=1;tick();s_valid_i=0;end endtask
  initial begin integer expected,timeout;integer opacity[0:7];opacity[0]=15;opacity[1]=16;opacity[2]=1024;opacity[3]=2048;
    opacity[4]=4096;opacity[5]=3000;opacity[6]=20;opacity[7]=4055;repeat(2)tick();rst_ni=1;tick();
    if(active_mask_o!==4'b1111)$fatal(1,"raster alpha full mask mismatch");m_ready_i=0;
    for(expected=0;expected<8;expected=expected+1)send(expected,opacity[expected]);expected=0;timeout=0;m_ready_i=1;
    while(expected<8&&timeout<100)begin m_ready_i=(timeout%5!=2);
      if(m_valid_o&&m_ready_i)begin
        if(m_seq_o!==expected||m_meta_o!=={8'h5a,expected[15:0]}||
           m_alpha_q12_o!==(opacity[expected]>4055?4055:opacity[expected])||
           m_pass_alpha_o!==((opacity[expected]>4055?4055:opacity[expected])>=16))
          $fatal(1,"parallel alpha order/value mismatch got_seq=%0d exp_seq=%0d meta=%h alpha=%0d exp_alpha=%0d pass=%b",m_seq_o,expected,m_meta_o,m_alpha_q12_o,(opacity[expected]>4055?4055:opacity[expected]),m_pass_alpha_o);
        expected=expected+1;
      end tick();timeout=timeout+1;
    end
    if(expected!=8||protocol_error_o)$fatal(1,"parallel alpha timeout/protocol");timeout=0;while(!all_idle_o&&timeout<10)begin tick();timeout=timeout+1;end
    if(!all_idle_o)$fatal(1,"parallel alpha did not drain");cfg_active_lanes_i=1;tick();if(active_mask_o!==4'b0001)$fatal(1,"raster alpha E mask mismatch");
    send(8,2048);timeout=0;while(!(m_valid_o&&m_ready_i)&&timeout<30)begin tick();timeout=timeout+1;end
    if(m_seq_o!==8||m_alpha_q12_o!==2048)$fatal(1,"one-lane alpha equivalence failed");tick();
    $display("PASS: tb_raster_alpha_lane_array");$finish;
  end
endmodule
