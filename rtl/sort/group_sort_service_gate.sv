// Epoch-stable service-rate gate between the coarse depth-group buffer and
// the stable in-group sorter.  The physical group/sort budget is represented
// by PHYSICAL_LANES time slots: an active count of N grants N consecutive
// slots per PHYSICAL_LANES-cycle round.  This changes only throughput and
// clock-enable opportunity; record values and ordering are untouched.
module group_sort_service_gate #(
    parameter int unsigned PHYSICAL_LANES = 4,
    parameter int unsigned COUNT_W = PHYSICAL_LANES < 1 ? 1 : $clog2(PHYSICAL_LANES + 1),
    parameter int unsigned SLOT_W = PHYSICAL_LANES <= 1 ? 1 : $clog2(PHYSICAL_LANES)
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [COUNT_W-1:0] cfg_active_lanes_i,
    input  logic s_valid_i,
    output logic s_ready_o,
    output logic m_valid_o,
    input  logic m_ready_i,
    output logic service_grant_o,
    output logic service_stall_o
);
    localparam logic [COUNT_W-1:0] PHYSICAL_COUNT = COUNT_W'(PHYSICAL_LANES);
    logic [SLOT_W-1:0] slot_q;
    logic [COUNT_W-1:0] active_lanes;
    logic advance_slot;

    assign active_lanes = cfg_active_lanes_i > PHYSICAL_COUNT
        ? PHYSICAL_COUNT : cfg_active_lanes_i;
    assign service_grant_o = active_lanes != 0 && COUNT_W'(slot_q) < active_lanes;
    assign m_valid_o = s_valid_i && service_grant_o;
    assign s_ready_o = m_ready_i && service_grant_o;
    assign service_stall_o = s_valid_i && !service_grant_o;

    // A granted valid beat freezes under downstream backpressure, preserving
    // ready/valid stability.  Non-grant slots continue advancing so reduced
    // modes cannot deadlock.  An idle boundary re-phases the next group to 0.
    assign advance_slot = s_valid_i && (!service_grant_o || m_ready_i);
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            slot_q <= '0;
        end else if (!s_valid_i) begin
            slot_q <= '0;
        end else if (advance_slot) begin
            if (slot_q == SLOT_W'(PHYSICAL_LANES - 1)) slot_q <= '0;
            else slot_q <= slot_q + 1'b1;
        end
    end

`ifndef SYNTHESIS
    initial begin
        assert (PHYSICAL_LANES >= 1);
        assert (COUNT_W >= $clog2(PHYSICAL_LANES + 1));
    end
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        m_valid_o && !m_ready_i |=> m_valid_o && service_grant_o);
`endif
endmodule
