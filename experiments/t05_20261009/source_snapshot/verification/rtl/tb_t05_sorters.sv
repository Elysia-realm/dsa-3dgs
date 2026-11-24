`timescale 1ns/1ps
`ifndef T05_K
`define T05_K 8
`endif
`ifndef T05_KIND
`define T05_KIND 0
`endif
// KIND: 0 BSU, 1 shared insertion, 2 shared Odd-Even (fastpaths disabled).
module tb_t05_sorters;
  localparam K=`T05_K;
  logic clk=0,rst=0;always #5 clk=~clk;
  logic svalid=0,sready,empty=0,last=0;logic signed[15:0]depth=0;
  logic[7:0]gid=0,seq=0;logic[15:0]payload=0;logic[1:0]group_id=0;
  logic[2:0]lanes=4;logic mvalid,mready;logic signed[15:0]md;logic[7:0]mg,ms;
  logic[15:0]mp;logic[1:0]mgroup;logic first,mlast,busy,overflow,clear=0,done;
  logic req,req_ready,rsp,rsp_ready,less;logic signed[31:0]lhs,rhs;
  logic[7:0]lg,rg,ls,rs;
  logic[31:0]shared_count,local_count,swaps,phases,groups,stalls;
  logic[31:0]rng=32'h81253476;logic stress=0;
  logic[2:0]gw,pw,rw;logic[1:0]owner=0;
  logic pvalid,rvalid,pready,rready,presponse,rresponse;
  logic signed[64:0]presult,rresult;logic gg,pg,rgrant;
  integer pcount=0,rcount=0,gcount=0,cycle=0,waitg=0,waitp=0,waitr=0;
  integer checked=0,total_expected,group_tests,ptr=0,n,timeout,case_start,case_cycles;
  logic[63:0]vectors[0:32767],expected[0:32767];logic checking=1;
  string input_path,expected_path;
  logic held=0;logic[53:0]held_data;
  assign mready=!stress||rng[0]||rng[1];
  assign pvalid=stress;assign rvalid=stress;
  always_comb begin
    gw=1;pw=1;rw=1;
    case(owner)0:begin gw=4;pw=2;end 1:begin pw=4;rw=2;end 2:begin rw=4;pw=2;end default:begin end endcase
  end
  generate if(`T05_KIND==0)begin:bsu
    bitonic_group_sorter_shared #(.CAPACITY(K),.DEPTH_W(16),.GID_W(8),.SEQ_W(8),.PAYLOAD_W(16))dut(
      .clk_i(clk),.rst_ni(rst),.clear_overflow_i(clear),.cfg_active_lanes_i(lanes),
      .s_valid_i(svalid),.s_ready_o(sready),.s_empty_i(empty),.s_depth_i(depth),.s_gid_i(gid),.s_seq_i(seq),
      .s_group_i(group_id),.s_payload_i(payload),.s_group_last_i(last),
      .m_valid_o(mvalid),.m_ready_i(mready),.m_depth_o(md),.m_gid_o(mg),.m_seq_o(ms),.m_group_o(mgroup),
      .m_payload_o(mp),.m_group_first_o(first),.m_group_last_o(mlast),.overflow_o(overflow),.busy_o(busy),.subset_done_o(done),
      .pe_req_valid_o(req),.pe_req_ready_i(req_ready),.pe_lhs_o(lhs),.pe_rhs_o(rhs),
      .pe_lhs_gid_o(lg),.pe_rhs_gid_o(rg),.pe_lhs_seq_o(ls),.pe_rhs_seq_o(rs),
      .pe_rsp_valid_i(rsp),.pe_rsp_ready_o(rsp_ready),.pe_less_i(less),
      .perf_shared_compares_o(shared_count),.perf_local_compares_o(local_count),.perf_swaps_o(swaps),
      .perf_phases_o(phases),.perf_groups_o(groups),.perf_stalls_o(stalls));
  end else if(`T05_KIND==1)begin:serial
    stable_group_sorter_shared_compare #(.CAPACITY(K),.DEPTH_W(16),.GID_W(8),.SEQ_W(8),.PAYLOAD_W(16))dut(
      .clk_i(clk),.rst_ni(rst),.clear_overflow_i(clear),
      .s_valid_i(svalid),.s_ready_o(sready),.s_depth_i(depth),.s_gid_i(gid),.s_seq_i(seq),
      .s_group_i(group_id),.s_payload_i(payload),.s_group_last_i(last),
      .m_valid_o(mvalid),.m_ready_i(mready),.m_depth_o(md),.m_gid_o(mg),.m_seq_o(ms),.m_group_o(mgroup),
      .m_payload_o(mp),.m_group_first_o(first),.m_group_last_o(mlast),.overflow_o(overflow),.busy_o(busy),
      .pe_req_valid_o(req),.pe_req_ready_i(req_ready),.pe_lhs_o(lhs),.pe_rhs_o(rhs),
      .pe_lhs_gid_o(lg),.pe_rhs_gid_o(rg),.pe_lhs_seq_o(ls),.pe_rhs_seq_o(rs),
      .pe_rsp_valid_i(rsp),.pe_rsp_ready_o(rsp_ready),.pe_less_i(less));
  end else begin:odd
    stable_group_sorter_parallel_shared #(.CAPACITY(K),.DEPTH_W(16),.GID_W(8),.SEQ_W(8),.PAYLOAD_W(16),
      .COMPARE_LANES(4),.ENABLE_SERIAL_FALLBACK(0),.ENABLE_BATCH_FORWARDING(0),.ENABLE_PHASE_FORWARDING(0),
      .ENABLE_MONOTONIC_FASTPATH(0),.ENABLE_STABLE_RUN_FASTPATH(0))dut(
      .clk_i(clk),.rst_ni(rst),.clear_overflow_i(clear),.cfg_active_lanes_i(lanes),
      .s_valid_i(svalid),.s_ready_o(sready),.s_depth_i(depth),.s_gid_i(gid),.s_seq_i(seq),
      .s_group_i(group_id),.s_payload_i(payload),.s_group_last_i(last),
      .m_valid_o(mvalid),.m_ready_i(mready),.m_depth_o(md),.m_gid_o(mg),.m_seq_o(ms),.m_group_o(mgroup),
      .m_payload_o(mp),.m_group_first_o(first),.m_group_last_o(mlast),.overflow_o(overflow),.busy_o(busy),
      .pe_req_valid_o(req),.pe_req_ready_i(req_ready),.pe_lhs_o(lhs),.pe_rhs_o(rhs),
      .pe_lhs_gid_o(lg),.pe_rhs_gid_o(rg),.pe_lhs_seq_o(ls),.pe_rhs_seq_o(rs),
      .pe_rsp_valid_i(rsp),.pe_rsp_ready_o(rsp_ready),.pe_less_i(less),
      .perf_shared_compares_o(shared_count),.perf_local_compares_o(local_count),.perf_swaps_o(swaps),
      .perf_phases_o(phases),.perf_groups_o(groups));
  end endgenerate
  shared_reconfigurable_pe_slice #(.GID_W(8),.SEQ_W(8))pe(
    .clk_i(clk),.rst_ni(rst),.group_weight_i(gw),.projection_weight_i(pw),.raster_weight_i(rw),
    .shared_owner_i(owner),.aggressive_clock_gate_i(1'b0),.reconfigure_i(1'b0),
    .g_valid_i(req),.g_ready_o(req_ready),.g_op_mac_i(1'b0),.g_lhs_i(lhs),.g_rhs_i(rhs),.g_acc_i(65'd0),
    .g_lhs_gid_i(lg),.g_rhs_gid_i(rg),.g_lhs_seq_i(ls),.g_rhs_seq_i(rs),
    .g_rsp_valid_o(rsp),.g_rsp_ready_i(rsp_ready),.g_less_o(less),
    .p_valid_i(pvalid),.p_ready_o(pready),.p_op_mac_i(1'b1),.p_lhs_i(32'sd3),.p_rhs_i(32'sd7),.p_acc_i(65'sd2),
    .p_lhs_gid_i(8'd0),.p_rhs_gid_i(8'd0),.p_lhs_seq_i(8'd0),.p_rhs_seq_i(8'd0),
    .p_rsp_valid_o(presponse),.p_rsp_ready_i(rng[2]||rng[3]),.p_result_o(presult),
    .r_valid_i(rvalid),.r_ready_o(rready),.r_op_mac_i(1'b1),.r_lhs_i(-32'sd2),.r_rhs_i(32'sd9),.r_acc_i(65'sd5),
    .r_lhs_gid_i(8'd0),.r_rhs_gid_i(8'd0),.r_lhs_seq_i(8'd0),.r_rhs_seq_i(8'd0),
    .r_rsp_valid_o(rresponse),.r_rsp_ready_i(rng[4]||rng[5]),.r_result_o(rresult),
    .group_grant_pulse_o(gg),.projection_grant_pulse_o(pg),.raster_grant_pulse_o(rgrant));
  always@(posedge clk)if(rst)begin
    cycle<=cycle+1;rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
    if(gg)gcount<=gcount+1;if(pg)pcount<=pcount+1;if(rgrant)rcount<=rcount+1;
    waitg<=req&&!req_ready?waitg+1:0;waitp<=pvalid&&!pready?waitp+1:0;waitr<=rvalid&&!rready?waitr+1:0;
    if(waitg>100||waitp>100||waitr>100)$fatal(1,"shared client starvation");
    if(presponse&&presult!=23)$fatal(1,"P response corrupted");
    if(rresponse&&rresult!=-13)$fatal(1,"R response corrupted");
    if(held&&(!mvalid||held_data!={md,mg,ms,mp,mgroup,first,mlast}))$fatal(1,"output changed under backpressure");
    held<=mvalid&&!mready;held_data<={md,mg,ms,mp,mgroup,first,mlast};
    if(mvalid&&mready&&checking)begin
      if(checked>=total_expected||{12'd0,md,mg,ms,mp,mgroup,first,mlast}!==expected[checked])
        $fatal(1,"sort mismatch index=%0d actual=%h expected=%h",checked,{12'd0,md,mg,ms,mp,mgroup,first,mlast},expected[checked]);
      checked<=checked+1;
    end
  end
  task tick;begin @(posedge clk);#1;end endtask
  task send(input logic[47:0]value,input logic end_group,input logic is_empty);
    begin
      @(negedge clk);{depth,gid,seq,payload}=value;last=end_group;empty=is_empty;svalid=1;
      timeout=0;#1;
      while(!sready)begin @(negedge clk);#1;timeout=timeout+1;if(timeout>10000)$fatal(1,"input timeout");end
      tick();
      @(negedge clk);svalid=0;empty=0;
    end
  endtask
  initial begin
    if(!$value$plusargs("INPUT=%s",input_path)||!$value$plusargs("EXPECTED=%s",expected_path)||
       !$value$plusargs("GROUPS=%d",group_tests)||!$value$plusargs("OUTPUTS=%d",total_expected))$fatal(1,"missing vector paths/counts");
    $readmemh(input_path,vectors);$readmemh(expected_path,expected);
    repeat(3)tick();@(negedge clk);rst=1;
    for(integer c=0;c<group_tests;c=c+1)begin
      n=int'(vectors[ptr][15:0]);lanes=vectors[ptr][18:16];group_id=vectors[ptr][25:24];
      stress=vectors[ptr][32];owner=vectors[ptr][34:33];ptr=ptr+1;case_start=cycle;
      if(n==0)begin if(`T05_KIND==0)send(0,1,1);end
      else for(integer i=0;i<n;i=i+1)begin send(vectors[ptr][47:0],i==n-1,0);ptr=ptr+1;end
      timeout=0;while(busy)begin tick();timeout=timeout+1;if(timeout>20000)$fatal(1,"output timeout");end
      tick();if(overflow)$fatal(1,"unexpected overflow");
      $display("T05_CASE kind=%0d k=%0d case=%0d n=%0d lanes=%0d stress=%0d cycles=%0d",`T05_KIND,K,c,n,lanes,stress,cycle-case_start);
    end
    if(checked!=total_expected)$fatal(1,"lost output %0d/%0d",checked,total_expected);
    checking=0;stress=0;lanes=4;
    if(`T05_KIND==0)begin
      for(integer i=0;i<K+1;i=i+1)send(48'(i),i==K,0);
      tick();if(!overflow||busy||mvalid)$fatal(1,"oversized subset not rejected atomically");
      clear=1;tick();clear=0;send(48'h000100020003,1,0);
      while(busy)tick();if(overflow)$fatal(1,"overflow recovery failed");
    end
    if(gcount==0||pcount==0||rcount==0)$fatal(1,"G/P/R paths were not all exercised");
    $display("PASS: tb_t05_sorters kind=%0d k=%0d outputs=%0d G=%0d P=%0d R=%0d",`T05_KIND,K,checked,gcount,pcount,rcount);$finish;
  end
endmodule
