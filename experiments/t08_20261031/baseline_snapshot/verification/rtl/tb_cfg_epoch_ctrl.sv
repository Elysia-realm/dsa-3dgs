`timescale 1ns/1ps

module tb_cfg_epoch_ctrl;
    logic clk_i = 1'b0;
    logic rst_ni = 1'b0;
    logic shadow_we_i = 1'b0;
    logic [1:0] shadow_mode_i = 2'b00;
    logic commit_i = 1'b0;
    logic epoch_boundary_i = 1'b0;
    logic affected_empty_i = 1'b0;
    logic [1:0] shadow_mode_o;
    logic [1:0] active_mode_o;
    logic [15:0] epoch_id_o;
    logic commit_pending_o;
    logic commit_pulse_o;
    logic commit_overrun_o;

    always #5 clk_i = ~clk_i;

    cfg_epoch_ctrl #(
        .MODE_W(2),
        .EPOCH_W(16),
        .RESET_MODE(2'b00)
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .shadow_we_i(shadow_we_i),
        .shadow_mode_i(shadow_mode_i),
        .commit_i(commit_i),
        .epoch_boundary_i(epoch_boundary_i),
        .affected_empty_i(affected_empty_i),
        .shadow_mode_o(shadow_mode_o),
        .active_mode_o(active_mode_o),
        .epoch_id_o(epoch_id_o),
        .commit_pending_o(commit_pending_o),
        .commit_pulse_o(commit_pulse_o),
        .commit_overrun_o(commit_overrun_o)
    );

    task automatic tick;
        begin
            @(posedge clk_i);
            #1;
        end
    endtask

    initial begin
        repeat (2) tick();
        rst_ni = 1'b1;
        tick();

        if (active_mode_o !== 2'b00 || epoch_id_o !== 16'd0)
            $fatal(1, "reset state mismatch");

        shadow_mode_i = 2'b10;
        shadow_we_i = 1'b1;
        tick();
        shadow_we_i = 1'b0;
        if (shadow_mode_o !== 2'b10 || active_mode_o !== 2'b00)
            $fatal(1, "shadow write changed active state");

        commit_i = 1'b1;
        tick();
        commit_i = 1'b0;
        if (!commit_pending_o || commit_pulse_o)
            $fatal(1, "unsafe commit was not held pending");

        epoch_boundary_i = 1'b1;
        affected_empty_i = 1'b1;
        tick();
        epoch_boundary_i = 1'b0;
        affected_empty_i = 1'b0;
        if (active_mode_o !== 2'b10 || epoch_id_o !== 16'd1 ||
            commit_pending_o || !commit_pulse_o)
            $fatal(1, "pending commit did not apply atomically");

        shadow_mode_i = 2'b01;
        shadow_we_i = 1'b1;
        commit_i = 1'b1;
        epoch_boundary_i = 1'b1;
        affected_empty_i = 1'b1;
        tick();
        shadow_we_i = 1'b0;
        commit_i = 1'b0;
        epoch_boundary_i = 1'b0;
        affected_empty_i = 1'b0;
        if (active_mode_o !== 2'b01 || epoch_id_o !== 16'd2 ||
            !commit_pulse_o)
            $fatal(1, "same-cycle write and safe commit mismatch");

        commit_i = 1'b1;
        tick();
        commit_i = 1'b0;
        tick();
        commit_i = 1'b1;
        tick();
        commit_i = 1'b0;
        if (!commit_pending_o || !commit_overrun_o)
            $fatal(1, "repeated pending commit did not flag overrun");

        $display("PASS: tb_cfg_epoch_ctrl");
        $finish;
    end
endmodule
