`timescale 1ns/1ps

module tb_projection_primitives;
    logic clk_i=0, rst_ni=0;
    logic s_valid_i=0, s_ready_o;
    logic [15:0] s_meta_i='0;
    logic signed [26:0] s_world_x_q16_i='0,s_world_y_q16_i='0,s_world_z_q16_i='0;
    logic signed [21:0] cfg_r00_q20_i=22'sd1048576,cfg_r01_q20_i=0,cfg_r02_q20_i=0;
    logic signed [21:0] cfg_r10_q20_i=0,cfg_r11_q20_i=22'sd1048576,cfg_r12_q20_i=0;
    logic signed [21:0] cfg_r20_q20_i=0,cfg_r21_q20_i=0,cfg_r22_q20_i=22'sd1048576;
    logic signed [26:0] cfg_tx_q16_i=27'sd65536,cfg_ty_q16_i=-27'sd131072,cfg_tz_q16_i=27'sd196608;
    logic transform_valid, transform_ready;
    logic [15:0] transform_meta;
    logic signed [26:0] camera_x,camera_y,camera_z;
    logic transform_overflow;
    logic signed [32:0] cfg_fx_q16_i=33'sd65536000,cfg_fy_q16_i=33'sd65536000;
    logic signed [32:0] cfg_cx_q16_i=33'sd2097152,cfg_cy_q16_i=33'sd1572864;
    logic signed [26:0] cfg_near_q16_i=27'sd13107,cfg_far_q16_i=27'sd65536000;
    logic m_valid_o,m_ready_i=1;
    logic [15:0] m_meta_o;
    logic signed [26:0] m_screen_x_q8_o,m_screen_y_q8_o,m_depth_q16_o;
    logic m_visible_o,m_numeric_overflow_o;

    always #5 clk_i=~clk_i;
    world_to_camera_core #(.META_W(16)) u_transform(
        .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i),.s_ready_o(s_ready_o),
        .s_meta_i(s_meta_i),.s_world_x_q16_i(s_world_x_q16_i),
        .s_world_y_q16_i(s_world_y_q16_i),.s_world_z_q16_i(s_world_z_q16_i),
        .cfg_r00_q20_i(cfg_r00_q20_i),.cfg_r01_q20_i(cfg_r01_q20_i),.cfg_r02_q20_i(cfg_r02_q20_i),
        .cfg_r10_q20_i(cfg_r10_q20_i),.cfg_r11_q20_i(cfg_r11_q20_i),.cfg_r12_q20_i(cfg_r12_q20_i),
        .cfg_r20_q20_i(cfg_r20_q20_i),.cfg_r21_q20_i(cfg_r21_q20_i),.cfg_r22_q20_i(cfg_r22_q20_i),
        .cfg_tx_q16_i(cfg_tx_q16_i),.cfg_ty_q16_i(cfg_ty_q16_i),.cfg_tz_q16_i(cfg_tz_q16_i),
        .m_valid_o(transform_valid),.m_ready_i(transform_ready),.m_meta_o(transform_meta),
        .m_camera_x_q16_o(camera_x),.m_camera_y_q16_o(camera_y),.m_camera_z_q16_o(camera_z),
        .m_overflow_o(transform_overflow));
    perspective_project_core #(.META_W(16)) u_project(
        .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(transform_valid),.s_ready_o(transform_ready),
        .s_meta_i(transform_meta),.s_camera_x_q16_i(camera_x),.s_camera_y_q16_i(camera_y),
        .s_camera_z_q16_i(camera_z),.s_transform_overflow_i(transform_overflow),
        .cfg_fx_q16_i(cfg_fx_q16_i),.cfg_fy_q16_i(cfg_fy_q16_i),
        .cfg_cx_q16_i(cfg_cx_q16_i),.cfg_cy_q16_i(cfg_cy_q16_i),
        .cfg_near_q16_i(cfg_near_q16_i),.cfg_far_q16_i(cfg_far_q16_i),
        .m_valid_o(m_valid_o),.m_ready_i(m_ready_i),.m_meta_o(m_meta_o),
        .m_screen_x_q8_o(m_screen_x_q8_o),.m_screen_y_q8_o(m_screen_y_q8_o),
        .m_depth_q16_o(m_depth_q16_o),.m_visible_o(m_visible_o),
        .m_numeric_overflow_o(m_numeric_overflow_o));

    task automatic tick; begin @(posedge clk_i);#1;end endtask
    initial begin
        integer timeout;
        repeat(2)tick();rst_ni=1;tick();
        // World (1,4,5) plus translation (1,-2,3) -> camera (2,2,8).
        // With f=1000 and principal point (32,24), screen=(282,274).
        s_meta_i=16'h1234;s_world_x_q16_i=27'sd65536;
        s_world_y_q16_i=27'sd262144;s_world_z_q16_i=27'sd327680;
        s_valid_i=1;tick();s_valid_i=0;
        timeout=0;while(!m_valid_o&&timeout<60)begin tick();timeout=timeout+1;end
        if(!m_valid_o||m_meta_o!==16'h1234||m_screen_x_q8_o!==27'sd72192
           ||m_screen_y_q8_o!==27'sd70144||m_depth_q16_o!==27'sd524288
           ||!m_visible_o||m_numeric_overflow_o)
            $fatal(1,"projection primitive mismatch meta=%h xy=%0d,%0d z=%0d flags=%b,%b",
                   m_meta_o,m_screen_x_q8_o,m_screen_y_q8_o,m_depth_q16_o,
                   m_visible_o,m_numeric_overflow_o);
        tick();
        $display("PASS: tb_projection_primitives");$finish;
    end
endmodule
