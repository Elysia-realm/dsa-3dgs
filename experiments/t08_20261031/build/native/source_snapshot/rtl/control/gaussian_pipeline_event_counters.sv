// Named performance-event wrapper. All event inputs are one-cycle pulses;
// sticky status signals must be edge-converted before entering this block.
module gaussian_pipeline_event_counters #(
    parameter int unsigned COUNTER_W=64,
    parameter int unsigned NUM_COUNTERS=10
) (
    input logic clk_i,input logic rst_ni,input logic clear_i,input logic snapshot_i,
    input logic group_accept_i,input logic group_overflow_pulse_i,input logic sort_busy_i,
    input logic projection_busy_i,input logic block_candidate_i,input logic block_terminated_skip_i,
    input logic alpha_issue_i,input logic blend_commit_i,input logic ordered_retire_wait_i,
    input logic mode_switch_i,
    output logic[NUM_COUNTERS*COUNTER_W-1:0]live_flat_o,
    output logic[NUM_COUNTERS*COUNTER_W-1:0]snapshot_flat_o
);
    logic[NUM_COUNTERS-1:0]events;
    initial begin
      if(NUM_COUNTERS!=10)$error("gaussian_pipeline_event_counters requires NUM_COUNTERS=10");
    end
    assign events={mode_switch_i,ordered_retire_wait_i,blend_commit_i,alpha_issue_i,
      block_terminated_skip_i,block_candidate_i,projection_busy_i,sort_busy_i,
      group_overflow_pulse_i,group_accept_i};
    sat_counter_bank #(.NUM_COUNTERS(NUM_COUNTERS),.COUNTER_W(COUNTER_W))u_bank(
      .clk_i(clk_i),.rst_ni(rst_ni),.clear_i(clear_i),.snapshot_i(snapshot_i),
      .increment_i(events),.live_flat_o(live_flat_o),.snapshot_flat_o(snapshot_flat_o));
endmodule
