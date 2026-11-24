`timescale 1ns/1ps
module tb_stable_group_sorter_shared_compare;
  localparam CAP=8,DW=16,GW=8,SW=8,PW=8,PEW=32,RESW=65;
  logic clk=0,rst_n=0,clear=0,src_valid=0,src_ready,lr,sr,last=0;
  logic signed[DW-1:0]depth=0;logic[GW-1:0]gid=0;logic[SW-1:0]seq=0;logic[1:0]group=0;logic[PW-1:0]payload=0;
  logic lv,sv,sink_ready=1;logic signed[DW-1:0]ld,sd;logic[GW-1:0]lg,sg;logic[SW-1:0]ls,ss;
  logic[1:0]lgrp,sgrp;logic[PW-1:0]lp,sp;logic lfirst,llast,sfirst,slast,lov,sov,lbusy,sbusy;
  logic req,req_ready,rsp,rsp_ready,less;logic signed[31:0]lhs,rhs;logic[GW-1:0]lhg,rhg;logic[SW-1:0]lhsq,rhsq;
  integer compared=0,ggrants=0;
  always#5 clk=~clk;assign src_ready=lr&&sr;
  stable_group_sorter #(.CAPACITY(CAP),.DEPTH_W(DW),.GID_W(GW),.SEQ_W(SW),.GROUP_W(2),.PAYLOAD_W(PW))golden(
    .clk_i(clk),.rst_ni(rst_n),.clear_overflow_i(clear),.s_valid_i(src_valid&&sr),.s_ready_o(lr),
    .s_depth_i(depth),.s_gid_i(gid),.s_seq_i(seq),.s_group_i(group),.s_payload_i(payload),.s_group_last_i(last),
    .m_valid_o(lv),.m_ready_i(sink_ready&&sv),.m_depth_o(ld),.m_gid_o(lg),.m_seq_o(ls),.m_group_o(lgrp),
    .m_payload_o(lp),.m_group_first_o(lfirst),.m_group_last_o(llast),.overflow_o(lov),.busy_o(lbusy));
  stable_group_sorter_shared_compare #(.CAPACITY(CAP),.DEPTH_W(DW),.GID_W(GW),.SEQ_W(SW),
    .GROUP_W(2),.PAYLOAD_W(PW),.PE_DATA_W(PEW))dut(
    .clk_i(clk),.rst_ni(rst_n),.clear_overflow_i(clear),.s_valid_i(src_valid&&lr),.s_ready_o(sr),
    .s_depth_i(depth),.s_gid_i(gid),.s_seq_i(seq),.s_group_i(group),.s_payload_i(payload),.s_group_last_i(last),
    .m_valid_o(sv),.m_ready_i(sink_ready&&lv),.m_depth_o(sd),.m_gid_o(sg),.m_seq_o(ss),.m_group_o(sgrp),
    .m_payload_o(sp),.m_group_first_o(sfirst),.m_group_last_o(slast),.overflow_o(sov),.busy_o(sbusy),
    .pe_req_valid_o(req),.pe_req_ready_i(req_ready),.pe_lhs_o(lhs),.pe_rhs_o(rhs),
    .pe_lhs_gid_o(lhg),.pe_rhs_gid_o(rhg),.pe_lhs_seq_o(lhsq),.pe_rhs_seq_o(rhsq),
    .pe_rsp_valid_i(rsp),.pe_rsp_ready_o(rsp_ready),.pe_less_i(less));
  shared_reconfigurable_pe_slice #(.DATA_W(PEW),.GID_W(GW),.SEQ_W(SW),.RESULT_W(RESW))pe(
    .clk_i(clk),.rst_ni(rst_n),.group_weight_i(3'd4),.projection_weight_i(3'd1),.raster_weight_i(3'd1),
    .shared_owner_i(2'd0),.aggressive_clock_gate_i(1'b0),.reconfigure_i(1'b0),
    .g_valid_i(req),.g_ready_o(req_ready),.g_op_mac_i(1'b0),.g_lhs_i(lhs),.g_rhs_i(rhs),.g_acc_i({RESW{1'b0}}),
    .g_lhs_gid_i(lhg),.g_rhs_gid_i(rhg),.g_lhs_seq_i(lhsq),.g_rhs_seq_i(rhsq),
    .g_rsp_valid_o(rsp),.g_rsp_ready_i(rsp_ready),.g_result_o(),.g_less_o(less),
    .p_valid_i(1'b0),.p_ready_o(),.p_op_mac_i(1'b0),.p_lhs_i({PEW{1'b0}}),.p_rhs_i({PEW{1'b0}}),.p_acc_i({RESW{1'b0}}),
    .p_lhs_gid_i({GW{1'b0}}),.p_rhs_gid_i({GW{1'b0}}),.p_lhs_seq_i({SW{1'b0}}),.p_rhs_seq_i({SW{1'b0}}),
    .p_rsp_valid_o(),.p_rsp_ready_i(1'b1),.p_result_o(),.p_less_o(),
    .r_valid_i(1'b0),.r_ready_o(),.r_op_mac_i(1'b0),.r_lhs_i({PEW{1'b0}}),.r_rhs_i({PEW{1'b0}}),.r_acc_i({RESW{1'b0}}),
    .r_lhs_gid_i({GW{1'b0}}),.r_rhs_gid_i({GW{1'b0}}),.r_lhs_seq_i({SW{1'b0}}),.r_rhs_seq_i({SW{1'b0}}),
    .r_rsp_valid_o(),.r_rsp_ready_i(1'b1),.r_result_o(),.r_less_o(),
    .group_grant_pulse_o(),.projection_grant_pulse_o(),.raster_grant_pulse_o(),
    .group_stall_o(),.projection_stall_o(),.raster_stall_o(),.utilization_pulse_o(),
    .clock_enable_o(),.busy_o());
  always@(posedge clk)if(rst_n&&lv&&sv&&sink_ready)begin
    if({ld,lg,ls,lgrp,lp,lfirst,llast}!=={sd,sg,ss,sgrp,sp,sfirst,slast})
      $fatal(1,"sort mismatch d/g/s/grp=%0d/%0d/%0d/%0d vs %0d/%0d/%0d/%0d",ld,lg,ls,lgrp,sd,sg,ss,sgrp);
    compared<=compared+1;
  end
  always@(posedge clk)if(rst_n&&req&&req_ready)ggrants<=ggrants+1;
  task automatic tick;begin@(posedge clk);#1;end endtask
  task automatic send(input integer d,input integer g,input integer s,input integer grp,input logic glast);begin
    while(!src_ready)tick();depth=d;gid=g;seq=s;group=grp;payload=g+8'h20;last=glast;src_valid=1;
    tick();src_valid=0;last=0;
  end endtask
  initial begin integer timeout;
    repeat(2)tick();rst_n=1;tick();
    send(100,5,0,0,0);send(50,7,1,0,0);send(100,2,2,0,0);send(100,2,3,0,1);
    timeout=0;while(compared<4&&timeout<300)begin sink_ready=(timeout%4!=1);tick();timeout=timeout+1;end
    send(300,9,4,1,0);send(200,4,5,1,0);send(250,8,6,1,1);
    while(compared<7&&timeout<600)begin sink_ready=(timeout%5!=2);tick();timeout=timeout+1;end
    if(compared!=7||lov||sov||ggrants==0)$fatal(1,"shared sort equivalence failed count=%0d grants=%0d",compared,ggrants);
    $display("PASS: tb_stable_group_sorter_shared_compare");$finish;
  end
endmodule
