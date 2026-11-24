// PSD-preserving alpha pipeline using block-float Cholesky factors.
// dx/dy: signed Q5.10; l00/l11: unsigned Q3.12; l10: signed Q3.12;
// opacity/alpha: Q1.12. Coordinate and factor shifts are powers of two.
module alpha_block_float_core #(
    parameter int unsigned META_W = 104
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic                  s_valid_i,
    output logic                  s_ready_o,
    input  logic [META_W-1:0]     s_meta_i,
    input  logic signed [15:0]    s_dx_q10_i,
    input  logic signed [15:0]    s_dy_q10_i,
    input  logic [14:0]           s_l00_q12_i,
    input  logic signed [15:0]    s_l10_q12_i,
    input  logic [14:0]           s_l11_q12_i,
    input  logic signed [5:0]     s_coordinate_shift_i,
    input  logic signed [5:0]     s_factor_shift_i,
    input  logic [12:0]           s_opacity_q12_i,
    output logic                  m_valid_o,
    input  logic                  m_ready_i,
    output logic [META_W-1:0]     m_meta_o,
    output logic [12:0]           m_alpha_q12_o,
    output logic                  m_pass_alpha_o
);
    localparam int unsigned AXIS_W = 15; // signed Q4.10
    localparam int unsigned S0_W = META_W + 13 + 2*AXIS_W;
    localparam int unsigned S1_W = META_W + 13 + 8;
    localparam int unsigned S2_W = META_W + 13 + 13;
    localparam logic [12:0] ALPHA_MAX_Q12 = 13'd4055;
    localparam logic [12:0] ALPHA_THRESHOLD_Q12 = 13'd16;

    logic signed [31:0] product00, product10, product11;
    logic signed [32:0] axis0_product, axis1_product;
    logic signed [6:0] result_shift;
    logic signed [AXIS_W-1:0] axis0_q10, axis1_q10;
    logic s0_valid, s0_ready;
    logic [S0_W-1:0] s0_data;
    logic [META_W-1:0] s0_meta;
    logic [12:0] s0_opacity;
    logic signed [AXIS_W-1:0] s0_axis0, s0_axis1;
    logic [29:0] axis0_square, axis1_square;
    logic [30:0] quadratic_q20;
    logic [21:0] magnitude_wide;
    logic [15:0] magnitude_q12;
    logic [23:0] lut_scale_product;
    logic [7:0] lut_index;
    logic s1_valid, s1_ready;
    logic [S1_W-1:0] s1_data;
    logic [META_W-1:0] s1_meta;
    logic [12:0] s1_opacity;
    logic [7:0] s1_lut_index;
    logic [12:0] exp_q12;
    logic s2_valid, s2_ready;
    logic [S2_W-1:0] s2_data;
    logic [META_W-1:0] s2_meta;
    logic [12:0] s2_opacity, s2_exp;
    logic [25:0] alpha_product_q24;
    logic [13:0] rounded_alpha_q12;
    logic [12:0] saturated_alpha_q12;
    logic [META_W+13:0] result_input;

    function automatic logic signed [AXIS_W-1:0] scale_axis(
        input logic signed [32:0] value,
        input logic signed [6:0] shift
    );
        logic signed [63:0] extended, shifted, rounding;
        integer right_shift;
        begin
            extended = {{31{value[32]}}, value};
            if (shift >= 7'sd12) begin
                if ((shift - 7'sd12) >= 7'sd31)
                    shifted = value[32] ? -64'sd16384 : 64'sd16383;
                else
                    shifted = extended <<< (shift - 7'sd12);
            end else begin
                right_shift = 12 - shift;
                if (right_shift >= 63)
                    shifted = '0;
                else if (right_shift == 0)
                    shifted = extended;
                else begin
                    rounding = 64'sd1 <<< (right_shift - 1);
                    shifted = extended >= 0
                        ? (extended + rounding) >>> right_shift
                        : -(((-extended) + rounding) >>> right_shift);
                end
            end
            if (shifted > 64'sd16383) scale_axis = 15'sd16383;
            else if (shifted < -64'sd16384) scale_axis = -15'sd16384;
            else scale_axis = shifted[AXIS_W-1:0];
        end
    endfunction

`include "alpha_exp_lut_256.svh"

    assign product00 = $signed(s_dx_q10_i) * $signed({1'b0, s_l00_q12_i});
    assign product10 = $signed(s_dy_q10_i) * $signed(s_l10_q12_i);
    assign product11 = $signed(s_dy_q10_i) * $signed({1'b0, s_l11_q12_i});
    assign axis0_product = $signed(product00) + $signed(product10);
    assign axis1_product = {{1{product11[31]}}, product11};
    assign result_shift = s_coordinate_shift_i + s_factor_shift_i;
    assign axis0_q10 = scale_axis(axis0_product, result_shift);
    assign axis1_q10 = scale_axis(axis1_product, result_shift);

    rv_reg_slice #(.DATA_W(S0_W)) u_axis_stage (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .s_valid_i(s_valid_i), .s_ready_o(s_ready_o),
        .s_data_i({s_meta_i, s_opacity_q12_i, axis0_q10, axis1_q10}),
        .m_valid_o(s0_valid), .m_ready_i(s0_ready), .m_data_o(s0_data)
    );
    assign {s0_meta, s0_opacity, s0_axis0, s0_axis1} = s0_data;
    assign axis0_square = $signed(s0_axis0) * $signed(s0_axis0);
    assign axis1_square = $signed(s0_axis1) * $signed(s0_axis1);
    assign quadratic_q20 = {1'b0, axis0_square} + {1'b0, axis1_square};
    assign magnitude_wide = (quadratic_q20 + 31'd256) >> 9;
    assign magnitude_q12 = |magnitude_wide[21:16] ? 16'hffff : magnitude_wide[15:0];
    assign lut_scale_product = magnitude_q12 * 8'd255;
    assign lut_index = magnitude_q12 >= 16'hffff
        ? 8'd0 : 8'd255 - ((lut_scale_product + 24'd32768) >> 16);

    rv_reg_slice #(.DATA_W(S1_W)) u_quadratic_stage (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .s_valid_i(s0_valid), .s_ready_o(s0_ready),
        .s_data_i({s0_meta, s0_opacity, lut_index}),
        .m_valid_o(s1_valid), .m_ready_i(s1_ready), .m_data_o(s1_data)
    );
    assign {s1_meta, s1_opacity, s1_lut_index} = s1_data;
    assign exp_q12 = exp_lut_q12(s1_lut_index);

    rv_reg_slice #(.DATA_W(S2_W)) u_exp_stage (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .s_valid_i(s1_valid), .s_ready_o(s1_ready),
        .s_data_i({s1_meta, s1_opacity, exp_q12}),
        .m_valid_o(s2_valid), .m_ready_i(s2_ready), .m_data_o(s2_data)
    );
    assign {s2_meta, s2_opacity, s2_exp} = s2_data;
    assign alpha_product_q24 = s2_opacity * s2_exp;
    assign rounded_alpha_q12 = (alpha_product_q24 + 26'd2048) >> 12;
    assign saturated_alpha_q12 = rounded_alpha_q12 > ALPHA_MAX_Q12
        ? ALPHA_MAX_Q12 : rounded_alpha_q12[12:0];
    assign result_input = {s2_meta, saturated_alpha_q12,
                           saturated_alpha_q12 >= ALPHA_THRESHOLD_Q12};

    rv_reg_slice #(.DATA_W(META_W+14)) u_alpha_stage (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .s_valid_i(s2_valid), .s_ready_o(s2_ready), .s_data_i(result_input),
        .m_valid_o(m_valid_o), .m_ready_i(m_ready_i),
        .m_data_o({m_meta_o, m_alpha_q12_o, m_pass_alpha_o})
    );

`ifndef SYNTHESIS
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        m_valid_o && !m_ready_i
        |=> m_valid_o && $stable({m_meta_o, m_alpha_q12_o, m_pass_alpha_o}));
`endif
endmodule
