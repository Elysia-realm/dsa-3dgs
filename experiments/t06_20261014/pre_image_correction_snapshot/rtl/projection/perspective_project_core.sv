// Camera-space mean projection. Inputs are signed Q10.16; focal length and
// principal point are signed Q16.16. Output screen coordinates are signed
// Q18.8 to preserve extreme off-screen values seen in real scenes.
module perspective_project_core #(
    parameter int unsigned META_W = 64,
    parameter int unsigned COORD_W = 27,
    parameter int unsigned SCREEN_W = 27,
    parameter int unsigned SCREEN_FRAC = 8,
    parameter int unsigned INTR_W = 33
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic                         s_valid_i,
    output logic                         s_ready_o,
    input  logic [META_W-1:0]            s_meta_i,
    input  logic signed [COORD_W-1:0]    s_camera_x_q16_i,
    input  logic signed [COORD_W-1:0]    s_camera_y_q16_i,
    input  logic signed [COORD_W-1:0]    s_camera_z_q16_i,
    input  logic                         s_transform_overflow_i,
    input  logic signed [INTR_W-1:0]     cfg_fx_q16_i,
    input  logic signed [INTR_W-1:0]     cfg_fy_q16_i,
    input  logic signed [INTR_W-1:0]     cfg_cx_q16_i,
    input  logic signed [INTR_W-1:0]     cfg_cy_q16_i,
    input  logic signed [COORD_W-1:0]    cfg_near_q16_i,
    input  logic signed [COORD_W-1:0]    cfg_far_q16_i,
    output logic                         m_valid_o,
    input  logic                         m_ready_i,
    output logic [META_W-1:0]            m_meta_o,
    output logic signed [SCREEN_W-1:0]   m_screen_x_q8_o,
    output logic signed [SCREEN_W-1:0]   m_screen_y_q8_o,
    output logic signed [COORD_W-1:0]    m_depth_q16_o,
    output logic                         m_visible_o,
    output logic                         m_numeric_overflow_o
);
    localparam int unsigned NUM_W = COORD_W + INTR_W;
    localparam int unsigned DIV_META_W = META_W + COORD_W + 2;
    localparam int unsigned SCREEN_ADD_W = INTR_W + 1;
    localparam logic signed [SCREEN_ADD_W-1:0] SCREEN_MAX = {
        {(SCREEN_ADD_W-SCREEN_W){1'b0}},1'b0,{(SCREEN_W-1){1'b1}}
    };
    localparam logic signed [SCREEN_ADD_W-1:0] SCREEN_MIN = {
        {(SCREEN_ADD_W-SCREEN_W){1'b1}},1'b1,{(SCREEN_W-1){1'b0}}
    };
    logic signed [NUM_W-1:0] product_x, product_y;
    logic signed [NUM_W-1:0] numerator_x, numerator_y;
    logic [COORD_W-1:0] positive_depth;
    logic divider_valid, divider_ready;
    logic [DIV_META_W-1:0] divider_meta;
    logic signed [SCREEN_W-1:0] offset_x_q8, offset_y_q8;
    logic divider_zero, divider_overflow;
    logic signed [SCREEN_ADD_W-1:0] offset_x_extended, offset_y_extended;
    logic signed [SCREEN_ADD_W-1:0] principal_x_q8, principal_y_q8;
    logic signed [SCREEN_ADD_W-1:0] screen_x_wide, screen_y_wide;
    logic signed [SCREEN_W-1:0] screen_x_sat, screen_y_sat;
    logic [META_W-1:0] divided_meta;
    logic signed [COORD_W-1:0] divided_depth;
    logic divided_transform_overflow;
    logic divided_depth_visible;
    logic input_visible;
    logic screen_x_overflow, screen_y_overflow, screen_overflow;
    logic [META_W + 2*SCREEN_W + COORD_W + 1:0] result_data;

    assign product_x = $signed(s_camera_x_q16_i) * $signed(cfg_fx_q16_i);
    assign product_y = $signed(s_camera_y_q16_i) * $signed(cfg_fy_q16_i);
    // Q32 / Q16 would produce Q16. Discard eight fractional bits before
    // division so the quotient directly uses the Q18.8 screen contract.
    assign numerator_x = product_x >>> (16-SCREEN_FRAC);
    assign numerator_y = product_y >>> (16-SCREEN_FRAC);
    assign positive_depth = s_camera_z_q16_i[COORD_W-1] ? '0 : s_camera_z_q16_i;
    assign input_visible = !s_transform_overflow_i
        && s_camera_z_q16_i >= cfg_near_q16_i
        && s_camera_z_q16_i <= cfg_far_q16_i
        && s_camera_z_q16_i > 0;

    fixed_div_pipe2 #(
        .NUM_W(NUM_W), .DEN_W(COORD_W), .QUOT_W(SCREEN_W),
        .META_W(DIV_META_W)
    ) u_divider (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .s_valid_i(s_valid_i), .s_ready_o(s_ready_o),
        .s_num0_i(numerator_x), .s_num1_i(numerator_y),
        .s_den_i(positive_depth),
        .s_meta_i({s_meta_i, s_camera_z_q16_i,
                   s_transform_overflow_i, input_visible}),
        .m_valid_o(divider_valid), .m_ready_i(divider_ready),
        .m_quot0_o(offset_x_q8), .m_quot1_o(offset_y_q8),
        .m_meta_o(divider_meta), .m_div_zero_o(divider_zero),
        .m_overflow_o(divider_overflow)
    );
    assign {divided_meta, divided_depth, divided_transform_overflow,
            divided_depth_visible} = divider_meta;
    assign offset_x_extended={{(SCREEN_ADD_W-SCREEN_W){offset_x_q8[SCREEN_W-1]}},offset_x_q8};
    assign offset_y_extended={{(SCREEN_ADD_W-SCREEN_W){offset_y_q8[SCREEN_W-1]}},offset_y_q8};
    assign principal_x_q8=$signed({{(SCREEN_ADD_W-INTR_W){cfg_cx_q16_i[INTR_W-1]}},cfg_cx_q16_i})
        >>> (16-SCREEN_FRAC);
    assign principal_y_q8=$signed({{(SCREEN_ADD_W-INTR_W){cfg_cy_q16_i[INTR_W-1]}},cfg_cy_q16_i})
        >>> (16-SCREEN_FRAC);
    assign screen_x_wide = offset_x_extended + principal_x_q8;
    assign screen_y_wide = offset_y_extended + principal_y_q8;
    assign screen_x_overflow = screen_x_wide > SCREEN_MAX || screen_x_wide < SCREEN_MIN;
    assign screen_y_overflow = screen_y_wide > SCREEN_MAX || screen_y_wide < SCREEN_MIN;
    assign screen_overflow = screen_x_overflow || screen_y_overflow;
    assign screen_x_sat = !screen_x_overflow ? screen_x_wide[SCREEN_W-1:0]
        : screen_x_wide[SCREEN_ADD_W-1]
            ? {1'b1, {(SCREEN_W-1){1'b0}}}
            : {1'b0, {(SCREEN_W-1){1'b1}}};
    assign screen_y_sat = !screen_y_overflow ? screen_y_wide[SCREEN_W-1:0]
        : screen_y_wide[SCREEN_ADD_W-1]
            ? {1'b1, {(SCREEN_W-1){1'b0}}}
            : {1'b0, {(SCREEN_W-1){1'b1}}};
    assign result_data = {
        divided_meta, screen_x_sat, screen_y_sat, divided_depth,
        divided_depth_visible
            && !(divided_transform_overflow || divider_zero || divider_overflow || screen_overflow),
        divided_transform_overflow || divider_zero || divider_overflow || screen_overflow
    };

    rv_reg_slice #(.DATA_W(META_W + 2*SCREEN_W + COORD_W + 2)) u_result (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .s_valid_i(divider_valid), .s_ready_o(divider_ready), .s_data_i(result_data),
        .m_valid_o(m_valid_o), .m_ready_i(m_ready_i),
        .m_data_o({m_meta_o, m_screen_x_q8_o, m_screen_y_q8_o,
                   m_depth_q16_o, m_visible_o, m_numeric_overflow_o})
    );
endmodule
