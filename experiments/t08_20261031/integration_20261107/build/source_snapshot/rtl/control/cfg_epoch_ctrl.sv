// Shadow/active configuration controller. A commit becomes visible atomically
// only at a declared epoch boundary after all affected state has drained.
module cfg_epoch_ctrl #(
    parameter int unsigned MODE_W  = 2,
    parameter int unsigned EPOCH_W = 16,
    parameter logic [MODE_W-1:0] RESET_MODE = '0
) (
    input  logic                 clk_i,
    input  logic                 rst_ni,
    input  logic                 shadow_we_i,
    input  logic [MODE_W-1:0]    shadow_mode_i,
    input  logic                 commit_i,
    input  logic                 epoch_boundary_i,
    input  logic                 affected_empty_i,
    output logic [MODE_W-1:0]    shadow_mode_o,
    output logic [MODE_W-1:0]    active_mode_o,
    output logic [EPOCH_W-1:0]   epoch_id_o,
    output logic                 commit_pending_o,
    output logic                 commit_pulse_o,
    output logic                 commit_overrun_o
);

    logic [MODE_W-1:0]  shadow_mode_q;
    logic [MODE_W-1:0]  active_mode_q;
    logic [EPOCH_W-1:0] epoch_id_q;
    logic               pending_q;
    logic               overrun_q;
    logic               safe_to_commit;

    assign safe_to_commit  = epoch_boundary_i && affected_empty_i;
    assign shadow_mode_o   = shadow_mode_q;
    assign active_mode_o   = active_mode_q;
    assign epoch_id_o      = epoch_id_q;
    assign commit_pending_o = pending_q;
    assign commit_overrun_o = overrun_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            shadow_mode_q <= RESET_MODE;
            active_mode_q <= RESET_MODE;
            epoch_id_q    <= '0;
            pending_q     <= 1'b0;
            overrun_q     <= 1'b0;
            commit_pulse_o <= 1'b0;
        end else begin
            commit_pulse_o <= 1'b0;
            if (shadow_we_i) begin
                shadow_mode_q <= shadow_mode_i;
            end
            if (commit_i && pending_q) begin
                overrun_q <= 1'b1;
            end
            if (commit_i) begin
                pending_q <= 1'b1;
            end
            if ((pending_q || commit_i) && safe_to_commit) begin
                // A same-cycle shadow write is intentionally included in the
                // atomic commit so software can write-and-commit at a boundary.
                active_mode_q <= shadow_we_i ? shadow_mode_i : shadow_mode_q;
                epoch_id_q    <= epoch_id_q + {{(EPOCH_W-1){1'b0}}, 1'b1};
                pending_q     <= 1'b0;
                commit_pulse_o <= 1'b1;
            end
        end
    end

`ifndef SYNTHESIS
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        $changed(active_mode_q) |-> $past((pending_q || commit_i) && safe_to_commit));
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        commit_pulse_o |-> $changed(epoch_id_q));
`endif

endmodule
