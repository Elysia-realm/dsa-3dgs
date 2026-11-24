// Complete per-Gaussian SH color path: world mean and camera position are
// normalized, then degree-3 RGB is evaluated once before block traversal.
module gaussian_sh_color_core #(
    parameter int unsigned META_W=32,parameter int unsigned COORD_W=27,
    parameter int unsigned COEFF_W=18,parameter int unsigned COEFFS=16,
    parameter int unsigned COEFF_FLAT_W=3*COEFFS*COEFF_W
) (
    input logic clk_i,input logic rst_ni,input logic s_valid_i,output logic s_ready_o,
    input logic[META_W-1:0]s_meta_i,
    input logic signed[COORD_W-1:0]s_world_x_q16_i,s_world_y_q16_i,s_world_z_q16_i,
    input logic signed[COORD_W-1:0]cfg_camera_x_q16_i,cfg_camera_y_q16_i,cfg_camera_z_q16_i,
    input logic[COEFF_FLAT_W-1:0]s_coeff_q12_flat_i,
    output logic m_valid_o,input logic m_ready_i,output logic[META_W-1:0]m_meta_o,
    output logic[12:0]m_r_q12_o,m_g_q12_o,m_b_q12_o,
    output logic m_direction_fallback_o,output logic m_numeric_overflow_o
);
    localparam int unsigned DELTA_W=COORD_W+1;
    localparam int unsigned NORM_META_W=META_W+COEFF_FLAT_W;
    localparam int unsigned EVAL_META_W=META_W+1;
    logic norm_valid,norm_ready;logic[NORM_META_W-1:0]norm_meta;logic signed[21:0]dir_x,dir_y,dir_z;
    logic norm_fallback,norm_overflow;logic[META_W-1:0]eval_meta;logic[COEFF_FLAT_W-1:0]eval_coeff;
    logic eval_overflow;logic[EVAL_META_W-1:0]color_meta;
    logic signed[DELTA_W-1:0]world_x_ext,world_y_ext,world_z_ext;
    logic signed[DELTA_W-1:0]camera_x_ext,camera_y_ext,camera_z_ext;
    logic signed[DELTA_W-1:0]delta_x,delta_y,delta_z;
    assign world_x_ext={s_world_x_q16_i[COORD_W-1],s_world_x_q16_i};
    assign world_y_ext={s_world_y_q16_i[COORD_W-1],s_world_y_q16_i};
    assign world_z_ext={s_world_z_q16_i[COORD_W-1],s_world_z_q16_i};
    assign camera_x_ext={cfg_camera_x_q16_i[COORD_W-1],cfg_camera_x_q16_i};
    assign camera_y_ext={cfg_camera_y_q16_i[COORD_W-1],cfg_camera_y_q16_i};
    assign camera_z_ext={cfg_camera_z_q16_i[COORD_W-1],cfg_camera_z_q16_i};
    assign delta_x=world_x_ext-camera_x_ext;
    assign delta_y=world_y_ext-camera_y_ext;
    assign delta_z=world_z_ext-camera_z_ext;
    view_direction_normalizer #(.META_W(NORM_META_W),.COORD_W(DELTA_W))u_normalize(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i),.s_ready_o(s_ready_o),
      .s_meta_i({s_meta_i,s_coeff_q12_flat_i}),
      .s_dx_q16_i(delta_x),.s_dy_q16_i(delta_y),.s_dz_q16_i(delta_z),
      .m_valid_o(norm_valid),.m_ready_i(norm_ready),.m_meta_o(norm_meta),
      .m_x_q20_o(dir_x),.m_y_q20_o(dir_y),.m_z_q20_o(dir_z),
      .m_zero_fallback_o(norm_fallback),.m_numeric_overflow_o(norm_overflow));
    assign {eval_meta,eval_coeff}=norm_meta;
    sh_degree3_color_core #(.META_W(EVAL_META_W),.COEFF_W(COEFF_W))u_evaluate(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(norm_valid),.s_ready_o(norm_ready),
      .s_meta_i({eval_meta,norm_fallback}),.s_x_q20_i(dir_x),.s_y_q20_i(dir_y),.s_z_q20_i(dir_z),
      .s_coeff_q12_flat_i(eval_coeff),.s_numeric_overflow_i(norm_overflow),
      .m_valid_o(m_valid_o),.m_ready_i(m_ready_i),.m_meta_o(color_meta),
      .m_r_q12_o(m_r_q12_o),.m_g_q12_o(m_g_q12_o),.m_b_q12_o(m_b_q12_o),
      .m_numeric_overflow_o(eval_overflow));
    assign {m_meta_o,m_direction_fallback_o}=color_meta;
    assign m_numeric_overflow_o=eval_overflow;
endmodule
