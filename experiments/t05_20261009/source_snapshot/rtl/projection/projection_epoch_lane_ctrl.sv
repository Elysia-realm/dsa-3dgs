// Decode the shared G/P/R/E epoch mode into the projection-lane allocation.
// G/P/R/E select half/all/half/one projection lanes. The physical upper bound
// never changes; disabled lanes are clock-gating candidates.
module projection_epoch_lane_ctrl #(
    parameter int unsigned LANES=4,
    parameter int unsigned MODE_W=2,
    parameter int unsigned EPOCH_W=16,
    parameter int unsigned COUNT_W=$clog2(LANES+1)
) (
    input  logic                   clk_i,
    input  logic                   rst_ni,
    input  logic                   shadow_we_i,
    input  logic [MODE_W-1:0]      shadow_mode_i,
    input  logic                   commit_i,
    input  logic                   epoch_boundary_i,
    input  logic                   lane_array_idle_i,
    output logic [MODE_W-1:0]      shadow_mode_o,
    output logic [MODE_W-1:0]      active_mode_o,
    output logic [COUNT_W-1:0]     active_lanes_o,
    output logic [EPOCH_W-1:0]     epoch_id_o,
    output logic                   commit_pending_o,
    output logic                   commit_pulse_o,
    output logic                   commit_overrun_o
);
    localparam int unsigned HALF=(LANES+1)/2;
    cfg_epoch_ctrl #(.MODE_W(MODE_W),.EPOCH_W(EPOCH_W))u_epoch_ctrl(
      .clk_i(clk_i),.rst_ni(rst_ni),.shadow_we_i(shadow_we_i),
      .shadow_mode_i(shadow_mode_i),.commit_i(commit_i),
      .epoch_boundary_i(epoch_boundary_i),.affected_empty_i(lane_array_idle_i),
      .shadow_mode_o(shadow_mode_o),.active_mode_o(active_mode_o),
      .epoch_id_o(epoch_id_o),.commit_pending_o(commit_pending_o),
      .commit_pulse_o(commit_pulse_o),.commit_overrun_o(commit_overrun_o));
    always_comb begin
      case(active_mode_o)
        2'd0:active_lanes_o=HALF;
        2'd1:active_lanes_o=LANES;
        2'd2:active_lanes_o=HALF;
        default:active_lanes_o={{(COUNT_W-1){1'b0}},1'b1};
      endcase
    end
endmodule
