`timescale 1ns/1ps

module tb_image_state_store;
    localparam int PIXEL_W = 4;
    localparam int EPOCH_W = 4;
    logic clk_i = 1'b0;
    logic rst_ni = 1'b0;
    logic query_valid_i = 1'b0;
    logic query_ready_o;
    logic [PIXEL_W-1:0] query_pixel_id_i = '0;
    logic [EPOCH_W-1:0] query_epoch_id_i = '0;
    logic response_valid_o;
    logic response_ready_i = 1'b1;
    logic [12:0] response_r_q12_o, response_g_q12_o, response_b_q12_o;
    logic [15:0] response_t_q16_o;
    logic update_valid_i = 1'b0;
    logic [PIXEL_W-1:0] update_pixel_id_i = '0;
    logic [EPOCH_W-1:0] update_epoch_id_i = '0;
    logic [12:0] update_r_q12_i = '0, update_g_q12_i = '0, update_b_q12_i = '0;
    logic [15:0] update_t_q16_i = '0;

    always #5 clk_i = ~clk_i;

    image_state_store #(
        .PIXEL_W(PIXEL_W), .EPOCH_W(EPOCH_W), .ENTRIES(16)
    ) dut (.*);

    task automatic tick;
        begin @(posedge clk_i); #1; end
    endtask

    task automatic update(
        input logic [3:0] pixel, epoch,
        input logic [12:0] r, g, b,
        input logic [15:0] t
    );
        begin
            update_pixel_id_i = pixel;
            update_epoch_id_i = epoch;
            update_r_q12_i = r;
            update_g_q12_i = g;
            update_b_q12_i = b;
            update_t_q16_i = t;
            update_valid_i = 1'b1;
            tick();
            update_valid_i = 1'b0;
        end
    endtask

    task automatic query_and_expect(
        input logic [3:0] pixel, epoch,
        input logic [12:0] expected_r, expected_g, expected_b,
        input logic [15:0] expected_t
    );
        begin
            while (!query_ready_o) tick();
            query_pixel_id_i = pixel;
            query_epoch_id_i = epoch;
            query_valid_i = 1'b1;
            tick();
            query_valid_i = 1'b0;
            if (!response_valid_o || response_r_q12_o !== expected_r ||
                response_g_q12_o !== expected_g || response_b_q12_o !== expected_b ||
                response_t_q16_o !== expected_t)
                $fatal(1, "state query mismatch pixel=%0d epoch=%0d", pixel, epoch);
            tick();
        end
    endtask

    initial begin
        repeat (2) tick();
        rst_ni = 1'b1;
        tick();

        query_and_expect(4'd3, 4'd1, 13'd0, 13'd0, 13'd0, 16'hffff);
        update(4'd3, 4'd1, 13'd100, 13'd200, 13'd300, 16'd40000);
        query_and_expect(4'd3, 4'd1, 13'd100, 13'd200, 13'd300, 16'd40000);
        // Epoch mismatch performs logical clear without clearing the arrays.
        query_and_expect(4'd3, 4'd2, 13'd0, 13'd0, 13'd0, 16'hffff);

        // Same-cycle update/query for the same tag is write-through.
        while (!query_ready_o) tick();
        query_pixel_id_i = 4'd5;
        query_epoch_id_i = 4'd2;
        query_valid_i = 1'b1;
        update_pixel_id_i = 4'd5;
        update_epoch_id_i = 4'd2;
        update_r_q12_i = 13'd111;
        update_g_q12_i = 13'd222;
        update_b_q12_i = 13'd333;
        update_t_q16_i = 16'd44444;
        update_valid_i = 1'b1;
        tick();
        query_valid_i = 1'b0;
        update_valid_i = 1'b0;
        if (!response_valid_o || response_r_q12_o !== 13'd111 ||
            response_g_q12_o !== 13'd222 || response_b_q12_o !== 13'd333 ||
            response_t_q16_o !== 16'd44444)
            $fatal(1, "state write-through mismatch");

        // Held response cannot be overwritten until the consumer is ready.
        response_ready_i = 1'b0;
        #1;
        repeat (3) begin
            if (!response_valid_o || response_r_q12_o !== 13'd111 ||
                response_t_q16_o !== 16'd44444 || query_ready_o)
                $fatal(1, "state response changed while stalled valid=%b r=%0d t=%0d qready=%b",
                       response_valid_o, response_r_q12_o, response_t_q16_o,
                       query_ready_o);
            tick();
        end
        response_ready_i = 1'b1;
        tick();

        $display("PASS: tb_image_state_store");
        $finish;
    end
endmodule
