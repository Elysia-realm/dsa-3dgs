`timescale 1ns/1ps

module tb_raster_pair_shell;
    localparam LANES=4;
    logic clk_i = 1'b0;
    logic rst_ni = 1'b0;
    logic [2:0] cfg_active_lanes_i = 4;
    logic task_valid_i = 1'b0;
    logic task_ready_o;
    logic [31:0] task_id_i = '0;
    logic [23:0] block_id_i = '0;
    logic [31:0] gid_i = '0;
    logic [15:0] epoch_id_i = '0;
    logic [11:0] pixel_id_i = '0;
    logic [5:0] pixel_in_block_i = '0;
    logic [12:0] color_r_q12_i = '0, color_g_q12_i = '0, color_b_q12_i = '0;
    logic signed [15:0] alpha_dx_q10_i = '0, alpha_dy_q10_i = '0;
    logic [14:0] alpha_l00_q12_i = 15'd4096;
    logic signed [15:0] alpha_l10_q12_i = '0;
    logic [14:0] alpha_l11_q12_i = 15'd4096;
    logic signed [5:0] alpha_coordinate_shift_i = '0;
    logic signed [5:0] alpha_factor_shift_i = '0;
    logic [12:0] alpha_opacity_q12_i = '0;
    logic block_terminated_pulse_o, skipped_terminated_pulse_o;
    logic commit_valid_o;
    logic commit_ready_i = 1'b1;
    logic [31:0] commit_task_id_o;
    logic [23:0] commit_block_id_o;
    logic [31:0] commit_gid_o;
    logic [15:0] commit_epoch_id_o;
    logic [12:0] commit_alpha_q12_o;
    logic commit_pass_alpha_o;
    logic [11:0] commit_pixel_id_o;
    logic [12:0] commit_r_q12_o, commit_g_q12_o, commit_b_q12_o;
    logic [15:0] commit_t_q16_o;
    logic commit_newly_terminated_o;
    logic [2:0] result_occupancy_o;
    logic [LANES-1:0] active_mask_o;
    logic retire_wait_o,protocol_error_o;
    logic idle_o;
    logic state_miss_req_valid_o,state_miss_req_ready_i=0;logic[1:0]state_miss_req_tag_o;
    logic state_miss_rsp_valid_i=0,state_miss_rsp_ready_o;logic[1:0]state_miss_rsp_tag_i=0;
    logic[11:0]state_miss_req_pixel_id_o;logic state_miss_rsp_error_i=0;
    logic[127:0]state_miss_rsp_data_i=0;logic state_cache_error_o,state_cache_idle_o;
    integer next_task_id = 1;
    integer simultaneous_commit_skip_count = 0;

    always #5 clk_i = ~clk_i;

    raster_pair_shell dut (.*,
        .r_pe_req_valid_o(),.r_pe_req_ready_i(1'b0),.r_pe_lhs_o(),.r_pe_rhs_o(),
        .r_pe_rsp_valid_i(1'b0),.r_pe_rsp_ready_o(),.r_pe_result_i(65'b0));

    always @(posedge clk_i)
        if (rst_ni && commit_valid_o && commit_ready_i && skipped_terminated_pulse_o)
            simultaneous_commit_skip_count <= simultaneous_commit_skip_count + 1;

    task automatic tick;
        begin @(posedge clk_i); #1; end
    endtask

    task automatic send_task(
        input logic [23:0] block_id,
        input logic [15:0] epoch,
        input logic [11:0] pixel_id,
        input logic [5:0] pixel_in_block,
        input logic [12:0] opacity,
        output logic [31:0] issued_task_id
    );
        begin
            issued_task_id = next_task_id;
            next_task_id = next_task_id + 1;
            task_id_i = issued_task_id;
            block_id_i = block_id;
            gid_i = 32'h1000_0000 + issued_task_id;
            epoch_id_i = epoch;
            pixel_id_i = pixel_id;
            pixel_in_block_i = pixel_in_block;
            color_r_q12_i = 13'd4096;
            color_g_q12_i = 13'd2048;
            color_b_q12_i = 13'd1024;
            alpha_dx_q10_i = 16'sd0;
            alpha_dy_q10_i = 16'sd0;
            alpha_l00_q12_i = 15'd4096;
            alpha_l10_q12_i = 16'sd0;
            alpha_l11_q12_i = 15'd4096;
            alpha_coordinate_shift_i = 6'sd0;
            alpha_factor_shift_i = 6'sd0;
            alpha_opacity_q12_i = opacity;
            task_valid_i = 1'b1;
            while (!task_ready_o) tick();
            tick();
            task_valid_i = 1'b0;
        end
    endtask

    task automatic wait_commit(
        input logic [31:0] expected_task_id,
        input logic [23:0] expected_block_id,
        input logic [15:0] expected_epoch,
        input logic [11:0] expected_pixel,
        input logic [12:0] expected_alpha,
        input logic expected_pass,
        input logic expected_newly_terminated
    );
        integer timeout;
        integer stall_cycles;
        begin
            // Deterministic pseudo-random backpressure (0..3 cycles) derived
            // from the transaction tag keeps the regression reproducible.
            stall_cycles = expected_task_id[1:0];
            commit_ready_i = 1'b0;
            timeout = 0;
            while (!commit_valid_o && timeout < 50) begin
                tick();
                timeout = timeout + 1;
            end
            if (!commit_valid_o)
                $fatal(1, "commit timeout task=%0d", expected_task_id);
            if (commit_task_id_o !== expected_task_id ||
                commit_block_id_o !== expected_block_id ||
                commit_epoch_id_o !== expected_epoch ||
                commit_pixel_id_o !== expected_pixel ||
                commit_alpha_q12_o !== expected_alpha ||
                commit_pass_alpha_o !== expected_pass ||
                commit_newly_terminated_o !== expected_newly_terminated)
                $fatal(1, "commit packet mismatch task=%0d got task=%0d block=%h epoch=%h pixel=%0d alpha=%0d pass=%b term=%b",
                       expected_task_id, commit_task_id_o, commit_block_id_o,
                       commit_epoch_id_o, commit_pixel_id_o, commit_alpha_q12_o,
                       commit_pass_alpha_o, commit_newly_terminated_o);
            repeat (stall_cycles) begin
                tick();
                if (!commit_valid_o || commit_task_id_o !== expected_task_id ||
                    commit_block_id_o !== expected_block_id ||
                    commit_epoch_id_o !== expected_epoch ||
                    commit_pixel_id_o !== expected_pixel ||
                    commit_alpha_q12_o !== expected_alpha ||
                    commit_pass_alpha_o !== expected_pass ||
                    commit_newly_terminated_o !== expected_newly_terminated)
                    $fatal(1, "commit packet changed during pseudo-random backpressure");
            end
            commit_ready_i = 1'b1;
            tick();
        end
    endtask

    initial begin : test_sequence
        logic [31:0] issued;
        integer pixel;
        integer pass;
        integer timeout;
        repeat (3) tick();
        rst_ni = 1'b1;
        tick();

        // Alpha below threshold still commits tags, but contributes zero color.
        send_task(24'h000101, 16'h0001, 12'd100, 6'd0, 13'd15, issued);
        wait_commit(issued, 24'h000101, 16'h0001, 12'd100, 13'd15, 1'b0, 1'b0);
        if (commit_r_q12_o !== 13'd0 || commit_g_q12_o !== 13'd0 ||
            commit_b_q12_o !== 13'd0 || commit_t_q16_o !== 16'hffff)
            $fatal(1, "pruned alpha modified image state");

        // A completed result must remain stable under external backpressure.
        commit_ready_i = 1'b0;
        send_task(24'h000102, 16'h0001, 12'd101, 6'd1, 13'd2048, issued);
        timeout = 0;
        while (!commit_valid_o && timeout < 50) begin tick(); timeout = timeout + 1; end
        if (!commit_valid_o) $fatal(1, "backpressured commit timeout");
        repeat (3) begin
            if (commit_task_id_o !== issued || commit_block_id_o !== 24'h000102 ||
                commit_epoch_id_o !== 16'h0001 || commit_pixel_id_o !== 12'd101 ||
                commit_alpha_q12_o !== 13'd2048 || !commit_pass_alpha_o)
                $fatal(1, "commit packet changed while stalled");
            tick();
        end
        commit_ready_i = 1'b1;
        tick();

        // Two maximum-alpha contributions reduce each fresh pixel from T=65535
        // to T=7. The second contribution therefore terminates the pixel.
        for (pixel = 0; pixel < 64; pixel = pixel + 1) begin
            for (pass = 0; pass < 2; pass = pass + 1) begin
                send_task(24'h000123, 16'h0002, pixel[11:0], pixel[5:0],
                          13'd4096, issued);
                wait_commit(issued, 24'h000123, 16'h0002, pixel[11:0],
                            13'd4055, 1'b1, pass == 1);
            end
        end

        timeout = 0;
        while (!block_terminated_pulse_o && timeout < 10) begin
            tick();
            timeout = timeout + 1;
        end
        if (!block_terminated_pulse_o)
            $fatal(1, "64 terminated pixels did not create block event");
        tick();

        // Once the coarse table is updated, another task for this block/epoch
        // is discarded before alpha and never reaches commit.
        send_task(24'h000123, 16'h0002, 12'd0, 6'd0, 13'd4096, issued);
        timeout = 0;
        while (!skipped_terminated_pulse_o && timeout < 20) begin
            if (commit_valid_o)
                $fatal(1, "terminated block unexpectedly reached commit");
            tick();
            timeout = timeout + 1;
        end
        if (!skipped_terminated_pulse_o)
            $fatal(1, "coarse block termination did not skip task");

        // The same block in a new epoch must be live again. Hold its completed
        // commit, then inject an old-epoch task which the coarse table skips.
        // Releasing commit on the skip pulse creates two independent
        // completions in one cycle and verifies inflight credit accounting.
        commit_ready_i = 1'b0;
        send_task(24'h000123, 16'h0003, 12'd0, 6'd0, 13'd16, issued);
        timeout = 0;
        while (!commit_valid_o && timeout < 50) begin tick(); timeout = timeout + 1; end
        if (!commit_valid_o || commit_task_id_o !== issued)
            $fatal(1, "new-epoch commit did not reach held output");
        send_task(24'h000123, 16'h0002, 12'd1, 6'd1, 13'd4096, issued);
        wait (skipped_terminated_pulse_o);
        if (!commit_valid_o)
            $fatal(1, "held commit disappeared before simultaneous skip");
        commit_ready_i = 1'b1;
        tick();
        if (simultaneous_commit_skip_count != 1)
            $fatal(1, "commit and skip did not complete in the same cycle");
        timeout = 0;
        while (!idle_o && timeout < 20) begin tick(); timeout = timeout + 1; end
        if (!idle_o || dut.inflight_count_q != 0)
            $fatal(1, "inflight accounting leaked after simultaneous commit+skip count=%0d",
                   dut.inflight_count_q);

        $display("PASS: tb_raster_pair_shell");
        $finish;
    end
endmodule
