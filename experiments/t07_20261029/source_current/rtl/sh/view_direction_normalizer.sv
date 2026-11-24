// Normalize a world-space view vector for degree-3 SH evaluation.
// Delta inputs are signed Q10.16; outputs are signed Q1.20. A zero-length
// vector deterministically falls back to (0,0,1), matching the FP32 model.
module view_direction_normalizer #(
    parameter int unsigned META_W=32,
    parameter int unsigned COORD_W=27,
    parameter int unsigned DIR_W=22,
    parameter int unsigned DIR_FRAC=20,
    parameter int unsigned RAD_W=2*COORD_W+2,
    parameter int unsigned ROOT_W=(RAD_W+1)/2,
    parameter int unsigned NUM_W=COORD_W+DIR_FRAC+1,
    parameter int unsigned SQRT_META_W=META_W+3*COORD_W+1,
    parameter int unsigned DIV_META_W=META_W+1
) (
    input logic clk_i,input logic rst_ni,
    input logic s_valid_i,output logic s_ready_o,input logic[META_W-1:0]s_meta_i,
    input logic signed[COORD_W-1:0]s_dx_q16_i,s_dy_q16_i,s_dz_q16_i,
    output logic m_valid_o,input logic m_ready_i,output logic[META_W-1:0]m_meta_o,
    output logic signed[DIR_W-1:0]m_x_q20_o,m_y_q20_o,m_z_q20_o,
    output logic m_zero_fallback_o,output logic m_numeric_overflow_o
);
    logic[2*COORD_W-1:0]x_square,y_square,z_square;
    logic[RAD_W-1:0]radicand,effective_radicand;
    logic zero_direction;logic signed[COORD_W-1:0]effective_x,effective_y,effective_z;
    logic sqrt_valid,sqrt_ready;logic[ROOT_W-1:0]norm_q16;
    logic[SQRT_META_W-1:0]sqrt_meta_in,sqrt_meta_out;
    logic[META_W-1:0]sqrt_meta;logic signed[COORD_W-1:0]sqrt_x,sqrt_y,sqrt_z;logic sqrt_zero;
    logic signed[NUM_W-1:0]num_x,num_y,num_z;
    logic signed[NUM_W-1:0]wide_x,wide_y,wide_z;
    logic div0_s_ready,div1_s_ready,div0_valid,div1_valid,div0_ready,div1_ready;
    logic signed[DIR_W-1:0]dir_x,dir_y,dir_z,unused_dir;
    logic[DIV_META_W-1:0]div0_meta,div1_meta;logic div0_zero,div1_zero,div0_overflow,div1_overflow;
    assign x_square=$signed(s_dx_q16_i)*$signed(s_dx_q16_i);
    assign y_square=$signed(s_dy_q16_i)*$signed(s_dy_q16_i);
    assign z_square=$signed(s_dz_q16_i)*$signed(s_dz_q16_i);
    assign radicand={{2{1'b0}},x_square}+{{2{1'b0}},y_square}+{{2{1'b0}},z_square};
    assign zero_direction=radicand==0;
    assign effective_x=zero_direction?'0:s_dx_q16_i;
    assign effective_y=zero_direction?'0:s_dy_q16_i;
    assign effective_z=zero_direction?$signed(1<<<16):s_dz_q16_i;
    // 1.0 in Q16 squared is bit 32 of the Q32 radicand.
    assign effective_radicand=zero_direction?({{(RAD_W-33){1'b0}},1'b1,32'd0}):radicand;
    assign sqrt_meta_in={s_meta_i,effective_x,effective_y,effective_z,zero_direction};
    fixed_sqrt_pipe #(.RAD_W(RAD_W),.META_W(SQRT_META_W))u_norm_sqrt(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i),.s_ready_o(s_ready_o),
      .s_radicand_i(effective_radicand),.s_meta_i(sqrt_meta_in),.m_valid_o(sqrt_valid),
      .m_ready_i(sqrt_ready),.m_root_o(norm_q16),.m_meta_o(sqrt_meta_out),.m_exact_o());
    assign {sqrt_meta,sqrt_x,sqrt_y,sqrt_z,sqrt_zero}=sqrt_meta_out;
    // Extend before shifting. Shifting a COORD_W operand directly would keep
    // COORD_W result width and silently discard the Q20 fractional bits.
    assign wide_x={{(NUM_W-COORD_W){sqrt_x[COORD_W-1]}},sqrt_x};
    assign wide_y={{(NUM_W-COORD_W){sqrt_y[COORD_W-1]}},sqrt_y};
    assign wide_z={{(NUM_W-COORD_W){sqrt_z[COORD_W-1]}},sqrt_z};
    assign num_x=wide_x<<<DIR_FRAC;assign num_y=wide_y<<<DIR_FRAC;
    assign num_z=wide_z<<<DIR_FRAC;
    fixed_div_pipe2 #(.NUM_W(NUM_W),.DEN_W(ROOT_W),.QUOT_W(DIR_W),.META_W(DIV_META_W))u_div_xy(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(sqrt_valid&&div1_s_ready),.s_ready_o(div0_s_ready),
      .s_num0_i(num_x),.s_num1_i(num_y),.s_den_i(norm_q16),.s_meta_i({sqrt_meta,sqrt_zero}),
      .m_valid_o(div0_valid),.m_ready_i(div0_ready),.m_quot0_o(dir_x),.m_quot1_o(dir_y),
      .m_meta_o(div0_meta),.m_div_zero_o(div0_zero),.m_overflow_o(div0_overflow));
    fixed_div_pipe2 #(.NUM_W(NUM_W),.DEN_W(ROOT_W),.QUOT_W(DIR_W),.META_W(DIV_META_W))u_div_z(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(sqrt_valid&&div0_s_ready),.s_ready_o(div1_s_ready),
      .s_num0_i(num_z),.s_num1_i({NUM_W{1'b0}}),.s_den_i(norm_q16),.s_meta_i({sqrt_meta,sqrt_zero}),
      .m_valid_o(div1_valid),.m_ready_i(div1_ready),.m_quot0_o(dir_z),.m_quot1_o(unused_dir),
      .m_meta_o(div1_meta),.m_div_zero_o(div1_zero),.m_overflow_o(div1_overflow));
    assign sqrt_ready=div0_s_ready&&div1_s_ready;
    assign div0_ready=m_ready_i&&div1_valid;assign div1_ready=m_ready_i&&div0_valid;
    assign m_valid_o=div0_valid&&div1_valid;assign m_meta_o=div0_meta[DIV_META_W-1:1];
    assign m_zero_fallback_o=div0_meta[0];assign m_x_q20_o=dir_x;assign m_y_q20_o=dir_y;assign m_z_q20_o=dir_z;
    assign m_numeric_overflow_o=div0_zero||div1_zero||div0_overflow||div1_overflow||div0_meta!=div1_meta;
endmodule
