`timescale 1ns/1ps
module tb_ordered_projection_sh_join;
  localparam META_W=16,SEQ_W=8,TASK_W=32,COLOR_W=16;
  logic clk_i=0,rst_ni=0,projection_valid_i=0,projection_ready_o;logic[TASK_W-1:0]projection_data_i=0;
  logic projection_first_i=0,projection_last_i=0,projection_culled_i=0;
  logic sh_valid_i=0,sh_ready_o;logic[META_W-1:0]sh_meta_i=0;logic[COLOR_W-1:0]sh_color_i=0;
  logic m_valid_o,m_ready_i=1;logic[TASK_W-1:0]m_projection_data_o;logic[COLOR_W-1:0]m_color_o;
  logic m_first_o,m_last_o,m_culled_o,sequence_mismatch_o,empty_o;logic[2:0]sh_occupancy_o;
  always#5 clk_i=~clk_i;ordered_projection_sh_join #(.TASK_W(TASK_W),.META_W(META_W),.SEQ_W(SEQ_W),.COLOR_W(COLOR_W),.SH_DEPTH(4))dut(.*);
  initial begin #200000;$fatal(1,"join watchdog pv=%b pr=%b sv=%b sr=%b mv=%b occ=%0d",projection_valid_i,projection_ready_o,sh_valid_i,sh_ready_o,m_valid_o,sh_occupancy_o);end
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic send_sh(input[15:0]meta,color);begin while(!sh_ready_o)tick();sh_meta_i=meta;sh_color_i=color;sh_valid_i=1;tick();sh_valid_i=0;tick();end endtask
  task automatic send_block(input[15:0]meta,input[15:0]payload,input logic first,last,culled,input[15:0]color);integer guard;begin
    projection_data_i={meta,payload};projection_first_i=first;projection_last_i=last;projection_culled_i=culled;projection_valid_i=1;#1;
    guard=0;while(!m_valid_o&&guard<20)begin tick();guard=guard+1;end
    if(!m_valid_o)$fatal(1,"join wait meta=%h occ=%0d head=%h pm=%h mismatch=%b",meta,sh_occupancy_o,dut.head_meta,dut.projection_meta,sequence_mismatch_o);
    if(m_projection_data_o!=={meta,payload}||m_color_o!==color||m_first_o!==first||m_last_o!==last||m_culled_o!==culled)
      $fatal(1,"join mismatch meta=%h",meta);tick();projection_valid_i=0;tick();end endtask
  initial begin repeat(2)tick();rst_ni=1;tick();send_sh(16'ha001,16'h1111);send_sh(16'ha002,16'h2222);
    send_block(16'ha001,16'h0100,1,0,0,16'h1111);send_block(16'ha001,16'h0101,0,0,0,16'h1111);
    m_ready_i=0;projection_data_i={16'ha001,16'h0102};projection_first_i=0;projection_last_i=1;projection_valid_i=1;#1;
    while(!m_valid_o)tick();repeat(3)begin if(m_color_o!==16'h1111||m_projection_data_o!=={16'ha001,16'h0102})$fatal(1,"join backpressure changed");tick();end
    m_ready_i=1;tick();projection_valid_i=0;
    send_block(16'ha002,16'h0200,1,1,1,16'h2222);if(!empty_o||sequence_mismatch_o)$fatal(1,"join final flags bad");
    $display("PASS: tb_ordered_projection_sh_join");$finish;
  end
endmodule
