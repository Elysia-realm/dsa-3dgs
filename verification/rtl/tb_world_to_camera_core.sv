`timescale 1ns/1ps

module tb_world_to_camera_core;
    localparam int META_W = 16;
    logic clk_i = 1'b0, rst_ni = 1'b0;
    logic s_valid_i = 1'b0, s_ready_o;
    logic [META_W-1:0] s_meta_i = '0;
    logic signed [26:0] s_world_x_q16_i = '0;
    logic signed [26:0] s_world_y_q16_i = '0;
    logic signed [26:0] s_world_z_q16_i = '0;
    logic signed [21:0] cfg_r00_q20_i = 22'sd1048576;
    logic signed [21:0] cfg_r01_q20_i = '0, cfg_r02_q20_i = '0;
    logic signed [21:0] cfg_r10_q20_i = '0, cfg_r11_q20_i = 22'sd1048576;
    logic signed [21:0] cfg_r12_q20_i = '0, cfg_r20_q20_i = '0;
    logic signed [21:0] cfg_r21_q20_i = '0, cfg_r22_q20_i = 22'sd1048576;
    logic signed [26:0] cfg_tx_q16_i = '0, cfg_ty_q16_i = '0, cfg_tz_q16_i = '0;
    logic m_valid_o, m_ready_i = 1'b1;
    logic [META_W-1:0] m_meta_o;
    logic signed [26:0] m_camera_x_q16_o, m_camera_y_q16_o, m_camera_z_q16_o;
    logic m_overflow_o;

    always #5 clk_i = ~clk_i;

    world_to_camera_core #(.META_W(META_W)) dut (.*);

    task automatic tick; begin @(posedge clk_i); #1; end endtask

    task automatic send_and_expect(
        input logic [15:0] meta,
        input logic signed [26:0] wx, wy, wz,
        input logic signed [26:0] expected_x, expected_y, expected_z,
        input logic expected_overflow
    );
        begin
            while (!s_ready_o) tick();
            s_meta_i = meta;
            s_world_x_q16_i = wx;
            s_world_y_q16_i = wy;
            s_world_z_q16_i = wz;
            s_valid_i = 1'b1;
            tick();
            s_valid_i = 1'b0;
            while (!m_valid_o) tick();
            if (m_meta_o !== meta || m_camera_x_q16_o !== expected_x ||
                m_camera_y_q16_o !== expected_y || m_camera_z_q16_o !== expected_z ||
                m_overflow_o !== expected_overflow)
                $fatal(1, "world transform mismatch meta=%h xyz=%0d,%0d,%0d ov=%b",
                       m_meta_o, m_camera_x_q16_o, m_camera_y_q16_o,
                       m_camera_z_q16_o, m_overflow_o);
            tick();
        end
    endtask

    initial begin
        repeat (2) tick();
        rst_ni = 1'b1;
        tick();

        // Exact identity plus signed translation.
        cfg_tx_q16_i = 27'sd65536;
        cfg_ty_q16_i = -27'sd131072;
        cfg_tz_q16_i = 27'sd196608;
        send_and_expect(16'h1001, 27'sd65536, 27'sd262144, 27'sd327680,
                        27'sd131072, 27'sd131072, 27'sd524288, 1'b0);

        // Exactly half an output LSB rounds away from zero on both signs.
        cfg_tx_q16_i = '0; cfg_ty_q16_i = '0; cfg_tz_q16_i = '0;
        cfg_r00_q20_i = 22'sd1;
        cfg_r11_q20_i = 22'sd1;
        cfg_r22_q20_i = 22'sd1;
        send_and_expect(16'h1002, 27'sd524288, -27'sd524288, 27'sd0,
                        27'sd1, -27'sd1, 27'sd0, 1'b0);

        // Saturation and overflow use the same rounded value.
        cfg_r00_q20_i = 22'sd2097151;
        cfg_r11_q20_i = 22'sd2097151;
        cfg_r22_q20_i = 22'sd1048576;
        send_and_expect(16'h1003, 27'sd67108863, -27'sd67108864, 27'sd0,
                        27'sd67108863, -27'sd67108864, 27'sd0, 1'b1);

        // Registered result must remain stable under backpressure.
        m_ready_i = 1'b0;
        cfg_r00_q20_i = 22'sd1048576;
        cfg_r11_q20_i = 22'sd1048576;
        while (!s_ready_o) tick();
        s_meta_i = 16'hcafe;
        s_world_x_q16_i = 27'sd7;
        s_world_y_q16_i = -27'sd9;
        s_world_z_q16_i = 27'sd11;
        s_valid_i = 1'b1;
        tick();
        s_valid_i = 1'b0;
        while (!m_valid_o) tick();
        repeat (3) begin
            if (m_meta_o !== 16'hcafe || m_camera_x_q16_o !== 27'sd7 ||
                m_camera_y_q16_o !== -27'sd9 || m_camera_z_q16_o !== 27'sd11 ||
                m_overflow_o)
                $fatal(1, "world transform output changed while stalled");
            tick();
        end
        m_ready_i = 1'b1;
        tick();

        $display("PASS: tb_world_to_camera_core");
        $finish;
    end
endmodule
