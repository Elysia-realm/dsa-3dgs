`timescale 1ns/1ps
module tb_shared_reconfigurable_pe_slice;
  localparam int DATA_W=16,RESULT_W=33;
  logic clk_i=0,rst_ni=0;always#5 clk_i=~clk_i;
  logic[2:0]gw=2,pw=1,rw=1;logic[1:0]owner=0;logic gate=0,reconfigure=0;
  logic gv=0,pv=0,rv=0,gr,pr,rr,gop=0,pop=1,rop=1;
  logic signed[15:0]gl=0,grhs=0,pl=0,prhs=0,rl=0,rrhs=0;
  logic signed[32:0]ga=0,pa=0,ra=0;
  logic[7:0]glg=0,grg=0,plg=0,prg=0,rlg=0,rrg=0;
  logic[7:0]gls=0,grs=0,pls=0,prs=0,rls=0,rrs=0;
  logic grv,prv,rrv;logic grr=1,prr=1,rrr=1;
  logic signed[32:0]gres,pres,rres;logic gless,pless,rless;
  logic gg,pg,rg,gs,ps,rs,util,ce,busy;
  integer grant_count=0;logic capture_grants=0;logic[1:0]grant_order[0:3];
  shared_reconfigurable_pe_slice #(.DATA_W(DATA_W),.GID_W(8),.SEQ_W(8),.RESULT_W(RESULT_W))dut(
    .clk_i(clk_i),.rst_ni(rst_ni),.group_weight_i(gw),.projection_weight_i(pw),.raster_weight_i(rw),
    .shared_owner_i(owner),.aggressive_clock_gate_i(gate),.reconfigure_i(reconfigure),
    .g_valid_i(gv),.g_ready_o(gr),.g_op_mac_i(gop),.g_lhs_i(gl),.g_rhs_i(grhs),.g_acc_i(ga),
    .g_lhs_gid_i(glg),.g_rhs_gid_i(grg),.g_lhs_seq_i(gls),.g_rhs_seq_i(grs),
    .g_rsp_valid_o(grv),.g_rsp_ready_i(grr),.g_result_o(gres),.g_less_o(gless),
    .p_valid_i(pv),.p_ready_o(pr),.p_op_mac_i(pop),.p_lhs_i(pl),.p_rhs_i(prhs),.p_acc_i(pa),
    .p_lhs_gid_i(plg),.p_rhs_gid_i(prg),.p_lhs_seq_i(pls),.p_rhs_seq_i(prs),
    .p_rsp_valid_o(prv),.p_rsp_ready_i(prr),.p_result_o(pres),.p_less_o(pless),
    .r_valid_i(rv),.r_ready_o(rr),.r_op_mac_i(rop),.r_lhs_i(rl),.r_rhs_i(rrhs),.r_acc_i(ra),
    .r_lhs_gid_i(rlg),.r_rhs_gid_i(rrg),.r_lhs_seq_i(rls),.r_rhs_seq_i(rrs),
    .r_rsp_valid_o(rrv),.r_rsp_ready_i(rrr),.r_result_o(rres),.r_less_o(rless),
    .group_grant_pulse_o(gg),.projection_grant_pulse_o(pg),.raster_grant_pulse_o(rg),
    .group_stall_o(gs),.projection_stall_o(ps),.raster_stall_o(rs),
    .utilization_pulse_o(util),.clock_enable_o(ce),.busy_o(busy));
  task automatic tick;begin @(posedge clk_i);#1;end endtask
  always@(posedge clk_i)if(rst_ni&&util&&capture_grants)begin
    if(gg)grant_order[grant_count]<=0;
    else if(pg)grant_order[grant_count]<=1;
    else if(rg)grant_order[grant_count]<=2;
    grant_count<=grant_count+1;
  end
  initial begin integer base;
    repeat(2)tick();rst_ni=1;tick();
    // Owner G receives its two credits first, then P and R each receive one.
    capture_grants=1;gv=1;pv=1;rv=1;gop=1;pop=1;rop=1;
    gl=2;grhs=3;ga=4;pl=-3;prhs=5;pa=2;rl=7;rrhs=8;ra=-1;
    while(grant_count<4)tick();capture_grants=0;gv=0;pv=0;rv=0;tick();
    if(grant_order[0]!==0||grant_order[1]!==0||grant_order[2]!==1||grant_order[3]!==2)
      $fatal(1,"weighted order wrong %0d %0d %0d %0d",grant_order[0],grant_order[1],grant_order[2],grant_order[3]);
    // Exact signed MAC result is carried only to the selected client.
    owner=1;reconfigure=1;tick();reconfigure=0;pv=1;pl=-7;prhs=6;pa=5;tick();pv=0;
    if(!prv||pres!==-37||pless)$fatal(1,"projection MAC result wrong valid=%0d result=%0d",prv,pres);
    tick();
    // Stable compare tie-breaks depth, then gid, then sequence.
    owner=0;reconfigure=1;tick();reconfigure=0;
    gop=0;gl=100;grhs=100;glg=9;grg=9;gls=3;grs=4;gv=1;tick();gv=0;
    if(!grv||!gless||gres!==0)$fatal(1,"stable key compare result wrong");
    tick();
    // Response backpressure freezes the physical result register and every request.
    owner=2;reconfigure=1;tick();reconfigure=0;rrr=0;rv=1;rop=1;rl=11;rrhs=12;ra=1;tick();rv=0;
    if(!rrv||rres!==133)$fatal(1,"raster MAC was not captured");
    pv=1;pl=4;prhs=5;pa=6;base=rres;
    repeat(3)begin tick();if(!rrv||rres!==base||pr||!ps)$fatal(1,"stalled result was not stable");end
    rrr=1;tick();
    if(!prv||pres!==26)$fatal(1,"elastic replacement failed result=%0d",pres);
    pv=0;tick();
    // E-style aggressive gating exposes a quiescent clock-enable boundary.
    gate=1;owner=3;reconfigure=1;tick();reconfigure=0;#1;if(ce||busy)$fatal(1,"idle aggressive gate did not quiesce");
    gv=1;gop=1;gl=1;grhs=2;ga=3;#1;if(!ce)$fatal(1,"request did not wake clock enable");
    tick();gv=0;tick();if(ce)$fatal(1,"clock enable stayed high after drain");
    $display("PASS: tb_shared_reconfigurable_pe_slice");$finish;
  end
endmodule
