`timescale 1ns/1ps

module tb_alpha_block_float_core;
    localparam int META_W = 16;
    logic clk_i = 1'b0;
    logic rst_ni = 1'b0;
    logic s_valid_i = 1'b0;
    logic s_ready_o;
    logic [META_W-1:0] s_meta_i = '0;
    logic signed [15:0] s_dx_q10_i = '0;
    logic signed [15:0] s_dy_q10_i = '0;
    logic [14:0] s_l00_q12_i = '0;
    logic signed [15:0] s_l10_q12_i = '0;
    logic [14:0] s_l11_q12_i = '0;
    logic signed [5:0] s_coordinate_shift_i = '0;
    logic signed [5:0] s_factor_shift_i = '0;
    logic [12:0] s_opacity_q12_i = '0;
    logic m_valid_o;
    logic m_ready_i = 1'b1;
    logic [META_W-1:0] m_meta_o;
    logic [12:0] m_alpha_q12_o;
    logic m_pass_alpha_o;

    always #5 clk_i = ~clk_i;

    alpha_block_float_core #(.META_W(META_W)) dut (.*);

    task automatic tick;
        begin @(posedge clk_i); #1; end
    endtask

    task automatic send_and_expect(
        input logic [META_W-1:0] meta,
        input logic signed [15:0] dx,
        input logic signed [15:0] dy,
        input logic [14:0] l00,
        input logic signed [15:0] l10,
        input logic [14:0] l11,
        input logic signed [5:0] coordinate_shift,
        input logic signed [5:0] factor_shift,
        input logic [12:0] opacity,
        input logic [12:0] expected_alpha,
        input logic expected_pass
    );
        integer timeout;
        begin
            while (!s_ready_o) tick();
            s_meta_i = meta;
            s_dx_q10_i = dx;
            s_dy_q10_i = dy;
            s_l00_q12_i = l00;
            s_l10_q12_i = l10;
            s_l11_q12_i = l11;
            s_coordinate_shift_i = coordinate_shift;
            s_factor_shift_i = factor_shift;
            s_opacity_q12_i = opacity;
            s_valid_i = 1'b1;
            tick();
            s_valid_i = 1'b0;

            timeout = 0;
            while (!m_valid_o && timeout < 20) begin
                tick();
                timeout = timeout + 1;
            end
            if (!m_valid_o)
                $fatal(1, "alpha output timeout meta=%h", meta);
            if (m_meta_o !== meta || m_alpha_q12_o !== expected_alpha ||
                m_pass_alpha_o !== expected_pass)
                $fatal(1, "alpha mismatch meta=%h got=(%h,%0d,%b) expected=(%h,%0d,%b)",
                       meta, m_alpha_q12_o, m_pass_alpha_o,
                       meta, expected_alpha, expected_pass);
            tick();
        end
    endtask

    initial begin
        repeat (2) tick();
        rst_ni = 1'b1;
        tick();

        // At the Gaussian center exp(0)=1, so alpha equals opacity.
        send_and_expect(16'h1001, 16'sd0, 16'sd0, 15'd4096, 16'sd0,
                        15'd4096, 6'sd0, 6'sd0, 13'd2048, 13'd2048, 1'b1);
        // Architectural clamp to 0.99 (4055/4096).
        send_and_expect(16'h1002, 16'sd0, 16'sd0, 15'd4096, 16'sd0,
                        15'd4096, 6'sd0, 6'sd0, 13'd4096, 13'd4055, 1'b1);
        // Threshold is inclusive at code 16.
        send_and_expect(16'h1003, 16'sd0, 16'sd0, 15'd4096, 16'sd0,
                        15'd4096, 6'sd0, 6'sd0, 13'd15, 13'd15, 1'b0);
        send_and_expect(16'h1004, 16'sd0, 16'sd0, 15'd4096, 16'sd0,
                        15'd4096, 6'sd0, 6'sd0, 13'd16, 13'd16, 1'b1);
        // dx=1, l00=1 gives LUT index 247 and exp code 2479.
        send_and_expect(16'h1005, 16'sd1024, 16'sd0, 15'd4096, 16'sd0,
                        15'd4096, 6'sd0, 6'sd0, 13'd4096, 13'd2479, 1'b1);

        // Backpressure must preserve the complete result packet.
        m_ready_i = 1'b0;
        while (!s_ready_o) tick();
        s_meta_i = 16'hbeef;
        s_dx_q10_i = 16'sd0;
        s_dy_q10_i = 16'sd0;
        s_l00_q12_i = 15'd4096;
        s_l10_q12_i = 16'sd0;
        s_l11_q12_i = 15'd4096;
        s_coordinate_shift_i = 6'sd0;
        s_factor_shift_i = 6'sd0;
        s_opacity_q12_i = 13'd1024;
        s_valid_i = 1'b1;
        tick();
        s_valid_i = 1'b0;
        while (!m_valid_o) tick();
        repeat (3) begin
            if (m_meta_o !== 16'hbeef || m_alpha_q12_o !== 13'd1024 ||
                !m_pass_alpha_o)
                $fatal(1, "alpha result changed while stalled");
            tick();
        end
        m_ready_i = 1'b1;
        tick();

        $display("PASS: tb_alpha_block_float_core");
        $finish;
    end
endmodule
