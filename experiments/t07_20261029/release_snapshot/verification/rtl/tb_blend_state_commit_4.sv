`timescale 1ns/1ps

module tb_blend_state_commit_4;
    localparam int META_W = 8;
    localparam int PIXEL_W = 5;
    localparam int EPOCH_W = 4;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    logic s_valid, s_ready;
    logic [META_W-1:0] s_meta;
    logic [PIXEL_W-1:0] s_pixel;
    logic [EPOCH_W-1:0] s_epoch;
    logic [12:0] s_r, s_g, s_b, s_alpha;
    logic m_valid, m_ready;
    logic [META_W-1:0] m_meta;
    logic [PIXEL_W-1:0] m_pixel;
    logic [EPOCH_W-1:0] m_epoch;
    logic [12:0] m_r, m_g, m_b;
    logic [15:0] m_t;
    logic m_terminated;
    logic [2:0] occupancy;
    logic query_valid, query_ready;
    logic [PIXEL_W-1:0] query_pixel;
    logic [EPOCH_W-1:0] query_epoch;
    logic [1:0] query_tag;
    logic response_valid, response_ready;
    logic [1:0] response_tag;
    logic [12:0] response_r, response_g, response_b;
    logic [15:0] response_t;
    logic update_valid;
    logic [PIXEL_W-1:0] update_pixel;
    logic [EPOCH_W-1:0] update_epoch;
    logic [12:0] update_r, update_g, update_b;
    logic [15:0] update_t;

    logic pending [0:3];
    logic [PIXEL_W-1:0] pending_pixel [0:3];
    logic [EPOCH_W-1:0] pending_epoch [0:3];
    logic mem_valid [0:31];
    logic [EPOCH_W-1:0] mem_epoch [0:31];
    logic [12:0] mem_r [0:31];
    logic [12:0] mem_g [0:31];
    logic [12:0] mem_b [0:31];
    logic [15:0] mem_t [0:31];

    logic [META_W-1:0] exp_meta [0:31];
    logic [PIXEL_W-1:0] exp_pixel [0:31];
    logic [12:0] exp_r [0:31];
    logic [15:0] exp_t [0:31];
    integer exp_wr = 0;
    integer exp_rd = 0;
    integer commit_count = 0;
    integer simultaneous_replace_count = 0;
    integer response_bypass_count = 0;
    integer blend_commit_bypass_count = 0;
    integer cycle_count = 0;

    blend_state_commit_4 #(
        .META_W(META_W), .PIXEL_W(PIXEL_W), .EPOCH_W(EPOCH_W),
        .ENABLE_RESPONSE_BLEND_BYPASS(1'b1),
        .ENABLE_BLEND_COMMIT_BYPASS(1'b1)
    ) dut (
        .clk_i(clk), .rst_ni(rst_n),
        .s_valid_i(s_valid), .s_ready_o(s_ready), .s_meta_i(s_meta),
        .s_pixel_id_i(s_pixel), .s_epoch_id_i(s_epoch),
        .s_color_r_q12_i(s_r), .s_color_g_q12_i(s_g),
        .s_color_b_q12_i(s_b), .s_alpha_q12_i(s_alpha),
        .m_valid_o(m_valid), .m_ready_i(m_ready), .m_meta_o(m_meta),
        .m_pixel_id_o(m_pixel), .m_epoch_id_o(m_epoch),
        .m_r_q12_o(m_r), .m_g_q12_o(m_g), .m_b_q12_o(m_b),
        .m_t_q16_o(m_t), .m_newly_terminated_o(m_terminated),
        .occupancy_o(occupancy),
        .state_query_valid_o(query_valid), .state_query_ready_i(query_ready),
        .state_query_pixel_id_o(query_pixel), .state_query_epoch_id_o(query_epoch),
        .state_query_tag_o(query_tag),
        .state_response_valid_i(response_valid),
        .state_response_ready_o(response_ready), .state_response_tag_i(response_tag),
        .state_response_r_q12_i(response_r), .state_response_g_q12_i(response_g),
        .state_response_b_q12_i(response_b), .state_response_t_q16_i(response_t),
        .state_update_valid_o(update_valid), .state_update_pixel_id_o(update_pixel),
        .state_update_epoch_id_o(update_epoch), .state_update_r_q12_o(update_r),
        .state_update_g_q12_o(update_g), .state_update_b_q12_o(update_b),
        .state_update_t_q16_o(update_t)
    );

    task automatic expect_packet(
        input logic [META_W-1:0] meta,
        input logic [PIXEL_W-1:0] pixel,
        input logic [12:0] red,
        input logic [15:0] transmittance
    );
        begin
            exp_meta[exp_wr] = meta;
            exp_pixel[exp_wr] = pixel;
            exp_r[exp_wr] = red;
            exp_t[exp_wr] = transmittance;
            exp_wr = exp_wr + 1;
        end
    endtask

    task automatic push_packet(
        input logic [META_W-1:0] meta,
        input logic [PIXEL_W-1:0] pixel,
        input logic [12:0] red,
        input logic [12:0] alpha
    );
        begin
            @(negedge clk);
            s_meta = meta;
            s_pixel = pixel;
            s_epoch = 4'h3;
            s_r = red;
            s_g = red;
            s_b = red;
            s_alpha = alpha;
            s_valid = 1'b1;
            do @(posedge clk); while (!s_ready);
            @(negedge clk);
            s_valid = 1'b0;
        end
    endtask

    task automatic wait_pending(input logic [1:0] tag);
        integer timeout;
        begin
            timeout = 0;
            while (!pending[tag]) begin
                @(negedge clk);
                timeout = timeout + 1;
                if (timeout > 100) $fatal(1, "timeout waiting for query tag %0d", tag);
            end
        end
    endtask

    task automatic return_response(input logic [1:0] tag);
        logic [PIXEL_W-1:0] pixel;
        begin
            wait_pending(tag);
            pixel = pending_pixel[tag];
            @(negedge clk);
            response_tag = tag;
            if (mem_valid[pixel] && mem_epoch[pixel] == pending_epoch[tag]) begin
                response_r = mem_r[pixel];
                response_g = mem_g[pixel];
                response_b = mem_b[pixel];
                response_t = mem_t[pixel];
            end else begin
                response_r = 13'd0;
                response_g = 13'd0;
                response_b = 13'd0;
                response_t = 16'hffff;
            end
            response_valid = 1'b1;
            do @(posedge clk); while (!response_ready);
            @(negedge clk);
            response_valid = 1'b0;
        end
    endtask

    task automatic wait_commits(input integer target);
        integer timeout;
        begin
            timeout = 0;
            while (commit_count < target) begin
                @(negedge clk);
                timeout = timeout + 1;
                if (timeout > 200) $fatal(1, "timeout waiting for commit %0d", target);
            end
        end
    endtask

    always @(posedge clk) begin
        cycle_count = cycle_count + 1;
        if (cycle_count > 2000) $fatal(1, "global timeout");

        if (rst_n && query_valid && query_ready) begin
            if (pending[query_tag])
                $fatal(1, "tag %0d reused before its response", query_tag);
            pending[query_tag] = 1'b1;
            pending_pixel[query_tag] = query_pixel;
            pending_epoch[query_tag] = query_epoch;
        end
        if (rst_n && response_valid && response_ready)
            pending[response_tag] = 1'b0;

        if (rst_n && update_valid) begin
            mem_valid[update_pixel] = 1'b1;
            mem_epoch[update_pixel] = update_epoch;
            mem_r[update_pixel] = update_r;
            mem_g[update_pixel] = update_g;
            mem_b[update_pixel] = update_b;
            mem_t[update_pixel] = update_t;
        end

        if (rst_n && m_valid && m_ready) begin
            if (exp_rd >= exp_wr) $fatal(1, "unexpected commit meta=%0d", m_meta);
            if (m_meta !== exp_meta[exp_rd] || m_pixel !== exp_pixel[exp_rd] ||
                m_r !== exp_r[exp_rd] || m_g !== exp_r[exp_rd] ||
                m_b !== exp_r[exp_rd] || m_t !== exp_t[exp_rd])
                $fatal(1, "commit[%0d] mismatch got meta/pixel/r/t=%0d/%0d/%0d/%0d expected=%0d/%0d/%0d/%0d",
                       exp_rd, m_meta, m_pixel, m_r, m_t, exp_meta[exp_rd],
                       exp_pixel[exp_rd], exp_r[exp_rd], exp_t[exp_rd]);
            exp_rd = exp_rd + 1;
            commit_count = commit_count + 1;
        end
        if (rst_n && dut.alloc_fire && dut.commit_fire)
            simultaneous_replace_count = simultaneous_replace_count + 1;
        if (rst_n && dut.response_bypass_fire)
            response_bypass_count = response_bypass_count + 1;
        if (rst_n && dut.blend_commit_bypass_fire)
            blend_commit_bypass_count = blend_commit_bypass_count + 1;
    end

    initial begin : stimulus
        integer index;
        logic [META_W-1:0] held_meta;
        logic [PIXEL_W-1:0] held_pixel;
        logic [12:0] held_r;
        logic [15:0] held_t;

        s_valid = 1'b0;
        s_meta = '0;
        s_pixel = '0;
        s_epoch = '0;
        s_r = '0;
        s_g = '0;
        s_b = '0;
        s_alpha = '0;
        m_ready = 1'b1;
        query_ready = 1'b1;
        response_valid = 1'b0;
        response_tag = '0;
        response_r = '0;
        response_g = '0;
        response_b = '0;
        response_t = 16'hffff;
        for (index = 0; index < 4; index = index + 1) pending[index] = 1'b0;
        for (index = 0; index < 32; index = index + 1) begin
            mem_valid[index] = 1'b0;
            mem_epoch[index] = '0;
            mem_r[index] = '0;
            mem_g[index] = '0;
            mem_b[index] = '0;
            mem_t[index] = 16'hffff;
        end

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // Four independent keys may query concurrently. Return state in the
        // deliberately hostile order 3,1,2,0; nothing may commit before head 0.
        for (index = 0; index < 4; index = index + 1) begin
            expect_packet(index[7:0], (index + 1), 13'd4096, 16'd0);
            push_packet(index[7:0], (index + 1), 13'd4096, 13'd4096);
        end
        return_response(2'd3);
        return_response(2'd1);
        return_response(2'd2);
        repeat (3) @(posedge clk);
        if (commit_count != 0) $fatal(1, "younger slot committed ahead of ring head");
        return_response(2'd0);
        wait_commits(4);

        // Complete-key RAW CAM must serialize all four updates to one pixel.
        // The expected values are the exact Q-format results for alpha=0.5.
        expect_packet(8'd4, 5'd9, 13'd2048, 16'd32768);
        expect_packet(8'd5, 5'd9, 13'd3072, 16'd16384);
        expect_packet(8'd6, 5'd9, 13'd3584, 16'd8192);
        expect_packet(8'd7, 5'd9, 13'd3840, 16'd4096);
        push_packet(8'd4, 5'd9, 13'd4096, 13'd2048);
        push_packet(8'd5, 5'd9, 13'd4096, 13'd2048);
        push_packet(8'd6, 5'd9, 13'd4096, 13'd2048);
        push_packet(8'd7, 5'd9, 13'd4096, 13'd2048);
        return_response(2'd0);
        wait_commits(5);
        return_response(2'd1);
        wait_commits(6);
        return_response(2'd2);
        wait_commits(7);
        return_response(2'd3);
        wait_commits(8);

        // Fill after head/tail wrap, finish all four slots, and stall commit.
        // Output payload must remain stable, and releasing ready while a fifth
        // packet is waiting must perform full-window commit+replacement.
        m_ready = 1'b0;
        for (index = 0; index < 4; index = index + 1) begin
            expect_packet((8 + index), (12 + index), (1000 + index), 16'd0);
            push_packet((8 + index), (12 + index), (1000 + index), 13'd4096);
        end
        return_response(2'd0);
        return_response(2'd1);
        return_response(2'd2);
        return_response(2'd3);
        while (!m_valid) @(negedge clk);
        if (occupancy !== 3'd4) $fatal(1, "window not full before replacement");
        held_meta = m_meta;
        held_pixel = m_pixel;
        held_r = m_r;
        held_t = m_t;
        repeat (3) begin
            @(posedge clk);
            if (!m_valid || m_meta !== held_meta || m_pixel !== held_pixel ||
                m_r !== held_r || m_t !== held_t)
                $fatal(1, "commit payload changed under backpressure");
        end

        expect_packet(8'd12, 5'd20, 13'd2000, 16'd0);
        @(negedge clk);
        s_meta = 8'd12;
        s_pixel = 5'd20;
        s_epoch = 4'h3;
        s_r = 13'd2000;
        s_g = 13'd2000;
        s_b = 13'd2000;
        s_alpha = 13'd4096;
        s_valid = 1'b1;
        if (s_ready) $fatal(1, "full window accepted without a simultaneous commit");
        m_ready = 1'b1;
        @(posedge clk);
        if (!s_ready) $fatal(1, "full window failed commit+replacement bypass");
        @(negedge clk);
        s_valid = 1'b0;
        if (occupancy !== 3'd4) $fatal(1, "replacement changed full occupancy");

        wait_commits(12);
        return_response(2'd0);
        wait_commits(13);
        if (simultaneous_replace_count == 0)
            $fatal(1, "commit+allocation replacement was not observed");
        if (response_bypass_count == 0)
            $fatal(1, "response-to-blend bypass was not observed");
        if (blend_commit_bypass_count == 0)
            $fatal(1, "blend-to-commit bypass was not observed");
        if (exp_rd != exp_wr) $fatal(1, "expected queue did not drain");
        if (occupancy != 0) $fatal(1, "window did not drain");

        $display("PASS: 4-entry ordered state window, OOO responses, RAW CAM, wrap and replacement");
        $finish;
    end
endmodule
