`timescale 1ns/1ps

module tb_raster_termination_filter;
    localparam int PAYLOAD_W = 16;
    localparam int BLOCK_W = 8;
    localparam int EPOCH_W = 4;
    logic clk_i = 1'b0;
    logic rst_ni = 1'b0;
    logic task_valid_i = 1'b0;
    logic task_ready_o;
    logic [PAYLOAD_W-1:0] task_payload_i = '0;
    logic [BLOCK_W-1:0] task_block_id_i = '0;
    logic [EPOCH_W-1:0] task_epoch_id_i = '0;
    logic live_valid_o;
    logic live_ready_i = 1'b1;
    logic [PAYLOAD_W-1:0] live_payload_o;
    logic term_update_valid_i = 1'b0;
    logic [BLOCK_W-1:0] term_update_block_id_i = '0;
    logic [EPOCH_W-1:0] term_update_epoch_id_i = '0;
    logic skipped_pulse_o;

    always #5 clk_i = ~clk_i;

    raster_termination_filter #(
        .PAYLOAD_W(PAYLOAD_W), .BLOCK_W(BLOCK_W), .EPOCH_W(EPOCH_W),
        .NUM_BANKS(2), .ROWS_PER_BANK(4)
    ) dut (.*);

    task automatic tick;
        begin @(posedge clk_i); #1; end
    endtask

    task automatic update_terminated(
        input logic [7:0] block_id,
        input logic [3:0] epoch
    );
        begin
            term_update_block_id_i = block_id;
            term_update_epoch_id_i = epoch;
            term_update_valid_i = 1'b1;
            tick();
            term_update_valid_i = 1'b0;
        end
    endtask

    task automatic send_task(
        input logic [15:0] payload,
        input logic [7:0] block_id,
        input logic [3:0] epoch
    );
        begin
            task_payload_i = payload;
            task_block_id_i = block_id;
            task_epoch_id_i = epoch;
            task_valid_i = 1'b1;
            while (!task_ready_o) tick();
            tick();
            task_valid_i = 1'b0;
        end
    endtask

    task automatic expect_live(input logic [15:0] payload);
        integer timeout;
        begin
            timeout = 0;
            while (!live_valid_o && timeout < 10) begin
                tick();
                timeout = timeout + 1;
            end
            if (!live_valid_o || live_payload_o !== payload)
                $fatal(1, "live result mismatch got=%h expected=%h", live_payload_o, payload);
            tick();
        end
    endtask

    task automatic expect_skip;
        integer timeout;
        begin
            timeout = 0;
            while (!skipped_pulse_o && timeout < 10) begin
                tick();
                timeout = timeout + 1;
            end
            if (!skipped_pulse_o || live_valid_o)
                $fatal(1, "terminated task was not consumed locally");
            tick();
        end
    endtask

    initial begin
        repeat (2) tick();
        rst_ni = 1'b1;
        tick();

        send_task(16'h1111, 8'h02, 4'h1);
        expect_live(16'h1111);

        update_terminated(8'h02, 4'h1);
        send_task(16'h2222, 8'h02, 4'h1);
        expect_skip();

        // Epoch mismatch is conservatively live.
        send_task(16'h3333, 8'h02, 4'h2);
        expect_live(16'h3333);

        // 0x0a aliases the same physical row as 0x02. Full tags ensure that
        // replacement cannot create a false-positive skip for the old block.
        update_terminated(8'h0a, 4'h1);
        send_task(16'h4444, 8'h02, 4'h1);
        expect_live(16'h4444);
        send_task(16'h5555, 8'h0a, 4'h1);
        expect_skip();

        // Same-cycle query/update uses write-through and skips the task.
        term_update_block_id_i = 8'h07;
        term_update_epoch_id_i = 4'h3;
        term_update_valid_i = 1'b1;
        task_payload_i = 16'h7777;
        task_block_id_i = 8'h07;
        task_epoch_id_i = 4'h3;
        task_valid_i = 1'b1;
        while (!task_ready_o) tick();
        tick();
        term_update_valid_i = 1'b0;
        task_valid_i = 1'b0;
        expect_skip();

        // Live result packet remains stable during downstream backpressure.
        live_ready_i = 1'b0;
        send_task(16'hbeef, 8'h04, 4'h1);
        while (!live_valid_o) tick();
        repeat (3) begin
            if (live_payload_o !== 16'hbeef)
                $fatal(1, "live payload changed while stalled");
            tick();
        end
        live_ready_i = 1'b1;
        tick();

        $display("PASS: tb_raster_termination_filter");
        $finish;
    end
endmodule
