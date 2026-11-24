`timescale 1ns/1ps
module tb_gaussian_depth_prepass_shared_mac;
`ifndef TB_PREPASS_CONTEXTS
`define TB_PREPASS_CONTEXTS 4
`endif
  localparam GID_W=8,SEQ_W=8,COORD_W=27,ROT_W=22,PE_W=32,RES_W=65;
  logic clk=0,rst_n=0,frame_start=0,src_valid=0,src_ready,local_ready,shared_ready;
  logic[7:0]gid=0,payload=0;logic signed[26:0]x=0,y=0,z=0,tz=0,nearv=-27'sd60000000,farv=27'sd60000000;
  logic signed[21:0]r20=0,r21=0,r22=22'sd1048576;
  logic lv,sv,lmr,smr;logic signed[26:0]ld,sd;logic[7:0]lg,sg,ls,ss,lp,sp;logic lvis,svis,lov,sov;
  logic req,req_ready,rsp,rsp_ready;logic signed[31:0]lhs,rhs;logic signed[64:0]acc,result;
  logic dummy_ready,dummy_rsp,dummy_less;logic signed[64:0]dummy_result;
  integer compared=0,expected_count=0,cycles=0,grants=0,stall_cycles=0;
  logic[52:0]expected[0:1023];
  logic stress=0,g_active;
  logic[31:0]random_q=32'h159a27ce;
  logic held_output=0,held_request=0;
  logic[52:0]previous_output;
  logic[128:0]previous_request;
  integer full_cycles=0,concurrent_io=0;
  always#5 clk=~clk;
  assign src_ready=local_ready&&shared_ready;
  gaussian_depth_prepass_core #(.GID_W(GID_W),.SEQ_W(SEQ_W),.PAYLOAD_W(8),.COORD_W(COORD_W),.ROT_W(ROT_W))golden(
    .clk_i(clk),.rst_ni(rst_n),.frame_start_i(frame_start),.s_valid_i(src_valid&&shared_ready),.s_ready_o(local_ready),
    .s_gid_i(gid),.s_payload_i(payload),.s_world_x_q16_i(x),.s_world_y_q16_i(y),.s_world_z_q16_i(z),
    .cfg_r20_q20_i(r20),.cfg_r21_q20_i(r21),.cfg_r22_q20_i(r22),.cfg_tz_q16_i(tz),
    .cfg_near_q16_i(nearv),.cfg_far_q16_i(farv),.m_valid_o(lv),.m_ready_i(lmr),
    .m_depth_q16_o(ld),.m_gid_o(lg),.m_seq_o(ls),.m_payload_o(lp),.m_visible_o(lvis),.m_numeric_overflow_o(lov));
  gaussian_depth_prepass_shared_mac #(.GID_W(GID_W),.SEQ_W(SEQ_W),.PAYLOAD_W(8),.COORD_W(COORD_W),
    .ROT_W(ROT_W),.PE_DATA_W(PE_W),.PE_RESULT_W(RES_W),.CONTEXTS(`TB_PREPASS_CONTEXTS))dut(
    .clk_i(clk),.rst_ni(rst_n),.frame_start_i(frame_start),.s_valid_i(src_valid&&local_ready),.s_ready_o(shared_ready),
    .s_gid_i(gid),.s_payload_i(payload),.s_world_x_q16_i(x),.s_world_y_q16_i(y),.s_world_z_q16_i(z),
    .cfg_r20_q20_i(r20),.cfg_r21_q20_i(r21),.cfg_r22_q20_i(r22),.cfg_tz_q16_i(tz),
    .cfg_near_q16_i(nearv),.cfg_far_q16_i(farv),.m_valid_o(sv),.m_ready_i(smr),
    .m_depth_q16_o(sd),.m_gid_o(sg),.m_seq_o(ss),.m_payload_o(sp),.m_visible_o(svis),.m_numeric_overflow_o(sov),
    .pe_req_valid_o(req),.pe_req_ready_i(req_ready),.pe_lhs_o(lhs),.pe_rhs_o(rhs),.pe_acc_o(acc),
    .pe_rsp_valid_i(rsp),.pe_rsp_ready_o(rsp_ready),.pe_result_i(result));
  shared_reconfigurable_pe_slice #(.DATA_W(PE_W),.GID_W(GID_W),.SEQ_W(SEQ_W),.RESULT_W(RES_W))pe(
    .clk_i(clk),.rst_ni(rst_n),.group_weight_i(3'd1),.projection_weight_i(3'd4),.raster_weight_i(3'd1),
    .shared_owner_i(2'd1),.aggressive_clock_gate_i(1'b0),.reconfigure_i(frame_start),
    .g_valid_i(g_active),.g_ready_o(dummy_ready),.g_op_mac_i(1'b0),.g_lhs_i({PE_W{1'b0}}),.g_rhs_i({PE_W{1'b0}}),.g_acc_i({RES_W{1'b0}}),
    .g_lhs_gid_i({GID_W{1'b0}}),.g_rhs_gid_i({GID_W{1'b0}}),.g_lhs_seq_i({SEQ_W{1'b0}}),.g_rhs_seq_i({SEQ_W{1'b0}}),
    .g_rsp_valid_o(dummy_rsp),.g_rsp_ready_i(1'b1),.g_result_o(dummy_result),.g_less_o(dummy_less),
    .p_valid_i(req),.p_ready_o(req_ready),.p_op_mac_i(1'b1),.p_lhs_i(lhs),.p_rhs_i(rhs),.p_acc_i(acc),
    .p_lhs_gid_i({GID_W{1'b0}}),.p_rhs_gid_i({GID_W{1'b0}}),.p_lhs_seq_i({SEQ_W{1'b0}}),.p_rhs_seq_i({SEQ_W{1'b0}}),
    .p_rsp_valid_o(rsp),.p_rsp_ready_i(rsp_ready),.p_result_o(result),.p_less_o(),
    .r_valid_i(1'b0),.r_ready_o(),.r_op_mac_i(1'b0),.r_lhs_i({PE_W{1'b0}}),.r_rhs_i({PE_W{1'b0}}),.r_acc_i({RES_W{1'b0}}),
    .r_lhs_gid_i({GID_W{1'b0}}),.r_rhs_gid_i({GID_W{1'b0}}),.r_lhs_seq_i({SEQ_W{1'b0}}),.r_rhs_seq_i({SEQ_W{1'b0}}),
    .r_rsp_valid_o(),.r_rsp_ready_i(1'b1),.r_result_o(),.r_less_o(),
    .group_grant_pulse_o(),.projection_grant_pulse_o(),.raster_grant_pulse_o(),
    .group_stall_o(),.projection_stall_o(),.raster_stall_o(),.utilization_pulse_o(),
    .clock_enable_o(),.busy_o());
  assign lmr=1'b1;assign smr=!stress||random_q[0]||random_q[1];
  assign g_active=stress&&random_q[2];
  always@(posedge clk)if(rst_n)begin
    if(held_output&&(!sv||previous_output!=={sd,sg,ss,sp,svis,sov}))$fatal(1,"output changed under backpressure");
    if(held_request&&(!req||previous_request!=={lhs,rhs,acc}))$fatal(1,"MAC retry changed under contention");
    held_output<=sv&&!smr;previous_output<={sd,sg,ss,sp,svis,sov};
    held_request<=req&&!req_ready;previous_request<={lhs,rhs,acc};
    if(!shared_ready)full_cycles<=full_cycles+1;
    if(src_valid&&src_ready&&sv&&smr)concurrent_io<=concurrent_io+1;
    random_q<={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
    cycles<=cycles+1;
    if(req&&req_ready)grants<=grants+1;
    if(req&&!req_ready)stall_cycles<=stall_cycles+1;
    if(lv&&lmr)begin expected[expected_count]<={ld,lg,ls,lp,lvis,lov};expected_count<=expected_count+1;end
    if(sv&&smr)begin
      if(compared>=expected_count||expected[compared]!=={sd,sg,ss,sp,svis,sov})
        $fatal(1,"prepass mismatch vector=%0d contexts=%0d",compared,`TB_PREPASS_CONTEXTS);
      compared<=compared+1;
    end
  end
  task automatic tick;begin@(posedge clk);#1;end endtask
  task automatic send(input integer id,input integer xv,input integer yv,input integer zv,
    input integer a,input integer b,input integer c,input integer tv);begin
    while(!src_ready)tick();gid=id;payload=id+8'h40;x=xv;y=yv;z=zv;r20=a;r21=b;r22=c;tz=tv;
    src_valid=1;tick();src_valid=0;
  end endtask
  initial begin integer timeout,start_cycles,burst_cycles,k;
    repeat(2)tick();rst_n=1;frame_start=1;tick();frame_start=0;
    send(1,0,0,131072,0,0,1048576,0);
    send(2,65536,-131072,196608,524288,-262144,786432,32768);
    send(3,-262144,98304,32768,-1048576,524288,262144,-65536);
    send(4,67108863,67108863,67108863,2097151,2097151,2097151,67108863);
    timeout=0;while(compared<4&&timeout<300)begin tick();timeout=timeout+1;end
    if(compared!=4)$fatal(1,"shared prepass equivalence timeout %0d",compared);
    start_cycles=cycles;
    for(k=0;k<64;k=k+1)send(k,k*65536,-k*32768,k*131072,524288,-262144,786432,-65536);
    timeout=0;while(compared<68&&timeout<1000)begin tick();timeout=timeout+1;end
    burst_cycles=cycles-start_cycles;
    if(compared!=68)$fatal(1,"burst timeout");
    if(`TB_PREPASS_CONTEXTS>=3&&burst_cycles>200)$fatal(1,"continuous MAC throughput regression %0d",burst_cycles);
    stress=1;
    for(k=0;k<256;k=k+1)begin
      send(k,$signed(random_q)%67108864,$signed({random_q[15:0],random_q[31:16]})%67108864,
        $signed(random_q^32'h673421ba)%67108864,
        $signed(random_q)%2097152,$signed(random_q^32'hbad53276)%2097152,
        $signed(random_q^32'h1239fe87)%2097152,$signed(random_q^32'hab457296)%67108864);
      if(k%23==0)begin frame_start=1;tick();frame_start=0;end
    end
    timeout=0;while(compared<324&&timeout<10000)begin tick();timeout=timeout+1;end
    if(compared!=324||grants!=972||stall_cycles==0)$fatal(1,"stress incomplete vectors=%0d grants=%0d stalls=%0d",compared,grants,stall_cycles);
    if(full_cycles==0)$fatal(1,"context-full backpressure was not exercised");
    $display("PREPASS_QUEUE contexts=%0d vectors=%0d burst64_cycles=%0d grants=%0d stalls=%0d cycles=%0d full=%0d concurrent_io=%0d",
      `TB_PREPASS_CONTEXTS,compared,burst_cycles,grants,stall_cycles,cycles,full_cycles,concurrent_io);
    $display("PASS: tb_gaussian_depth_prepass_shared_mac");$finish;
  end
endmodule
