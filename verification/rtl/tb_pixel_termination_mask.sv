`timescale 1ns/1ps

module tb_pixel_termination_mask;
    localparam int BLOCK_W = 8;
    localparam int EPOCH_W = 4;
    logic clk_i = 1'b0;
    logic rst_ni = 1'b0;
    logic query_valid_i = 1'b0;
    logic query_ready_o;
    logic [BLOCK_W-1:0] query_block_id_i = '0;
    logic [EPOCH_W-1:0] query_epoch_id_i = '0;
    logic response_valid_o;
    logic response_ready_i = 1'b1;
    logic [63:0] response_mask_o;
    logic response_all_terminated_o;
    logic update_valid_i = 1'b0;
    logic [BLOCK_W-1:0] update_block_id_i = '0;
    logic [EPOCH_W-1:0] update_epoch_id_i = '0;
    logic [63:0] update_new_terminated_i = '0;
    logic block_terminated_pulse_o;
    logic [BLOCK_W-1:0] block_terminated_id_o;
    logic [EPOCH_W-1:0] block_terminated_epoch_o;

    always #5 clk_i = ~clk_i;

    pixel_termination_mask #(
        .BLOCK_W(BLOCK_W), .EPOCH_W(EPOCH_W), .ENTRIES(4), .PIXELS(64)
    ) dut (.*);

    task automatic tick;
        begin @(posedge clk_i); #1; end
    endtask

    task automatic update(
        input logic [7:0] block_id,
        input logic [3:0] epoch,
        input logic [63:0] new_mask
    );
        begin
            update_block_id_i = block_id;
            update_epoch_id_i = epoch;
            update_new_terminated_i = new_mask;
            update_valid_i = 1'b1;
            tick();
            update_valid_i = 1'b0;
        end
    endtask

    task automatic query_and_expect(
        input logic [7:0] block_id,
        input logic [3:0] epoch,
        input logic [63:0] expected_mask
    );
        begin
            while (!query_ready_o) tick();
            query_block_id_i = block_id;
            query_epoch_id_i = epoch;
            query_valid_i = 1'b1;
            tick();
            query_valid_i = 1'b0;
            if (!response_valid_o || response_mask_o !== expected_mask ||
                response_all_terminated_o !== (&expected_mask))
                $fatal(1, "termination mask query mismatch block=%h epoch=%h", block_id, epoch);
            tick();
        end
    endtask

    initial begin
        repeat (2) tick();
        rst_ni = 1'b1;
        tick();

        query_and_expect(8'h05, 4'h1, 64'd0);
        update(8'h05, 4'h1, 64'h0000_0000_0000_0003);
        if (block_terminated_pulse_o) $fatal(1, "premature block termination pulse");
        update(8'h05, 4'h1, 64'h0000_0000_0000_000c);
        query_and_expect(8'h05, 4'h1, 64'h0000_0000_0000_000f);

        update(8'h05, 4'h1, 64'hffff_ffff_ffff_fff0);
        if (!block_terminated_pulse_o || block_terminated_id_o !== 8'h05 ||
            block_terminated_epoch_o !== 4'h1)
            $fatal(1, "first full-mask transition did not pulse");
        tick();
        if (block_terminated_pulse_o) $fatal(1, "termination pulse exceeded one cycle");
        update(8'h05, 4'h1, 64'h0000_0000_0000_0001);
        if (block_terminated_pulse_o) $fatal(1, "full mask pulsed more than once");

        // Epoch mismatch and a capacity alias both return an empty mask.
        query_and_expect(8'h05, 4'h2, 64'd0);
        query_and_expect(8'h09, 4'h1, 64'd0);

        // Same-cycle query/update exposes the merged mask.
        query_block_id_i = 8'h06;
        query_epoch_id_i = 4'h3;
        query_valid_i = 1'b1;
        update_block_id_i = 8'h06;
        update_epoch_id_i = 4'h3;
        update_new_terminated_i = 64'h8000_0000_0000_0001;
        update_valid_i = 1'b1;
        tick();
        query_valid_i = 1'b0;
        update_valid_i = 1'b0;
        if (!response_valid_o || response_mask_o !== 64'h8000_0000_0000_0001)
            $fatal(1, "termination mask write-through mismatch");

        response_ready_i = 1'b0;
        #1;
        repeat (3) begin
            if (!response_valid_o || response_mask_o !== 64'h8000_0000_0000_0001 ||
                query_ready_o)
                $fatal(1, "termination response changed while stalled");
            tick();
        end
        response_ready_i = 1'b1;
        tick();

        $display("PASS: tb_pixel_termination_mask");
        $finish;
    end
endmodule
