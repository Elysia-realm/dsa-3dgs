// World-space mean to camera-space mean. Coordinates use signed Q10.16 and
// rotation coefficients use signed Q2.20. Translation is signed Q10.16.
module world_to_camera_core #(
    parameter int unsigned META_W = 64,
    parameter int unsigned COORD_W = 27,
    parameter int unsigned ROT_W = 22,
    parameter int unsigned ROT_FRAC = 20
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic                         s_valid_i,
    output logic                         s_ready_o,
    input  logic [META_W-1:0]            s_meta_i,
    input  logic signed [COORD_W-1:0]    s_world_x_q16_i,
    input  logic signed [COORD_W-1:0]    s_world_y_q16_i,
    input  logic signed [COORD_W-1:0]    s_world_z_q16_i,
    input  logic signed [ROT_W-1:0]      cfg_r00_q20_i,
    input  logic signed [ROT_W-1:0]      cfg_r01_q20_i,
    input  logic signed [ROT_W-1:0]      cfg_r02_q20_i,
    input  logic signed [ROT_W-1:0]      cfg_r10_q20_i,
    input  logic signed [ROT_W-1:0]      cfg_r11_q20_i,
    input  logic signed [ROT_W-1:0]      cfg_r12_q20_i,
    input  logic signed [ROT_W-1:0]      cfg_r20_q20_i,
    input  logic signed [ROT_W-1:0]      cfg_r21_q20_i,
    input  logic signed [ROT_W-1:0]      cfg_r22_q20_i,
    input  logic signed [COORD_W-1:0]    cfg_tx_q16_i,
    input  logic signed [COORD_W-1:0]    cfg_ty_q16_i,
    input  logic signed [COORD_W-1:0]    cfg_tz_q16_i,
    output logic                         m_valid_o,
    input  logic                         m_ready_i,
    output logic [META_W-1:0]            m_meta_o,
    output logic signed [COORD_W-1:0]    m_camera_x_q16_o,
    output logic signed [COORD_W-1:0]    m_camera_y_q16_o,
    output logic signed [COORD_W-1:0]    m_camera_z_q16_o,
    output logic                         m_overflow_o
);
    localparam int unsigned PRODUCT_W = COORD_W + ROT_W;
    localparam int unsigned ACC_W = PRODUCT_W + 2;
    localparam int unsigned OUT_DATA_W = META_W + 3*COORD_W + 1;
    logic signed [PRODUCT_W-1:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    logic signed [ACC_W-1:0] acc_x, acc_y, acc_z;
    logic signed [ACC_W-1:0] tx_scaled, ty_scaled, tz_scaled;
    logic signed [ACC_W:0] shifted_x, shifted_y, shifted_z;
    logic signed [COORD_W-1:0] camera_x, camera_y, camera_z;
    logic overflow_x, overflow_y, overflow_z;
    logic [OUT_DATA_W-1:0] result_data;

    function automatic logic signed [ACC_W-1:0] sum_products_translation(
        input logic signed [PRODUCT_W-1:0] p0,
        input logic signed [PRODUCT_W-1:0] p1,
        input logic signed [PRODUCT_W-1:0] p2,
        input logic signed [ACC_W-1:0] translation
    );
        logic signed [ACC_W-1:0] p0_ext, p1_ext, p2_ext;
        begin
            p0_ext = {{(ACC_W-PRODUCT_W){p0[PRODUCT_W-1]}}, p0};
            p1_ext = {{(ACC_W-PRODUCT_W){p1[PRODUCT_W-1]}}, p1};
            p2_ext = {{(ACC_W-PRODUCT_W){p2[PRODUCT_W-1]}}, p2};
            sum_products_translation = p0_ext + p1_ext + p2_ext + translation;
        end
    endfunction

    function automatic logic signed [ACC_W:0] rounded_shift(
        input logic signed [ACC_W-1:0] value
    );
        logic signed [ACC_W:0] extended;
        logic signed [ACC_W:0] magnitude;
        begin
            extended = $signed({value[ACC_W-1], value});
            if (extended >= 0)
                rounded_shift = (extended
                    + ({{ACC_W{1'b0}}, 1'b1} <<< (ROT_FRAC-1))) >>> ROT_FRAC;
            else begin
                magnitude = -extended;
                rounded_shift = -((magnitude
                    + ({{ACC_W{1'b0}}, 1'b1} <<< (ROT_FRAC-1))) >>> ROT_FRAC);
            end
        end
    endfunction

    function automatic logic shifted_overflow(
        input logic signed [ACC_W:0] shifted
    );
        logic signed [ACC_W:0] maximum;
        logic signed [ACC_W:0] minimum;
        begin
            maximum = ({{ACC_W{1'b0}}, 1'b1} <<< (COORD_W-1)) - 1;
            minimum = -({{ACC_W{1'b0}}, 1'b1} <<< (COORD_W-1));
            shifted_overflow = shifted > maximum || shifted < minimum;
        end
    endfunction

    function automatic logic signed [COORD_W-1:0] saturate_shifted(
        input logic signed [ACC_W:0] shifted
    );
        logic signed [ACC_W:0] maximum;
        logic signed [ACC_W:0] minimum;
        begin
            maximum = ({{ACC_W{1'b0}}, 1'b1} <<< (COORD_W-1)) - 1;
            minimum = -({{ACC_W{1'b0}}, 1'b1} <<< (COORD_W-1));
            if (shifted > maximum)
                saturate_shifted = {1'b0, {(COORD_W-1){1'b1}}};
            else if (shifted < minimum)
                saturate_shifted = {1'b1, {(COORD_W-1){1'b0}}};
            else
                saturate_shifted = shifted[COORD_W-1:0];
        end
    endfunction

    assign p00 = s_world_x_q16_i * cfg_r00_q20_i;
    assign p01 = s_world_y_q16_i * cfg_r01_q20_i;
    assign p02 = s_world_z_q16_i * cfg_r02_q20_i;
    assign p10 = s_world_x_q16_i * cfg_r10_q20_i;
    assign p11 = s_world_y_q16_i * cfg_r11_q20_i;
    assign p12 = s_world_z_q16_i * cfg_r12_q20_i;
    assign p20 = s_world_x_q16_i * cfg_r20_q20_i;
    assign p21 = s_world_y_q16_i * cfg_r21_q20_i;
    assign p22 = s_world_z_q16_i * cfg_r22_q20_i;
    assign tx_scaled = $signed({{(ACC_W-COORD_W){cfg_tx_q16_i[COORD_W-1]}},
                                cfg_tx_q16_i}) <<< ROT_FRAC;
    assign ty_scaled = $signed({{(ACC_W-COORD_W){cfg_ty_q16_i[COORD_W-1]}},
                                cfg_ty_q16_i}) <<< ROT_FRAC;
    assign tz_scaled = $signed({{(ACC_W-COORD_W){cfg_tz_q16_i[COORD_W-1]}},
                                cfg_tz_q16_i}) <<< ROT_FRAC;
    assign acc_x = sum_products_translation(p00, p01, p02, tx_scaled);
    assign acc_y = sum_products_translation(p10, p11, p12, ty_scaled);
    assign acc_z = sum_products_translation(p20, p21, p22, tz_scaled);
    assign shifted_x = rounded_shift(acc_x);
    assign shifted_y = rounded_shift(acc_y);
    assign shifted_z = rounded_shift(acc_z);

    always_comb begin
        camera_x = saturate_shifted(shifted_x);
        camera_y = saturate_shifted(shifted_y);
        camera_z = saturate_shifted(shifted_z);
        overflow_x = shifted_overflow(shifted_x);
        overflow_y = shifted_overflow(shifted_y);
        overflow_z = shifted_overflow(shifted_z);
    end
    assign result_data = {s_meta_i, camera_x, camera_y, camera_z,
                          overflow_x || overflow_y || overflow_z};

    rv_reg_slice #(.DATA_W(OUT_DATA_W)) u_result (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .s_valid_i(s_valid_i), .s_ready_o(s_ready_o), .s_data_i(result_data),
        .m_valid_o(m_valid_o), .m_ready_i(m_ready_i),
        .m_data_o({m_meta_o, m_camera_x_q16_o, m_camera_y_q16_o,
                   m_camera_z_q16_o, m_overflow_o})
    );
endmodule
