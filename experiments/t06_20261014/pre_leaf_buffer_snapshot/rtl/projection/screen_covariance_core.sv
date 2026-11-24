// Project a camera-space 3D covariance into screen space using the perspective
// Jacobian. Covariance input is signed Q20.20. Output is signed/unsigned Q27.8.
// Two fully pipelined divider pairs compute fx/z, fy/z, -fx*x/z^2 and
// -fy*y/z^2. A complete metadata packet crosses both dividers atomically.
module screen_covariance_core #(
    parameter int unsigned META_W = 64,
    parameter int unsigned COORD_W = 27,
    parameter int unsigned COV3_W = 41,
    parameter int unsigned COV2_W = 35,
    parameter int unsigned INTR_W = 33,
    // Real near-plane Bonsai views require a signed 33-bit Q*.16 j02 term
    // (max observed magnitude 2,549,914,624).  One guard bit prevents the
    // restoring divider from saturating before covariance formation.
    parameter int unsigned JAC_W = 34,
    parameter int unsigned JAC_FRAC_W = 16,
    parameter int unsigned COV3_FRAC_W = 20
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic                         s_valid_i,
    output logic                         s_ready_o,
    input  logic [META_W-1:0]            s_meta_i,
    input  logic signed [COORD_W-1:0]    s_camera_x_q16_i,
    input  logic signed [COORD_W-1:0]    s_camera_y_q16_i,
    input  logic signed [COORD_W-1:0]    s_camera_z_q16_i,
    input  logic signed [COV3_W-1:0]     s_cov_xx_q16_i,
    input  logic signed [COV3_W-1:0]     s_cov_xy_q16_i,
    input  logic signed [COV3_W-1:0]     s_cov_xz_q16_i,
    input  logic signed [COV3_W-1:0]     s_cov_yy_q16_i,
    input  logic signed [COV3_W-1:0]     s_cov_yz_q16_i,
    input  logic signed [COV3_W-1:0]     s_cov_zz_q16_i,
    input  logic signed [INTR_W-1:0]     cfg_fx_q16_i,
    input  logic signed [INTR_W-1:0]     cfg_fy_q16_i,
    input  logic        [COV2_W-1:0]     cfg_regularizer_q8_i,
    output logic                         m_valid_o,
    input  logic                         m_ready_i,
    output logic [META_W-1:0]            m_meta_o,
    output logic        [COV2_W-1:0]     m_cov00_q8_o,
    output logic signed [COV2_W-1:0]     m_cov01_q8_o,
    output logic        [COV2_W-1:0]     m_cov11_q8_o,
    output logic                         m_numeric_overflow_o
);
    localparam int unsigned FX_NUM_W = INTR_W + 16;
    localparam int unsigned FIRST_META_W = META_W + 3*COORD_W + 6*COV3_W;
    // Camera coordinates are consumed when launching the second divide and do
    // not need to toggle through its pipeline.  Carry only the final metadata,
    // covariance and diagonal Jacobian terms after that boundary.
    localparam int unsigned SECOND_META_W = META_W + 6*COV3_W + 2*JAC_W + 1;
    localparam int unsigned JX_NUM_W = JAC_W + COORD_W;
    localparam int unsigned PRODUCT_W = JAC_W + COV3_W;
    localparam int unsigned ROW_W = PRODUCT_W + 1;
    localparam int unsigned COV_PRODUCT_W = ROW_W + JAC_W;
    localparam int unsigned COV_ACC_W = COV_PRODUCT_W + 1;
    localparam int unsigned COV_TO_Q8_SHIFT =
        2*JAC_FRAC_W + COV3_FRAC_W - 8;
    localparam int unsigned RESULT_W = META_W + 3*COV2_W + 1;

    logic signed [FX_NUM_W-1:0] fx_scaled_q32, fy_scaled_q32;
    logic jac1_valid, jac1_ready;
    logic [FIRST_META_W-1:0] jac1_meta;
    logic signed [JAC_W-1:0] j00_q16, j11_q16;
    logic jac1_div_zero, jac1_overflow;
    logic signed [COORD_W-1:0] camera_x1, camera_y1, camera_z1;
    logic signed [JX_NUM_W-1:0] j02_numerator, j12_numerator;
    logic jac2_valid, jac2_ready;
    logic [SECOND_META_W-1:0] jac2_meta;
    logic signed [JAC_W-1:0] j02_q16, j12_q16;
    logic jac2_div_zero, jac2_overflow;
    logic signed [JAC_W-1:0] j00_2, j11_2;
    logic jac1_error2;
    logic [META_W-1:0] meta2;
    logic signed [COV3_W-1:0] cov_xx2, cov_xy2, cov_xz2, cov_yy2, cov_yz2, cov_zz2;

    logic signed [PRODUCT_W-1:0] j00_xx, j02_xz, j00_xy, j02_yz, j00_xz, j02_zz;
    logic signed [PRODUCT_W-1:0] j11_yy, j12_yz, j11_yz, j12_zz;
    logic signed [ROW_W-1:0] row0_x, row0_y, row0_z;
    logic signed [ROW_W-1:0] row1_y, row1_z;
    logic signed [COV_PRODUCT_W-1:0] cov00_p0,cov00_p1,cov01_p0,cov01_p1,cov11_p0,cov11_p1;
    logic signed [COV_ACC_W-1:0] cov00_q48, cov01_q48, cov11_q48;
    logic signed [COV_ACC_W-1:0] cov00_q8_wide, cov01_q8_wide, cov11_q8_wide;
    logic signed [COV_ACC_W-1:0] cov00_regularized, cov11_regularized;
    logic [COV2_W-1:0] cov00_sat, cov11_sat;
    logic signed [COV2_W-1:0] cov01_sat;
    logic cov00_overflow, cov01_overflow, cov11_overflow;
    logic [RESULT_W-1:0] result_data;

    function automatic logic signed [ROW_W-1:0] sum2_product(
        input logic signed [PRODUCT_W-1:0] a,b
    );
        begin
            sum2_product={{(ROW_W-PRODUCT_W){a[PRODUCT_W-1]}},a}
                +{{(ROW_W-PRODUCT_W){b[PRODUCT_W-1]}},b};
        end
    endfunction

    function automatic logic signed [COV_PRODUCT_W-1:0] mul_row_jac(
        input logic signed [ROW_W-1:0] a,
        input logic signed [JAC_W-1:0] b
    );
        begin mul_row_jac=a*b;end
    endfunction

    function automatic logic signed [COV_ACC_W-1:0] sum2_cov_product(
        input logic signed [COV_PRODUCT_W-1:0] a,b
    );
        begin
            sum2_cov_product={{(COV_ACC_W-COV_PRODUCT_W){a[COV_PRODUCT_W-1]}},a}
                +{{(COV_ACC_W-COV_PRODUCT_W){b[COV_PRODUCT_W-1]}},b};
        end
    endfunction

    function automatic logic signed [COV_ACC_W-1:0] round_cov_to_q8(
        input logic signed [COV_ACC_W-1:0] value
    );
        logic signed [COV_ACC_W-1:0] magnitude;
        begin
            if (value >= 0)
                round_cov_to_q8 = (value
                    + ({{(COV_ACC_W-1){1'b0}},1'b1}
                       <<< (COV_TO_Q8_SHIFT-1))) >>> COV_TO_Q8_SHIFT;
            else begin
                magnitude = -value;
                round_cov_to_q8 = -((magnitude
                    + ({{(COV_ACC_W-1){1'b0}},1'b1}
                       <<< (COV_TO_Q8_SHIFT-1))) >>> COV_TO_Q8_SHIFT);
            end
        end
    endfunction

    function automatic logic unsigned_overflow(
        input logic signed [COV_ACC_W-1:0] value
    );
        logic signed [COV_ACC_W-1:0] maximum;
        begin
            maximum = ({{(COV_ACC_W-1){1'b0}},1'b1} <<< COV2_W) - 1;
            unsigned_overflow = value < 0 || value > maximum;
        end
    endfunction

    function automatic logic signed_overflow(
        input logic signed [COV_ACC_W-1:0] value
    );
        logic signed [COV_ACC_W-1:0] maximum, minimum;
        begin
            maximum = ({{(COV_ACC_W-1){1'b0}},1'b1} <<< (COV2_W-1)) - 1;
            minimum = -({{(COV_ACC_W-1){1'b0}},1'b1} <<< (COV2_W-1));
            signed_overflow = value > maximum || value < minimum;
        end
    endfunction

    function automatic logic [COV2_W-1:0] saturate_unsigned(
        input logic signed [COV_ACC_W-1:0] value
    );
        begin
            if (value <= 0)
                saturate_unsigned = '0;
            else if (unsigned_overflow(value))
                saturate_unsigned = {COV2_W{1'b1}};
            else
                saturate_unsigned = value[COV2_W-1:0];
        end
    endfunction

    function automatic logic signed [COV2_W-1:0] saturate_signed(
        input logic signed [COV_ACC_W-1:0] value
    );
        begin
            if (!signed_overflow(value))
                saturate_signed = value[COV2_W-1:0];
            else if (value < 0)
                saturate_signed = {1'b1, {(COV2_W-1){1'b0}}};
            else
                saturate_signed = {1'b0, {(COV2_W-1){1'b1}}};
        end
    endfunction

    assign fx_scaled_q32 = $signed({{(FX_NUM_W-INTR_W){cfg_fx_q16_i[INTR_W-1]}},
                                     cfg_fx_q16_i}) <<< 16;
    assign fy_scaled_q32 = $signed({{(FX_NUM_W-INTR_W){cfg_fy_q16_i[INTR_W-1]}},
                                     cfg_fy_q16_i}) <<< 16;

    fixed_div_pipe2 #(
        .NUM_W(FX_NUM_W), .DEN_W(COORD_W), .QUOT_W(JAC_W),
        .META_W(FIRST_META_W)
    ) u_jacobian_div_z (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .s_valid_i(s_valid_i), .s_ready_o(s_ready_o),
        .s_num0_i(fx_scaled_q32), .s_num1_i(fy_scaled_q32),
        .s_den_i(s_camera_z_q16_i[COORD_W-1] ? {COORD_W{1'b0}} : s_camera_z_q16_i),
        .s_meta_i({s_meta_i, s_camera_x_q16_i, s_camera_y_q16_i, s_camera_z_q16_i,
                   s_cov_xx_q16_i, s_cov_xy_q16_i, s_cov_xz_q16_i,
                   s_cov_yy_q16_i, s_cov_yz_q16_i, s_cov_zz_q16_i}),
        .m_valid_o(jac1_valid), .m_ready_i(jac1_ready),
        .m_quot0_o(j00_q16), .m_quot1_o(j11_q16), .m_meta_o(jac1_meta),
        .m_div_zero_o(jac1_div_zero), .m_overflow_o(jac1_overflow)
    );
    assign {camera_x1,camera_y1,camera_z1}=
        jac1_meta[FIRST_META_W-META_W-1-:3*COORD_W];
    assign j02_numerator = -($signed(j00_q16) * $signed(camera_x1));
    assign j12_numerator = -($signed(j11_q16) * $signed(camera_y1));

    fixed_div_pipe2 #(
        .NUM_W(JX_NUM_W), .DEN_W(COORD_W), .QUOT_W(JAC_W),
        .META_W(SECOND_META_W)
    ) u_jacobian_div_z2 (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .s_valid_i(jac1_valid), .s_ready_o(jac1_ready),
        .s_num0_i(j02_numerator), .s_num1_i(j12_numerator),
        .s_den_i(camera_z1[COORD_W-1] ? {COORD_W{1'b0}} : camera_z1),
        .s_meta_i({jac1_meta[FIRST_META_W-1-:META_W],
                   jac1_meta[6*COV3_W-1:0],j00_q16,j11_q16,
                   jac1_div_zero || jac1_overflow}),
        .m_valid_o(jac2_valid), .m_ready_i(jac2_ready),
        .m_quot0_o(j02_q16), .m_quot1_o(j12_q16), .m_meta_o(jac2_meta),
        .m_div_zero_o(jac2_div_zero), .m_overflow_o(jac2_overflow)
    );
    assign {meta2,cov_xx2,cov_xy2,cov_xz2,cov_yy2,cov_yz2,cov_zz2,
            j00_2,j11_2,jac1_error2}=jac2_meta;

    assign j00_xx = j00_2 * cov_xx2;
    assign j02_xz = j02_q16 * cov_xz2;
    assign j00_xy = j00_2 * cov_xy2;
    assign j02_yz = j02_q16 * cov_yz2;
    assign j00_xz = j00_2 * cov_xz2;
    assign j02_zz = j02_q16 * cov_zz2;
    assign j11_yy = j11_2 * cov_yy2;
    assign j12_yz = j12_q16 * cov_yz2;
    assign j11_yz = j11_2 * cov_yz2;
    assign j12_zz = j12_q16 * cov_zz2;
    assign row0_x=sum2_product(j00_xx,j02_xz);
    assign row0_y=sum2_product(j00_xy,j02_yz);
    assign row0_z=sum2_product(j00_xz,j02_zz);
    assign row1_y=sum2_product(j11_yy,j12_yz);
    assign row1_z=sum2_product(j11_yz,j12_zz);
    assign cov00_p0=mul_row_jac(row0_x,j00_2);assign cov00_p1=mul_row_jac(row0_z,j02_q16);
    assign cov01_p0=mul_row_jac(row0_y,j11_2);assign cov01_p1=mul_row_jac(row0_z,j12_q16);
    assign cov11_p0=mul_row_jac(row1_y,j11_2);assign cov11_p1=mul_row_jac(row1_z,j12_q16);
    assign cov00_q48=sum2_cov_product(cov00_p0,cov00_p1);
    assign cov01_q48=sum2_cov_product(cov01_p0,cov01_p1);
    assign cov11_q48=sum2_cov_product(cov11_p0,cov11_p1);
    assign cov00_q8_wide = round_cov_to_q8(cov00_q48);
    assign cov01_q8_wide = round_cov_to_q8(cov01_q48);
    assign cov11_q8_wide = round_cov_to_q8(cov11_q48);
    assign cov00_regularized=cov00_q8_wide+
        $signed({{(COV_ACC_W-COV2_W){1'b0}},cfg_regularizer_q8_i});
    assign cov11_regularized=cov11_q8_wide+
        $signed({{(COV_ACC_W-COV2_W){1'b0}},cfg_regularizer_q8_i});
    assign cov00_overflow = unsigned_overflow(cov00_regularized);
    assign cov01_overflow = signed_overflow(cov01_q8_wide);
    assign cov11_overflow = unsigned_overflow(cov11_regularized);
    assign cov00_sat = saturate_unsigned(cov00_regularized);
    assign cov01_sat = saturate_signed(cov01_q8_wide);
    assign cov11_sat = saturate_unsigned(cov11_regularized);
    assign result_data = {meta2, cov00_sat, cov01_sat, cov11_sat,
                          jac1_error2 || jac2_div_zero || jac2_overflow
                          || cov00_overflow || cov01_overflow || cov11_overflow};

    rv_reg_slice #(.DATA_W(RESULT_W)) u_result (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .s_valid_i(jac2_valid), .s_ready_o(jac2_ready), .s_data_i(result_data),
        .m_valid_o(m_valid_o), .m_ready_i(m_ready_i),
        .m_data_o({m_meta_o, m_cov00_q8_o, m_cov01_q8_o,
                   m_cov11_q8_o, m_numeric_overflow_o})
    );
endmodule
