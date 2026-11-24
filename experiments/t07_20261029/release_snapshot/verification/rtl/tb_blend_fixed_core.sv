`timescale 1ns/1ps

module tb_blend_fixed_core;
    localparam int META_W = 16;
    localparam int RANDOM_CASES = 256;
    logic clk_i = 1'b0;
    logic rst_ni = 1'b0;
    logic s_valid_i = 1'b0;
    logic s_ready_o;
    logic [META_W-1:0] s_meta_i = '0;
    logic [12:0] s_old_r_q12_i = '0, s_old_g_q12_i = '0, s_old_b_q12_i = '0;
    logic [15:0] s_old_t_q16_i = '0;
    logic [12:0] s_color_r_q12_i = '0, s_color_g_q12_i = '0;
    logic [12:0] s_color_b_q12_i = '0, s_alpha_q12_i = '0;
    logic m_valid_o;
    logic m_ready_i = 1'b1;
    logic [META_W-1:0] m_meta_o;
    logic [12:0] m_new_r_q12_o, m_new_g_q12_o, m_new_b_q12_o;
    logic [15:0] m_new_t_q16_o;
    logic m_newly_terminated_o;
    logic r_pe_req_valid_o,r_pe_req_ready_i=1'b0,r_pe_rsp_valid_i=1'b0,r_pe_rsp_ready_o;
    logic signed[31:0]r_pe_lhs_o,r_pe_rhs_o;
    logic signed[64:0]r_pe_result_i='0;

    always #5 clk_i = ~clk_i;

    blend_fixed_core #(.META_W(META_W), .TERMINATION_Q16(7)) dut (.*);

    task automatic tick;
        begin @(posedge clk_i); #1; end
    endtask

    task automatic send_and_expect(
        input logic [15:0] meta,
        input logic [12:0] old_r, old_g, old_b,
        input logic [15:0] old_t,
        input logic [12:0] color_r, color_g, color_b, alpha,
        input logic [12:0] expected_r, expected_g, expected_b,
        input logic [15:0] expected_t,
        input logic expected_newly_terminated
    );
        begin
            while (!s_ready_o) tick();
            s_meta_i = meta;
            s_old_r_q12_i = old_r;
            s_old_g_q12_i = old_g;
            s_old_b_q12_i = old_b;
            s_old_t_q16_i = old_t;
            s_color_r_q12_i = color_r;
            s_color_g_q12_i = color_g;
            s_color_b_q12_i = color_b;
            s_alpha_q12_i = alpha;
            s_valid_i = 1'b1;
            tick();
            s_valid_i = 1'b0;
            while (!m_valid_o) tick();
            if (m_meta_o !== meta || m_new_r_q12_o !== expected_r ||
                m_new_g_q12_o !== expected_g || m_new_b_q12_o !== expected_b ||
                m_new_t_q16_o !== expected_t ||
                m_newly_terminated_o !== expected_newly_terminated)
                $fatal(1, "blend mismatch meta=%h rgb=%0d,%0d,%0d t=%0d term=%b",
                       m_meta_o, m_new_r_q12_o, m_new_g_q12_o,
                       m_new_b_q12_o, m_new_t_q16_o, m_newly_terminated_o);
            tick();
        end
    endtask

    task automatic send_reference(
        input logic [15:0] meta,
        input logic [12:0] old_r, old_g, old_b,
        input logic [15:0] old_t,
        input logic [12:0] color_r, color_g, color_b, alpha
    );
        longint unsigned weight_product_ref;
        longint unsigned weight_ref;
        longint unsigned add_r_ref, add_g_ref, add_b_ref;
        longint unsigned new_r_ref, new_g_ref, new_b_ref, new_t_ref;
        begin
            weight_product_ref = old_t * alpha;
            weight_ref = (weight_product_ref + 2048) >> 12;
            add_r_ref = (weight_ref * color_r + 32768) >> 16;
            add_g_ref = (weight_ref * color_g + 32768) >> 16;
            add_b_ref = (weight_ref * color_b + 32768) >> 16;
            new_r_ref = old_r + add_r_ref;
            new_g_ref = old_g + add_g_ref;
            new_b_ref = old_b + add_b_ref;
            new_t_ref = (old_t * (4096-alpha) + 2048) >> 12;
            send_and_expect(meta, old_r, old_g, old_b, old_t,
                            color_r, color_g, color_b, alpha,
                            new_r_ref > 4096 ? 13'd4096 : new_r_ref[12:0],
                            new_g_ref > 4096 ? 13'd4096 : new_g_ref[12:0],
                            new_b_ref > 4096 ? 13'd4096 : new_b_ref[12:0],
                            new_t_ref[15:0],
                            (old_t > 7) && (new_t_ref <= 7));
        end
    endtask

    initial begin
        repeat (2) tick();
        rst_ni = 1'b1;
        tick();

        send_and_expect(16'h2001, 13'd0, 13'd0, 13'd0, 16'hffff,
                        13'd4096, 13'd2048, 13'd1024, 13'd2048,
                        13'd2048, 13'd1024, 13'd512, 16'd32768, 1'b0);
        send_and_expect(16'h2002, 13'd4000, 13'd4090, 13'd4096, 16'hffff,
                        13'd4096, 13'd4096, 13'd4096, 13'd2048,
                        13'd4096, 13'd4096, 13'd4096, 16'd32768, 1'b0);
        send_and_expect(16'h2003, 13'd0, 13'd0, 13'd0, 16'd8,
                        13'd0, 13'd0, 13'd0, 13'd512,
                        13'd0, 13'd0, 13'd0, 16'd7, 1'b1);
        send_and_expect(16'h2004, 13'd0, 13'd0, 13'd0, 16'd7,
                        13'd4096, 13'd4096, 13'd4096, 13'd4096,
                        13'd0, 13'd0, 13'd0, 16'd0, 1'b0);

        // Registered result must remain stable under output backpressure.
        m_ready_i = 1'b0;
        while (!s_ready_o) tick();
        s_meta_i = 16'hcafe;
        s_old_r_q12_i = 13'd10;
        s_old_g_q12_i = 13'd20;
        s_old_b_q12_i = 13'd30;
        s_old_t_q16_i = 16'hffff;
        s_color_r_q12_i = 13'd4096;
        s_color_g_q12_i = 13'd0;
        s_color_b_q12_i = 13'd0;
        s_alpha_q12_i = 13'd1024;
        s_valid_i = 1'b1;
        tick();
        s_valid_i = 1'b0;
        while (!m_valid_o) tick();
        repeat (3) begin
            if (m_meta_o !== 16'hcafe || m_new_r_q12_o !== 13'd1034 ||
                m_new_g_q12_o !== 13'd20 || m_new_b_q12_o !== 13'd30 ||
                m_new_t_q16_o !== 16'd49151)
                $fatal(1, "blend result changed while stalled");
            tick();
        end
        m_ready_i = 1'b1;
        tick();

        // Valid-domain randomized arithmetic regression.  This independently
        // evaluates the two original equations and catches any error in the
        // shared-product transform, rounding, saturation, or metadata order.
        for (int i = 0; i < RANDOM_CASES; i++) begin
            send_reference(16'h4000 + i[15:0],
                           $urandom_range(4096, 0),
                           $urandom_range(4096, 0),
                           $urandom_range(4096, 0),
                           $urandom_range(65535, 0),
                           $urandom_range(4096, 0),
                           $urandom_range(4096, 0),
                           $urandom_range(4096, 0),
                           $urandom_range(4096, 0));
        end

        $display("PASS: tb_blend_fixed_core");
        $finish;
    end
endmodule
