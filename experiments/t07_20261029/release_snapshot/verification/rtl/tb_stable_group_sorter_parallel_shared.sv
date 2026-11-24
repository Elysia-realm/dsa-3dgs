`timescale 1ns/1ps
`ifndef TB_SHARED_SORT_BINARY_SEARCH
`define TB_SHARED_SORT_BINARY_SEARCH 0
`endif
`ifndef TB_SORT_CAPACITY
`define TB_SORT_CAPACITY 8
`endif
`ifndef TB_SORT_PARALLEL
`define TB_SORT_PARALLEL 1
`endif
`ifndef TB_SORT_SERIAL_FALLBACK
`define TB_SORT_SERIAL_FALLBACK 1
`endif
`ifndef TB_SORT_BATCH_FORWARDING
`define TB_SORT_BATCH_FORWARDING 1
`endif
`ifndef TB_SORT_PHASE_FORWARDING
`define TB_SORT_PHASE_FORWARDING 1
`endif
`ifndef TB_SORT_MONOTONIC_FASTPATH
`define TB_SORT_MONOTONIC_FASTPATH 1
`endif
`ifndef TB_SORT_STABLE_RUN_FASTPATH
`define TB_SORT_STABLE_RUN_FASTPATH 1
`endif
module tb_stable_group_sorter_parallel_shared;
  localparam CAP=`TB_SORT_CAPACITY,DW=16,GW=8,SW=8,PW=8,LANES=4;
  logic clk=0,rst_n=0,clear=0,src_valid=0,lr,sr,last=0;
  logic signed[DW-1:0]depth=0;logic[GW-1:0]gid=0;logic[SW-1:0]seq=0;
  logic[1:0]group=0;logic[PW-1:0]payload=0;logic[2:0]active_lanes=4;
  logic lv,sv,sink_ready;logic signed[DW-1:0]ld,sd;logic[GW-1:0]lg,sg;logic[SW-1:0]ls,ss;
  logic[1:0]lgrp,sgrp;logic[PW-1:0]lp,sp;logic lfirst,llast,sfirst,slast,lov,sov,lbusy,sbusy;
  logic req,req_ready,rsp,rsp_ready,less;
  logic signed[31:0]lhs,rhs;logic[GW-1:0]lhg,rhg;logic[SW-1:0]lhsq,rhsq;
  logic stress=0;logic[31:0]random_q=32'h862aba17;
  logic[31:0]input_random_q=32'h62b531de;
  integer compared=0,cycles=0,grants=0,stalls=0,expected_count=0;
  integer local_compares=0,parallel_batches=0;
  integer serial_groups=0,forwarded_grants=0,forwarded_stalls=0;
  integer phase_grants=0,phase_stalls=0,swap_count=0,phase_count=0,groups_done=0;
  integer case_index=0;
  integer shifts=0,collect_compares=0,fast_groups=0,reverse_groups=0;
  wire[31:0]perf_shared,perf_local,perf_swaps,perf_phases,perf_groups,perf_fallback,perf_phase_grants,perf_phase_stalls;
  wire[31:0]perf_shifts,perf_collect,perf_fast,perf_reverse;
  integer reverse1,reverse4,sorted4,identical4;
  logic held=0;logic[43:0]previous_output;
  logic held_req=0;logic[95:0]previous_req;
  always#5 clk=~clk;
  assign sink_ready=!stress||random_q[0]||random_q[1];
  stable_group_sorter #(.CAPACITY(CAP),.DEPTH_W(DW),.GID_W(GW),.SEQ_W(SW),.GROUP_W(2),.PAYLOAD_W(PW))golden(
    .clk_i(clk),.rst_ni(rst_n),.clear_overflow_i(clear),.s_valid_i(src_valid&&sr),.s_ready_o(lr),
    .s_depth_i(depth),.s_gid_i(gid),.s_seq_i(seq),.s_group_i(group),.s_payload_i(payload),.s_group_last_i(last),
    .m_valid_o(lv),.m_ready_i(sink_ready&&sv),.m_depth_o(ld),.m_gid_o(lg),.m_seq_o(ls),.m_group_o(lgrp),
    .m_payload_o(lp),.m_group_first_o(lfirst),.m_group_last_o(llast),.overflow_o(lov),.busy_o(lbusy));
  generate
    if(`TB_SORT_PARALLEL)begin:g_parallel
      always@(posedge clk)if(rst_n)begin
        if(src_valid&&lr&&sr&&dut.count_q==0&&`TB_SORT_SERIAL_FALLBACK&&active_lanes<=1)serial_groups=serial_groups+1;
        if(req&&!req_ready&&dut.batch_chain)forwarded_stalls=forwarded_stalls+1;
        if(req&&req_ready&&dut.batch_chain)forwarded_grants=forwarded_grants+1;
        if(req&&!req_ready&&dut.phase_chain)phase_stalls=phase_stalls+1;
        if(req&&req_ready&&dut.phase_chain)phase_grants=phase_grants+1;
        if(dut.collect_compare_fire)begin local_compares=local_compares+1;collect_compares=collect_compares+1;end
        if(dut.state_q==dut.SERIAL_INSERT)shifts=shifts+int'(dut.count_q)-int'(dut.insert_q);
        if(sv&&lv&&sink_ready&&slast)begin
          if(dut.fast_emit_q)fast_groups=fast_groups+1;
          if(dut.reverse_emit_q)reverse_groups=reverse_groups+1;
        end
        if(dut.state_q==dut.COMPARE_WAIT&&rsp)begin
          for(integer k=0;k<LANES;k=k+1)if(dut.batch_swap[k])swap_count=swap_count+1;
          if(!dut.more_batch)phase_count=phase_count+1;
        end
        if(dut.state_q==dut.COMPARE_REQ&&dut.base_q+1>=dut.count_q)phase_count=phase_count+1;
        if(req&&req_ready&&!dut.serial_request)begin
        for(integer k=1;k<LANES;k=k+1)
          if(k<int'(dut.lanes_q)&&int'(dut.request_base)+2*k+1<int'(dut.count_q))local_compares=local_compares+1;
        if(dut.lanes_q>1&&int'(dut.request_base)+3<int'(dut.count_q))parallel_batches=parallel_batches+1;
        end
      end
      stable_group_sorter_parallel_shared #(.CAPACITY(CAP),.DEPTH_W(DW),.GID_W(GW),.SEQ_W(SW),
        .GROUP_W(2),.PAYLOAD_W(PW),.COMPARE_LANES(LANES),
        .ENABLE_SERIAL_FALLBACK(`TB_SORT_SERIAL_FALLBACK),.ENABLE_BATCH_FORWARDING(`TB_SORT_BATCH_FORWARDING),
        .ENABLE_PHASE_FORWARDING(`TB_SORT_PHASE_FORWARDING),.ENABLE_MONOTONIC_FASTPATH(`TB_SORT_MONOTONIC_FASTPATH),
        .ENABLE_STABLE_RUN_FASTPATH(`TB_SORT_STABLE_RUN_FASTPATH))dut(
        .clk_i(clk),.rst_ni(rst_n),.clear_overflow_i(clear),.cfg_active_lanes_i(active_lanes),
        .s_valid_i(src_valid&&lr),.s_ready_o(sr),.s_depth_i(depth),.s_gid_i(gid),.s_seq_i(seq),
        .s_group_i(group),.s_payload_i(payload),.s_group_last_i(last),
        .m_valid_o(sv),.m_ready_i(sink_ready&&lv),.m_depth_o(sd),.m_gid_o(sg),.m_seq_o(ss),.m_group_o(sgrp),
        .m_payload_o(sp),.m_group_first_o(sfirst),.m_group_last_o(slast),.overflow_o(sov),.busy_o(sbusy),
        .pe_req_valid_o(req),.pe_req_ready_i(req_ready),.pe_lhs_o(lhs),.pe_rhs_o(rhs),
        .pe_lhs_gid_o(lhg),.pe_rhs_gid_o(rhg),.pe_lhs_seq_o(lhsq),.pe_rhs_seq_o(rhsq),
        .pe_rsp_valid_i(rsp),.pe_rsp_ready_o(rsp_ready),.pe_less_i(less),
        .perf_shared_compares_o(perf_shared),.perf_local_compares_o(perf_local),.perf_swaps_o(perf_swaps),
        .perf_phases_o(perf_phases),.perf_groups_o(perf_groups),.perf_fallback_groups_o(perf_fallback),
        .perf_phase_grants_o(perf_phase_grants),.perf_phase_stalls_o(perf_phase_stalls),
        .perf_shifts_o(perf_shifts),.perf_collect_compares_o(perf_collect),.perf_fast_groups_o(perf_fast),.perf_reverse_groups_o(perf_reverse));
    end else begin:g_serial
      stable_group_sorter_shared_compare #(.CAPACITY(CAP),.DEPTH_W(DW),.GID_W(GW),.SEQ_W(SW),
        .GROUP_W(2),.PAYLOAD_W(PW),.ENABLE_BINARY_SEARCH(`TB_SHARED_SORT_BINARY_SEARCH))dut(
        .clk_i(clk),.rst_ni(rst_n),.clear_overflow_i(clear),
        .s_valid_i(src_valid&&lr),.s_ready_o(sr),.s_depth_i(depth),.s_gid_i(gid),.s_seq_i(seq),
        .s_group_i(group),.s_payload_i(payload),.s_group_last_i(last),
        .m_valid_o(sv),.m_ready_i(sink_ready&&lv),.m_depth_o(sd),.m_gid_o(sg),.m_seq_o(ss),.m_group_o(sgrp),
        .m_payload_o(sp),.m_group_first_o(sfirst),.m_group_last_o(slast),.overflow_o(sov),.busy_o(sbusy),
        .pe_req_valid_o(req),.pe_req_ready_i(req_ready),.pe_lhs_o(lhs),.pe_rhs_o(rhs),
        .pe_lhs_gid_o(lhg),.pe_rhs_gid_o(rhg),.pe_lhs_seq_o(lhsq),.pe_rhs_seq_o(rhsq),
        .pe_rsp_valid_i(rsp),.pe_rsp_ready_o(rsp_ready),.pe_less_i(less));
    end
  endgenerate
  shared_reconfigurable_pe_slice #(.DATA_W(32),.GID_W(GW),.SEQ_W(SW),.RESULT_W(65))pe(
    .clk_i(clk),.rst_ni(rst_n),.group_weight_i(3'd2),.projection_weight_i(3'd4),.raster_weight_i(3'd1),
    .shared_owner_i(2'd1),.aggressive_clock_gate_i(1'b0),.reconfigure_i(1'b0),
    .g_valid_i(req),.g_ready_o(req_ready),.g_op_mac_i(1'b0),.g_lhs_i(lhs),.g_rhs_i(rhs),.g_acc_i(65'd0),
    .g_lhs_gid_i(lhg),.g_rhs_gid_i(rhg),.g_lhs_seq_i(lhsq),.g_rhs_seq_i(rhsq),
    .g_rsp_valid_o(rsp),.g_rsp_ready_i(rsp_ready),.g_result_o(),.g_less_o(less),
    .p_valid_i(stress&&random_q[2]),.p_ready_o(),.p_op_mac_i(1'b1),.p_lhs_i(32'd3),.p_rhs_i(32'd7),.p_acc_i(65'd0),
    .p_lhs_gid_i(8'd0),.p_rhs_gid_i(8'd0),.p_lhs_seq_i(8'd0),.p_rhs_seq_i(8'd0),
    .p_rsp_valid_o(),.p_rsp_ready_i(1'b1),.p_result_o(),.p_less_o(),
    .r_valid_i(1'b0),.r_ready_o(),.r_op_mac_i(1'b0),.r_lhs_i(32'd0),.r_rhs_i(32'd0),.r_acc_i(65'd0),
    .r_lhs_gid_i(8'd0),.r_rhs_gid_i(8'd0),.r_lhs_seq_i(8'd0),.r_rhs_seq_i(8'd0),
    .r_rsp_valid_o(),.r_rsp_ready_i(1'b1),.r_result_o(),.r_less_o(),
    .group_grant_pulse_o(),.projection_grant_pulse_o(),.raster_grant_pulse_o(),
    .group_stall_o(),.projection_stall_o(),.raster_stall_o(),.utilization_pulse_o(),.clock_enable_o(),.busy_o());
  always@(posedge clk)if(rst_n)begin
    cycles<=cycles+1;random_q<={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
    if(src_valid&&lr&&sr)input_random_q<={input_random_q[30:0],input_random_q[31]^input_random_q[21]^input_random_q[1]^input_random_q[0]};
    if(req&&req_ready)grants<=grants+1;
    if(req&&!req_ready)stalls<=stalls+1;
    if(held&&(!sv||previous_output!=={sd,sg,ss,sgrp,sp,sfirst,slast}))$fatal(1,"stalled output changed");
    held<=sv&&!(sink_ready&&lv);previous_output<={sd,sg,ss,sgrp,sp,sfirst,slast};
    if(held_req&&(!req||previous_req!=={lhs,rhs,lhg,rhg,lhsq,rhsq}))$fatal(1,"stalled shared request changed");
    held_req<=req&&!req_ready;previous_req<={lhs,rhs,lhg,rhg,lhsq,rhsq};
    if(lv&&sv&&sink_ready)begin
      if({ld,lg,ls,lgrp,lp,lfirst,llast}!=={sd,sg,ss,sgrp,sp,sfirst,slast})
        $fatal(1,"parallel sort mismatch vector=%0d cap=%0d expected=%h actual=%h",compared,CAP,
          {ld,lg,ls,lgrp,lp,lfirst,llast},{sd,sg,ss,sgrp,sp,sfirst,slast});
      compared<=compared+1;
      if(slast)groups_done=groups_done+1;
    end
  end
  task automatic tick;begin@(posedge clk);#1;end endtask
  task automatic run_group(input integer n,kind,budget,grp,output integer elapsed);
    integer i,start_cycle,start_grants,target,timeout;
    begin
      start_cycle=cycles;start_grants=grants;target=compared+(n>CAP?CAP:n);active_lanes=budget;
      for(i=0;i<n;i=i+1)begin
        while(!(lr&&sr))tick();
        case(kind)
          0:begin depth=n-i;gid=i;seq=i;end
          1:begin depth=i;gid=i;seq=i;end
          2:begin depth=17;gid=3;seq=4;end
          3:begin depth=(i%2)?-32768:32767;gid=n-i;seq=i;end
          5:begin depth=i==0?0:((i%2)?i+1:i-1);gid=i;seq=i;end
          7:begin depth=i==n-2?n-1:(i==n-1?n-2:i);gid=i;seq=i;end
          8:begin depth=0;gid=(n-i)%3;seq=(n-i)%2;end
          10:begin depth=(n-i)/2;gid=3;seq=4;end
          11:begin depth=i/2;gid=3;seq=4;end
          12:begin depth=i==n-1?n+2:n-i;gid=3;seq=4;end
          13:begin depth=i<CAP?CAP-i:100+i;gid=i;seq=i;end
          14:begin depth=(n-i)/3;gid=3;seq=4;end
          15:begin depth=0;gid=(n-i)/3;seq=4;end
          16:begin depth=-32768;gid=3;seq=(n-i)/3;end
          17:begin depth=i==n-1?n/2:n-i;gid=3;seq=4;end
          18:begin depth=i==n-1?n/4:(n-i)/2;gid=3;seq=4;end
          default:begin depth=$signed(input_random_q[15:0])%7;gid=input_random_q[19:16]%4;seq=input_random_q[23:20]%4;end
        endcase
        payload=i;group=grp;last=i==n-1;src_valid=1;tick();src_valid=0;last=0;
        if(kind==6&&i==0)active_lanes=budget==1?4:1;
      end
      // Changes after acceptance must not affect a partially sorted group.
      active_lanes=budget==1?4:1;
      timeout=0;while(compared<target&&timeout<20000)begin tick();timeout=timeout+1;end
      if(compared!=target||lbusy||sbusy)$fatal(1,"sort drain timeout");
      if(lov!==(n>CAP)||sov!==(n>CAP))$fatal(1,"overflow contract mismatch");
      elapsed=cycles-start_cycle;expected_count=expected_count+(n>CAP?CAP:n);
      $display("SORT_CASE index=%0d n=%0d kind=%0d budget=%0d stress=%0d cycles=%0d grants=%0d",case_index,n,kind,budget,stress,elapsed,grants-start_grants);
      case_index=case_index+1;
      clear=1;tick();clear=0;if(lov||sov)$fatal(1,"overflow clear failed");
    end
  endtask
  initial begin integer k,n,dummy,extremes;
    repeat(2)tick();rst_n=1;tick();
    run_group(CAP,0,1,0,reverse1);run_group(CAP,0,4,0,reverse4);
    run_group(CAP,1,4,1,sorted4);run_group(CAP,2,4,2,identical4);run_group(CAP,3,4,3,extremes);
    // Even pairs ordered but odd boundary inverted: one quiet phase is NOT
    // sufficient evidence for convergence (e.g. 0,2,1,4,3,...).
    run_group(CAP,5,4,0,dummy);
    run_group(CAP,6,1,1,dummy);run_group(CAP,6,4,2,dummy);
    run_group(CAP,0,2,0,dummy);run_group(CAP,1,2,1,dummy);
    run_group(CAP,7,4,2,dummy);run_group(CAP,8,4,3,dummy);
    for(n=1;n<=CAP;n=n+1)run_group(n,0,4,n%4,dummy);
    run_group(CAP,10,2,0,dummy);run_group(CAP,10,4,1,dummy);
    run_group(CAP,11,4,2,dummy);run_group(CAP,12,4,3,dummy);
    run_group(CAP+3,13,2,0,dummy);
    run_group(CAP,17,2,0,dummy);run_group(CAP,12,2,1,dummy);
    run_group(CAP,17,4,2,dummy);run_group(CAP,18,2,3,dummy);
    for(n=1;n<=CAP;n=n+1)begin
      run_group(n,14,2,0,dummy);run_group(n,15,4,1,dummy);run_group(n,16,4,2,dummy);
    end
    stress=1;
    run_group(CAP,14,2,0,dummy);run_group(CAP,15,4,1,dummy);run_group(CAP,16,4,2,dummy);
    run_group(CAP+3,14,4,3,dummy);
    run_group(CAP,17,2,0,dummy);run_group(CAP,18,4,1,dummy);
    stress=1;
    for(k=0;k<512;k=k+1)begin n=1+input_random_q[15:8]%CAP;run_group(n,4,1<<(k%3),k%4,dummy);end
    run_group(CAP+3,4,4,0,dummy);
    if(compared!=expected_count||(CAP>1&&(grants==0||stalls==0)))$fatal(1,"incomplete stress coverage");
    if(`TB_SORT_PARALLEL&&CAP>=4&&(local_compares==0||parallel_batches==0))$fatal(1,"local parallel compare work not observed");
    if(`TB_SORT_PARALLEL&&(perf_shared!==grants||perf_local!==local_compares||perf_swaps!==swap_count||perf_phases!==phase_count||
      perf_groups!==groups_done||perf_fallback!==serial_groups||perf_phase_grants!==phase_grants||perf_phase_stalls!==phase_stalls||
      perf_shifts!==shifts||perf_collect!==collect_compares||perf_fast!==fast_groups||perf_reverse!==reverse_groups))
      $fatal(1,"hardware work counters disagree with monitor");
    if(`TB_SORT_PARALLEL&&`TB_SORT_PHASE_FORWARDING&&CAP>=3&&(phase_grants==0||phase_stalls==0))$fatal(1,"phase retry coverage absent");
    $display("SORT_ABLATION parallel=%0d fallback=%0d forwarding=%0d phase_forwarding=%0d monotonic=%0d capacity=%0d groups=%0d vectors=%0d reverse1=%0d reverse4=%0d sorted4=%0d identical4=%0d grants=%0d stalls=%0d cycles=%0d local_compares=%0d parallel_batches=%0d serial_groups=%0d forwarded_grants=%0d forwarded_stalls=%0d phase_grants=%0d phase_stalls=%0d swaps=%0d phases=%0d shifts=%0d collect_compares=%0d fast_groups=%0d reverse_groups=%0d",
      `TB_SORT_PARALLEL,`TB_SORT_SERIAL_FALLBACK,`TB_SORT_BATCH_FORWARDING,`TB_SORT_PHASE_FORWARDING,`TB_SORT_MONOTONIC_FASTPATH,CAP,groups_done,compared,reverse1,reverse4,sorted4,identical4,grants,stalls,cycles,
      local_compares,parallel_batches,serial_groups,forwarded_grants,forwarded_stalls,phase_grants,phase_stalls,swap_count,phase_count,shifts,collect_compares,fast_groups,reverse_groups);
    if(`TB_SORT_PARALLEL)begin
      rst_n=0;repeat(2)tick();
      if({perf_shared,perf_local,perf_swaps,perf_phases,perf_groups,perf_fallback,perf_phase_grants,perf_phase_stalls,
        perf_shifts,perf_collect,perf_fast,perf_reverse}!==384'd0)$fatal(1,"work counters reset failed");
    end
    $display("PASS: tb_stable_group_sorter_parallel_shared");$finish;
  end
endmodule
