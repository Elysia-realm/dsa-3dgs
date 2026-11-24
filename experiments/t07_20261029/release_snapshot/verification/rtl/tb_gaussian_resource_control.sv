`timescale 1ns/1ps
module tb_gaussian_resource_control;
  logic clk_i=0,rst_ni=0,clear_i=0,snapshot_i=0;logic[1:0]active_mode_i=0;
  logic[2:0]group_active,projection_active,sh_active,raster_active;
  logic[2:0]group_weight,projection_weight,raster_weight;logic[1:0]owner;logic gate;
  logic[1:0]odd_group_active,odd_sh_active;
  logic[2:0]odd_projection_active,odd_raster_active;
  logic[2:0]odd_group_weight,odd_projection_weight,odd_raster_weight;logic[1:0]odd_owner;logic odd_gate;
  logic group_accept=0,group_overflow=0,sort_busy=0,projection_busy=0,block_candidate=0,block_skip=0;
  logic alpha_issue=0,blend_commit=0,retire_wait=0,mode_switch=0;logic[79:0]live,snapshot;
  always#5 clk_i=~clk_i;
  gaussian_resource_mode_table #(.GROUP_LANES(4),.PROJECTION_LANES(4),.SH_LANES(4),.RASTER_LANES(4))u_mode(
    .active_mode_i(active_mode_i),.group_active_lanes_o(group_active),.projection_active_lanes_o(projection_active),
    .sh_active_lanes_o(sh_active),.raster_active_lanes_o(raster_active),.group_weight_o(group_weight),
    .projection_weight_o(projection_weight),.raster_weight_o(raster_weight),.shared_math_owner_o(owner),
    .aggressive_clock_gate_o(gate));
  // Non-power-of-two and asymmetric physical lane counts exercise the generic
  // count widths and the ceil-half policy used by epoch reconfiguration.
  gaussian_resource_mode_table #(.GROUP_LANES(3),.PROJECTION_LANES(5),.SH_LANES(2),.RASTER_LANES(7))u_odd_mode(
    .active_mode_i(active_mode_i),.group_active_lanes_o(odd_group_active),
    .projection_active_lanes_o(odd_projection_active),.sh_active_lanes_o(odd_sh_active),
    .raster_active_lanes_o(odd_raster_active),.group_weight_o(odd_group_weight),
    .projection_weight_o(odd_projection_weight),.raster_weight_o(odd_raster_weight),
    .shared_math_owner_o(odd_owner),.aggressive_clock_gate_o(odd_gate));
  gaussian_pipeline_event_counters #(.COUNTER_W(8))u_count(
    .clk_i(clk_i),.rst_ni(rst_ni),.clear_i(clear_i),.snapshot_i(snapshot_i),.group_accept_i(group_accept),
    .group_overflow_pulse_i(group_overflow),.sort_busy_i(sort_busy),.projection_busy_i(projection_busy),
    .block_candidate_i(block_candidate),.block_terminated_skip_i(block_skip),.alpha_issue_i(alpha_issue),
    .blend_commit_i(blend_commit),.ordered_retire_wait_i(retire_wait),.mode_switch_i(mode_switch),
    .live_flat_o(live),.snapshot_flat_o(snapshot));
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic check_mode(input integer mode,input integer g,input integer p,input integer sh,input integer r,
      input integer wg,input integer wp,input integer wr,input logic gated);begin
    active_mode_i=mode;#1;
    if(group_active!==g||projection_active!==p||sh_active!==sh||raster_active!==r||
       group_weight!==wg||projection_weight!==wp||raster_weight!==wr||owner!==mode||gate!==gated)
      $fatal(1,"mode %0d table mismatch",mode);
  end endtask
  task automatic check_odd_mode(input integer mode,input integer g,input integer p,input integer sh,input integer r,
      input integer wg,input integer wp,input integer wr,input logic gated);begin
    active_mode_i=mode;#1;
    if(odd_group_active!==g||odd_projection_active!==p||odd_sh_active!==sh||odd_raster_active!==r||
       odd_group_weight!==wg||odd_projection_weight!==wp||odd_raster_weight!==wr||odd_owner!==mode||odd_gate!==gated)
      $fatal(1,"asymmetric mode %0d table mismatch",mode);
  end endtask
  initial begin
    check_mode(0,4,2,2,2,4,2,1,0);check_mode(1,2,4,4,2,1,4,2,0);
    check_mode(2,2,2,2,4,1,2,4,0);check_mode(3,1,1,1,1,1,1,1,1);
    check_odd_mode(0,3,3,1,4,4,2,1,0);check_odd_mode(1,2,5,2,4,1,4,2,0);
    check_odd_mode(2,2,3,1,7,1,2,4,0);check_odd_mode(3,1,1,1,1,1,1,1,1);
    repeat(2)tick();rst_ni=1;tick();
    group_accept=1;sort_busy=1;projection_busy=1;retire_wait=1;tick();
    group_accept=0;sort_busy=0;projection_busy=0;retire_wait=0;
    block_candidate=1;block_skip=1;alpha_issue=1;blend_commit=1;mode_switch=1;tick();
    block_candidate=0;block_skip=0;alpha_issue=0;blend_commit=0;mode_switch=0;
    if(live[7:0]!=1||live[23:16]!=1||live[31:24]!=1||live[47:40]!=1||live[55:48]!=1||
       live[63:56]!=1||live[71:64]!=1||live[79:72]!=1)$fatal(1,"event counter mapping mismatch");
    snapshot_i=1;tick();snapshot_i=0;
    if(snapshot!==live)$fatal(1,"counter snapshot mismatch");
    clear_i=1;tick();clear_i=0;if(live!='0)$fatal(1,"counter clear mismatch");
    $display("PASS: tb_gaussian_resource_control");$finish;
  end
endmodule
