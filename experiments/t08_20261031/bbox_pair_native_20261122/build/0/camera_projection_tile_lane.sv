// Replicable projection lane for the dynamically reconfigurable 3DGS front end.
// Camera-space mean and covariance fork atomically into mean/covariance paths,
// rejoin by construction, form a conservative bounding box, and enumerate all
// covered 8x8 blocks within the current Gaussian. No persistent tile bin or
// per-tile sorting is created. More lanes may be enabled at an epoch boundary without
// changing the arithmetic or descriptor format.
module camera_projection_tile_lane #(
    parameter int unsigned META_W = 64,
    parameter int unsigned COORD_W = 27,
    parameter int unsigned SCREEN_W = 27,
    parameter int unsigned COV3_W = 41,
    parameter int unsigned COV2_W = 35,
    parameter int unsigned PIXEL_W = 16,
    parameter int unsigned TILE_W = 12,
    parameter int unsigned RAW_DESC_W = META_W + 13 + COORD_W + 3*COV2_W
                                          + 2*SCREEN_W + 4*PIXEL_W + 1,
    parameter int unsigned DESC_W = RAW_DESC_W + 15 + 16 + 15 + 6 + 6 + 1
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
    input  logic [12:0]                  s_opacity_q12_i,
    input  logic                         s_transform_overflow_i,
    input  logic signed [32:0]           cfg_fx_q16_i,
    input  logic signed [32:0]           cfg_fy_q16_i,
    input  logic signed [32:0]           cfg_cx_q16_i,
    input  logic signed [32:0]           cfg_cy_q16_i,
    input  logic signed [COORD_W-1:0]    cfg_near_q16_i,
    input  logic signed [COORD_W-1:0]    cfg_far_q16_i,
    input  logic [COV2_W-1:0]            cfg_regularizer_q8_i,
    input  logic [PIXEL_W-1:0]           cfg_image_width_i,
    input  logic [PIXEL_W-1:0]           cfg_image_height_i,
    output logic                         m_task_valid_o,
    input  logic                         m_task_ready_i,
    output logic [DESC_W-1:0]            m_task_desc_o,
    output logic [TILE_W-1:0]            m_task_tile_x_o,
    output logic [TILE_W-1:0]            m_task_tile_y_o,
    output logic                         m_task_first_o,
    output logic                         m_task_last_o,
    output logic                         m_task_culled_o,
    output logic                         culled_pulse_o
);
    localparam int unsigned PIPE_META_W = META_W + 13;
    localparam int unsigned BBOX_META_W = PIPE_META_W + COORD_W + 3*COV2_W;
    logic projection_s_ready, covariance_s_ready;
    logic projection_valid, projection_ready;
    logic [PIPE_META_W-1:0] projection_meta;
    logic signed [SCREEN_W-1:0] mean_x_q8,mean_y_q8;
    logic signed [COORD_W-1:0] depth_q16;
    logic projection_visible, projection_overflow;
    logic covariance_valid, covariance_ready;
    logic [PIPE_META_W-1:0] covariance_meta;
    logic [12:0] projected_opacity;
    logic [COV2_W-1:0] cov00_q8,cov11_q8;
    logic signed [COV2_W-1:0] cov01_q8;
    logic covariance_overflow;
    logic join_valid, bbox_ready;
    logic bbox_valid, encoder_ready,encoder_valid,task_desc_ready;
    logic [BBOX_META_W-1:0] bbox_meta;
    logic signed [SCREEN_W-1:0] bbox_mean_x,bbox_mean_y;
    logic [PIXEL_W-1:0] bbox_x0,bbox_y0,bbox_x1,bbox_y1;
    logic [TILE_W-1:0] tile_x0,tile_y0,tile_x1,tile_y1;
    logic bbox_keep,bbox_numeric_invalid;
    logic [RAW_DESC_W-1:0] raw_task_desc,encoded_raw_desc;
    logic encoded_keep;
    logic [14:0] encoded_l00,encoded_l11;
    logic signed [15:0] encoded_l10;
    logic signed [5:0] encoded_coordinate_shift,encoded_factor_shift;
    logic [12:0] encoded_opacity;
    logic encoded_numeric_overflow;
    logic [DESC_W-1:0] task_desc;
    logic [PIXEL_W-1:0] encoded_x0,encoded_y0,encoded_x1,encoded_y1;
    logic [TILE_W-1:0] encoded_tile_x0,encoded_tile_y0,encoded_tile_x1,encoded_tile_y1;
    logic [PIPE_META_W-1:0] bbox_projection_meta;
    logic signed [COORD_W-1:0] bbox_depth;
    logic [COV2_W-1:0] bbox_cov00,bbox_cov11;
    logic signed [COV2_W-1:0] bbox_cov01;

    assign s_ready_o = projection_s_ready && covariance_s_ready;
    assign join_valid = projection_valid && covariance_valid;
    assign projection_ready = covariance_valid && bbox_ready;
    assign covariance_ready = projection_valid && bbox_ready;

    perspective_project_core #(.META_W(PIPE_META_W)) u_mean_projection(
        .clk_i(clk_i),.rst_ni(rst_ni),
        .s_valid_i(s_valid_i && covariance_s_ready),.s_ready_o(projection_s_ready),
        .s_meta_i({s_meta_i,s_opacity_q12_i}),.s_camera_x_q16_i(s_camera_x_q16_i),
        .s_camera_y_q16_i(s_camera_y_q16_i),.s_camera_z_q16_i(s_camera_z_q16_i),
        .s_transform_overflow_i(s_transform_overflow_i),.cfg_fx_q16_i(cfg_fx_q16_i),
        .cfg_fy_q16_i(cfg_fy_q16_i),.cfg_cx_q16_i(cfg_cx_q16_i),.cfg_cy_q16_i(cfg_cy_q16_i),
        .cfg_near_q16_i(cfg_near_q16_i),.cfg_far_q16_i(cfg_far_q16_i),
        .m_valid_o(projection_valid),.m_ready_i(projection_ready),.m_meta_o(projection_meta),
        .m_screen_x_q8_o(mean_x_q8),.m_screen_y_q8_o(mean_y_q8),.m_depth_q16_o(depth_q16),
        .m_visible_o(projection_visible),.m_numeric_overflow_o(projection_overflow));

    screen_covariance_core #(.META_W(PIPE_META_W)) u_covariance_projection(
        .clk_i(clk_i),.rst_ni(rst_ni),
        .s_valid_i(s_valid_i && projection_s_ready),.s_ready_o(covariance_s_ready),
        .s_meta_i({s_meta_i,s_opacity_q12_i}),.s_camera_x_q16_i(s_camera_x_q16_i),
        .s_camera_y_q16_i(s_camera_y_q16_i),.s_camera_z_q16_i(s_camera_z_q16_i),
        .s_cov_xx_q16_i(s_cov_xx_q16_i),.s_cov_xy_q16_i(s_cov_xy_q16_i),
        .s_cov_xz_q16_i(s_cov_xz_q16_i),.s_cov_yy_q16_i(s_cov_yy_q16_i),
        .s_cov_yz_q16_i(s_cov_yz_q16_i),.s_cov_zz_q16_i(s_cov_zz_q16_i),
        .cfg_fx_q16_i(cfg_fx_q16_i),.cfg_fy_q16_i(cfg_fy_q16_i),
        .cfg_regularizer_q8_i(cfg_regularizer_q8_i),
        .cfg_image_width_i(cfg_image_width_i),.cfg_image_height_i(cfg_image_height_i),
        .m_valid_o(covariance_valid),.m_ready_i(covariance_ready),.m_meta_o(covariance_meta),
        .m_cov00_q8_o(cov00_q8),.m_cov01_q8_o(cov01_q8),.m_cov11_q8_o(cov11_q8),
        .m_numeric_overflow_o(covariance_overflow));

    assign projected_opacity=projection_meta[12:0];
    bbox_tile_bounds_core #(.META_W(BBOX_META_W),.COV_W(COV2_W)) u_bbox(
        .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(join_valid),.s_ready_o(bbox_ready),
        .s_meta_i({projection_meta,depth_q16,cov00_q8,cov01_q8,cov11_q8}),
        .s_mean_x_q8_i(mean_x_q8),.s_mean_y_q8_i(mean_y_q8),
        .s_cov00_q8_i(cov00_q8),.s_cov01_q8_i(cov01_q8),.s_cov11_q8_i(cov11_q8),
        .s_opacity_q12_i(projected_opacity),
        .s_visible_i(projection_visible && projection_meta==covariance_meta),
        .s_numeric_overflow_i(projection_overflow || covariance_overflow),
        .cfg_image_width_i(cfg_image_width_i),.cfg_image_height_i(cfg_image_height_i),
        .m_valid_o(bbox_valid),.m_ready_i(encoder_ready),.m_meta_o(bbox_meta),
        .m_mean_x_q8_o(bbox_mean_x),.m_mean_y_q8_o(bbox_mean_y),
        .m_x0_o(bbox_x0),.m_y0_o(bbox_y0),.m_x1_o(bbox_x1),.m_y1_o(bbox_y1),
        .m_tile_x0_o(tile_x0),.m_tile_y0_o(tile_y0),.m_tile_x1_o(tile_x1),.m_tile_y1_o(tile_y1),
        .m_keep_o(bbox_keep),.m_numeric_invalid_o(bbox_numeric_invalid));
    assign {bbox_projection_meta,bbox_depth,bbox_cov00,bbox_cov01,bbox_cov11}=bbox_meta;
    assign raw_task_desc={bbox_meta,bbox_mean_x,bbox_mean_y,
        bbox_x0,bbox_y0,bbox_x1,bbox_y1,bbox_keep};

    covariance2d_cholesky_encoder #(.META_W(RAW_DESC_W),.COV_W(COV2_W))u_alpha_encoder(
        .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(bbox_valid),.s_ready_o(encoder_ready),
        .s_meta_i(raw_task_desc),.s_cov00_q8_i(bbox_cov00),.s_cov01_q8_i(bbox_cov01),
        .s_cov11_q8_i(bbox_cov11),.s_mean_x_q8_i(bbox_mean_x),.s_mean_y_q8_i(bbox_mean_y),
        .s_x0_i(bbox_x0),.s_y0_i(bbox_y0),.s_x1_i(bbox_x1),.s_y1_i(bbox_y1),
        .s_opacity_q12_i(bbox_projection_meta[12:0]),
        .s_numeric_overflow_i(bbox_numeric_invalid),
        .m_valid_o(encoder_valid),.m_ready_i(task_desc_ready),.m_meta_o(encoded_raw_desc),
        .m_l00_q12_o(encoded_l00),.m_l10_q12_o(encoded_l10),.m_l11_q12_o(encoded_l11),
        .m_coordinate_shift_o(encoded_coordinate_shift),.m_factor_shift_o(encoded_factor_shift),
        .m_opacity_q12_o(encoded_opacity),.m_numeric_overflow_o(encoded_numeric_overflow));
    // bbox_keep is already represented by a non-empty bbox. Culls have x0=x1
    // or y0=y1, so the predicate is reconstructed after the long encoder.
    assign encoded_x0=encoded_raw_desc[4*PIXEL_W:3*PIXEL_W+1];
    assign encoded_y0=encoded_raw_desc[3*PIXEL_W:2*PIXEL_W+1];
    assign encoded_x1=encoded_raw_desc[2*PIXEL_W:PIXEL_W+1];
    assign encoded_y1=encoded_raw_desc[PIXEL_W:1];
    // Encoder-local failures also fail closed.  Upstream invalid inputs have
    // already produced an empty bbox; this final guard covers determinant,
    // divider, residual and factor-encoding failures.

    logic bbox_proven_empty;
    wire signed [SCREEN_W-1:0] encoded_my=encoded_raw_desc[4*PIXEL_W+1+:SCREEN_W];
    wire signed [SCREEN_W-1:0] encoded_mx=encoded_raw_desc[4*PIXEL_W+1+SCREEN_W+:SCREEN_W];
    gaussian_bbox_axis0_reject #(.SCREEN_W(SCREEN_W),.PIXEL_W(PIXEL_W)) u_bbox_axis0(
      .x0_i(encoded_x0),.y0_i(encoded_y0),.x1_i(encoded_x1),.y1_i(encoded_y1),
      .mean_x_i(encoded_mx),.mean_y_i(encoded_my),.coord_i(encoded_coordinate_shift),
      .factor_i(encoded_factor_shift),.l00_i(encoded_l00),.l10_i(encoded_l10),.opacity_i(encoded_opacity),
      .reject_o(bbox_proven_empty));
    wire bbox_skip=1'b0&&encoded_raw_desc[0]&&!encoded_numeric_overflow&&bbox_proven_empty;
    assign encoded_keep=encoded_raw_desc[0]&&!encoded_numeric_overflow&&!bbox_skip;

    assign encoded_tile_x0=encoded_x0>>3;
    assign encoded_tile_y0=encoded_y0>>3;
    assign encoded_tile_x1=encoded_keep?((encoded_x1-1'b1)>>3):'0;
    assign encoded_tile_y1=encoded_keep?((encoded_y1-1'b1)>>3):'0;
    assign task_desc={encoded_raw_desc,encoded_l00,encoded_l10,encoded_l11,
        encoded_coordinate_shift,encoded_factor_shift,encoded_numeric_overflow};

    gaussian_tile_task_gen #(.DESC_W(DESC_W),.TILE_W(TILE_W)) u_task_gen(
        .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(encoder_valid),.s_ready_o(task_desc_ready),
        .s_desc_i(task_desc),.s_tile_x0_i(encoded_tile_x0),.s_tile_y0_i(encoded_tile_y0),
        .s_tile_x1_i(encoded_tile_x1),.s_tile_y1_i(encoded_tile_y1),
        .s_keep_i(encoded_keep),
        .m_valid_o(m_task_valid_o),.m_ready_i(m_task_ready_i),.m_desc_o(m_task_desc_o),
        .m_tile_x_o(m_task_tile_x_o),.m_tile_y_o(m_task_tile_y_o),
        .m_first_o(m_task_first_o),.m_last_o(m_task_last_o),.m_culled_o(m_task_culled_o),
        .culled_pulse_o(culled_pulse_o));
endmodule
