`timescale 1ns/1ps

module tb_perspective_project_core;
    localparam int META_W=16;
    logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o;
    logic [META_W-1:0] s_meta_i='0;
    logic signed [26:0] s_camera_x_q16_i='0,s_camera_y_q16_i='0,s_camera_z_q16_i=27'sd65536;
    logic s_transform_overflow_i=0;
    logic signed [32:0] cfg_fx_q16_i=0,cfg_fy_q16_i=0;
    logic signed [32:0] cfg_cx_q16_i=0,cfg_cy_q16_i=0;
    logic signed [26:0] cfg_near_q16_i=27'sd1,cfg_far_q16_i=27'sd67108863;
    logic m_valid_o,m_ready_i=1;
    logic [META_W-1:0] m_meta_o;
    logic signed [26:0] m_screen_x_q8_o,m_screen_y_q8_o,m_depth_q16_o;
    logic m_visible_o,m_numeric_overflow_o;

    always #5 clk_i=~clk_i;
    perspective_project_core #(.META_W(META_W)) dut(.*);
    task automatic tick;begin @(posedge clk_i);#1;end endtask
    task automatic send_and_wait;integer timeout;begin
        while(!s_ready_o)tick();s_valid_i=1;tick();s_valid_i=0;
        timeout=0;while(!m_valid_o&&timeout<100)begin tick();timeout=timeout+1;end
        if(!m_valid_o)$fatal(1,"perspective timeout");
    end endtask

    initial begin
        repeat(2)tick();rst_ni=1;tick();

        // Normal Q16 principal-point conversion.
        s_meta_i=16'h1001;cfg_cx_q16_i=33'sd2097152;cfg_cy_q16_i=33'sd1572864;
        send_and_wait();
        if(m_meta_o!==16'h1001||m_screen_x_q8_o!==27'sd8192
           ||m_screen_y_q8_o!==27'sd6144||!m_visible_o||m_numeric_overflow_o)
            $fatal(1,"principal projection mismatch xy=%0d,%0d flags=%b,%b",
                   m_screen_x_q8_o,m_screen_y_q8_o,m_visible_o,m_numeric_overflow_o);
        tick();

        // Only X overflows: X saturates, Y must retain its valid value.
        s_meta_i=16'h1002;cfg_fx_q16_i=33'sd3932160000;cfg_fy_q16_i=0;
        s_camera_x_q16_i=27'sd262144;s_camera_y_q16_i=0;
        cfg_cx_q16_i=33'sd4294967295;cfg_cy_q16_i=33'sd65536;
        send_and_wait();
        if(m_meta_o!==16'h1002||m_screen_x_q8_o!==27'sd67108863
           ||m_screen_y_q8_o!==27'sd256||m_visible_o||!m_numeric_overflow_o)
            $fatal(1,"independent axis saturation mismatch xy=%0d,%0d flags=%b,%b",
                   m_screen_x_q8_o,m_screen_y_q8_o,m_visible_o,m_numeric_overflow_o);
        tick();

        // Negative Y overflow must not corrupt an in-range X coordinate.
        s_meta_i=16'h1003;cfg_fx_q16_i=0;cfg_fy_q16_i=33'sd3932160000;
        s_camera_x_q16_i=0;s_camera_y_q16_i=-27'sd262144;
        cfg_cx_q16_i=-33'sd65536;cfg_cy_q16_i=-33'sd4294967296;
        send_and_wait();
        if(m_screen_x_q8_o!==-27'sd256||m_screen_y_q8_o!==-27'sd67108864
           ||m_visible_o||!m_numeric_overflow_o)
            $fatal(1,"negative saturation mismatch xy=%0d,%0d flags=%b,%b",
                   m_screen_x_q8_o,m_screen_y_q8_o,m_visible_o,m_numeric_overflow_o);
        tick();

        $display("PASS: tb_perspective_project_core");$finish;
    end
endmodule
