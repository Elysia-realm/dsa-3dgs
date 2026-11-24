`timescale 1ns/1ps
module tb_gaussian_depth_prepass_core;
  localparam integer ONE_Q20=1<<20;
  logic clk_i=0,rst_ni=0,frame_start_i=0,s_valid_i=0,s_ready_o;
  logic[7:0]s_gid_i=0,s_payload_i=0;
  logic signed[26:0]s_world_x_q16_i=0,s_world_y_q16_i=0,s_world_z_q16_i=0;
  logic signed[21:0]cfg_r20_q20_i=0,cfg_r21_q20_i=0,cfg_r22_q20_i=ONE_Q20;
  logic signed[26:0]cfg_tz_q16_i=5*65536,cfg_near_q16_i=0,cfg_far_q16_i=100*65536;
  logic m_valid_o,m_ready_i=1;logic signed[26:0]m_depth_q16_o;
  logic[7:0]m_gid_o,m_seq_o,m_payload_o;logic m_visible_o,m_numeric_overflow_o;
  integer received=0;logic signed[26:0]expect_depth[0:3];logic[7:0]expect_gid[0:3];
  logic expect_visible[0:3],expect_overflow[0:3];
  always#5 clk_i=~clk_i;
  gaussian_depth_prepass_core #(.GID_W(8),.SEQ_W(8),.PAYLOAD_W(8))dut(
    .clk_i(clk_i),.rst_ni(rst_ni),.frame_start_i(frame_start_i),.s_valid_i(s_valid_i),.s_ready_o(s_ready_o),
    .s_gid_i(s_gid_i),.s_payload_i(s_payload_i),.s_world_x_q16_i(s_world_x_q16_i),
    .s_world_y_q16_i(s_world_y_q16_i),.s_world_z_q16_i(s_world_z_q16_i),
    .cfg_r20_q20_i(cfg_r20_q20_i),.cfg_r21_q20_i(cfg_r21_q20_i),.cfg_r22_q20_i(cfg_r22_q20_i),
    .cfg_tz_q16_i(cfg_tz_q16_i),.cfg_near_q16_i(cfg_near_q16_i),.cfg_far_q16_i(cfg_far_q16_i),
    .m_valid_o(m_valid_o),.m_ready_i(m_ready_i),.m_depth_q16_o(m_depth_q16_o),.m_gid_o(m_gid_o),
    .m_seq_o(m_seq_o),.m_payload_o(m_payload_o),.m_visible_o(m_visible_o),
    .m_numeric_overflow_o(m_numeric_overflow_o));
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic send(input integer gid,input integer x,input integer y,input integer z);begin
    #1;while(!s_ready_o)tick();s_gid_i=gid;s_payload_i=gid+8'h40;
    s_world_x_q16_i=x*65536;s_world_y_q16_i=y*65536;s_world_z_q16_i=z*65536;
    s_valid_i=1;tick();s_valid_i=0;
  end endtask
  always@(posedge clk_i)if(rst_ni&&m_valid_o&&m_ready_i)begin
    if(received>3)$fatal(1,"unexpected prepass result");
    if(m_depth_q16_o!==expect_depth[received]||m_gid_o!==expect_gid[received]||m_seq_o!==received||
       m_payload_o!==(expect_gid[received]+8'h40)||m_visible_o!==expect_visible[received]||
       m_numeric_overflow_o!==expect_overflow[received])
      $fatal(1,"prepass[%0d] got depth/gid/seq/vis/ov=%0d/%0d/%0d/%0d/%0d",
        received,m_depth_q16_o,m_gid_o,m_seq_o,m_visible_o,m_numeric_overflow_o);
    received<=received+1;
  end
  initial begin integer timeout;logic signed[26:0]held_depth;logic[7:0]held_gid,held_seq;
    expect_depth[0]=15*65536;expect_gid[0]=1;expect_visible[0]=1;expect_overflow[0]=0;
    expect_depth[1]=-5*65536;expect_gid[1]=2;expect_visible[1]=0;expect_overflow[1]=0;
    expect_depth[2]=120*65536;expect_gid[2]=3;expect_visible[2]=0;expect_overflow[2]=0;
    expect_depth[3]={1'b0,{26{1'b1}}};expect_gid[3]=4;expect_visible[3]=0;expect_overflow[3]=1;
    repeat(2)tick();rst_ni=1;tick();
    // The first record intentionally coincides with frame_start and must get seq=0.
    frame_start_i=1;send(1,0,0,10);frame_start_i=0;tick();
    m_ready_i=0;send(2,0,0,-10);held_depth=m_depth_q16_o;held_gid=m_gid_o;held_seq=m_seq_o;
    repeat(3)begin
      s_gid_i=$random;s_world_z_q16_i=$random;tick();
      if(!m_valid_o||m_depth_q16_o!==held_depth||m_gid_o!==held_gid||m_seq_o!==held_seq)
        $fatal(1,"prepass output changed under backpressure");
    end
    m_ready_i=1;tick();
    cfg_tz_q16_i=0;send(3,0,0,120);
    cfg_r20_q20_i=ONE_Q20;cfg_r21_q20_i=ONE_Q20;send(4,600,600,600);
    timeout=0;while(received<4&&timeout<30)begin tick();timeout=timeout+1;end
    if(received!=4)$fatal(1,"prepass timeout received=%0d",received);
    $display("PASS: tb_gaussian_depth_prepass_core");$finish;
  end
endmodule
