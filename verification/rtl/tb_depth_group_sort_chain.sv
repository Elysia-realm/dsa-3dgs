`timescale 1ns/1ps
module tb_depth_group_sort_chain;
 logic clk_i=0,rst_ni=0,clear_overflow_i=0;
 logic s_valid_i=0,s_ready_o;logic signed[15:0]s_depth_i=0;logic[7:0]s_gid_i=0,s_seq_i=0,s_payload_i=0;logic frame_end_i=0;
 logic g_valid,g_ready;logic signed[15:0]g_depth;logic[7:0]g_gid,g_seq,g_payload;logic[1:0]g_group;
 logic g_first,g_last,frame_done,group_overflow,group_busy;
 logic m_valid_o,m_ready_i=1;logic signed[15:0]m_depth_o;logic[7:0]m_gid_o,m_seq_o,m_payload_o;logic[1:0]m_group_o;
 logic m_group_first_o,m_group_last_o,sort_overflow,sort_busy;
 logic signed[15:0]expect_depth[0:6];logic[7:0]expect_gid[0:6],expect_group[0:6];integer received=0;
 always#5 clk_i=~clk_i;
 depth_group_buffer #(.CAPACITY(4),.DEPTH_W(16),.GID_W(8),.SEQ_W(8),.PAYLOAD_W(8))u_group(
  .clk_i(clk_i),.rst_ni(rst_ni),.clear_overflow_i(clear_overflow_i),.s_valid_i(s_valid_i),.s_ready_o(s_ready_o),
  .s_depth_i(s_depth_i),.s_gid_i(s_gid_i),.s_seq_i(s_seq_i),.s_payload_i(s_payload_i),.frame_end_i(frame_end_i),
  .frame_abort_i(1'b0),
  .cfg_pivot0_i(16'sd100),.cfg_pivot1_i(16'sd200),.cfg_pivot2_i(16'sd300),
  .m_valid_o(g_valid),.m_ready_i(g_ready),.m_depth_o(g_depth),.m_gid_o(g_gid),.m_seq_o(g_seq),
  .m_payload_o(g_payload),.m_group_o(g_group),.m_group_first_o(g_first),.m_group_last_o(g_last),
  .frame_done_pulse_o(frame_done),.overflow_o(group_overflow),.busy_o(group_busy));
 stable_group_sorter #(.CAPACITY(4),.DEPTH_W(16),.GID_W(8),.SEQ_W(8),.GROUP_W(2),.PAYLOAD_W(8))u_sort(
  .clk_i(clk_i),.rst_ni(rst_ni),.clear_overflow_i(clear_overflow_i),.s_valid_i(g_valid),.s_ready_o(g_ready),
  .s_depth_i(g_depth),.s_gid_i(g_gid),.s_seq_i(g_seq),.s_group_i(g_group),.s_payload_i(g_payload),
  .s_group_last_i(g_last),.m_valid_o(m_valid_o),.m_ready_i(m_ready_i),.m_depth_o(m_depth_o),
  .m_gid_o(m_gid_o),.m_seq_o(m_seq_o),.m_group_o(m_group_o),.m_payload_o(m_payload_o),
  .m_group_first_o(m_group_first_o),.m_group_last_o(m_group_last_o),.overflow_o(sort_overflow),.busy_o(sort_busy));
 task automatic tick;begin@(posedge clk_i);#1;end endtask
 task automatic send(input integer depth,input integer gid,input integer seq);begin
   while(!s_ready_o)tick();s_depth_i=depth;s_gid_i=gid;s_seq_i=seq;s_payload_i=gid;s_valid_i=1;tick();s_valid_i=0;
 end endtask
 always@(posedge clk_i)if(rst_ni&&m_valid_o&&m_ready_i)begin
   if(m_depth_o!==expect_depth[received]||m_gid_o!==expect_gid[received]||m_group_o!==expect_group[received]
      ||m_payload_o!==expect_gid[received])$fatal(1,"sort[%0d] got d/g/grp=%0d/%0d/%0d exp=%0d/%0d/%0d",
       received,m_depth_o,m_gid_o,m_group_o,expect_depth[received],expect_gid[received],expect_group[received]);
   received<=received+1;
 end
 initial begin integer timeout;
   expect_depth[0]=50;expect_gid[0]=2;expect_group[0]=0;
   expect_depth[1]=150;expect_gid[1]=1;expect_group[1]=1;
   expect_depth[2]=150;expect_gid[2]=5;expect_group[2]=1;
   expect_depth[3]=220;expect_gid[3]=8;expect_group[3]=2;
   expect_depth[4]=250;expect_gid[4]=3;expect_group[4]=2;
   expect_depth[5]=350;expect_gid[5]=4;expect_group[5]=3;
   expect_depth[6]=390;expect_gid[6]=7;expect_group[6]=3;
   repeat(2)tick();rst_ni=1;tick();
   send(250,3,0);send(150,5,1);send(350,4,2);send(50,2,3);send(150,1,4);send(390,7,5);send(220,8,6);
   frame_end_i=1;tick();frame_end_i=0;timeout=0;
   while(received<7&&timeout<100)begin m_ready_i=(timeout[1:0]!=1);tick();timeout=timeout+1;end
   if(received!=7||group_overflow||sort_overflow)$fatal(1,"chain timeout/overflow received=%0d",received);
   tick();$display("PASS: tb_depth_group_sort_chain");$finish;
 end
endmodule
