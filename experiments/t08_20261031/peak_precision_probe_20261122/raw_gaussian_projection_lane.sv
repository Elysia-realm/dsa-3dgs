// Complete replicable 3DGS front-end lane. One raw Gaussian atomically forks
// into mean and covariance paths, rejoins in camera space, and emits all tile
// tasks with the block-float Cholesky alpha descriptor. Camera configuration
// must remain stable until the lane is drained at an epoch boundary.
module raw_gaussian_projection_lane #(
    parameter bit ENABLE_COMPRESSED_ATTRIBUTES=1'b0,
    parameter int unsigned META_W   = 64,
    parameter int unsigned COORD_W  = 27,
    parameter int unsigned QUAT_W   = 22,
    parameter int unsigned SCALE_W  = 24,
    parameter int unsigned ROT_W    = 22,
    parameter bit MEAN_IS_CAMERA = 1'b0,
    parameter int unsigned COV3_W   = 41,
    parameter int unsigned COV2_W   = 35,
    parameter int unsigned SCREEN_W = 27,
    parameter int unsigned PIXEL_W  = 16,
    parameter int unsigned TILE_W   = 12,
    parameter int unsigned RAW_DESC_W = META_W + 13 + COORD_W + 3*COV2_W
        + 2*SCREEN_W + 4*PIXEL_W + 1,
    parameter int unsigned DESC_W = RAW_DESC_W + 15 + 16 + 15 + 6 + 6 + 1
) (

    input logic [248:0] s_attr_aux_i,
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic                         s_valid_i,
    output logic                         s_ready_o,
    input  logic [META_W-1:0]            s_meta_i,
    input  logic signed [COORD_W-1:0]    s_world_x_q16_i,
    input  logic signed [COORD_W-1:0]    s_world_y_q16_i,
    input  logic signed [COORD_W-1:0]    s_world_z_q16_i,
    input  logic                         s_mean_overflow_i,
    input  logic signed [QUAT_W-1:0]     s_qw_q20_i,
    input  logic signed [QUAT_W-1:0]     s_qx_q20_i,
    input  logic signed [QUAT_W-1:0]     s_qy_q20_i,
    input  logic signed [QUAT_W-1:0]     s_qz_q20_i,
    input  logic        [SCALE_W-1:0]    s_scale_x_q20_i,
    input  logic        [SCALE_W-1:0]    s_scale_y_q20_i,
    input  logic        [SCALE_W-1:0]    s_scale_z_q20_i,
    input  logic        [12:0]           s_opacity_q12_i,

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
    input  logic signed [32:0]           cfg_fx_q16_i,
    input  logic signed [32:0]           cfg_fy_q16_i,
    input  logic signed [32:0]           cfg_cx_q16_i,
    input  logic signed [32:0]           cfg_cy_q16_i,
    input  logic signed [COORD_W-1:0]    cfg_near_q16_i,
    input  logic signed [COORD_W-1:0]    cfg_far_q16_i,
    input  logic        [COV2_W-1:0]     cfg_regularizer_q8_i,
    input  logic        [PIXEL_W-1:0]    cfg_image_width_i,
    input  logic        [PIXEL_W-1:0]    cfg_image_height_i,

    output logic                         m_task_valid_o,
    input  logic                         m_task_ready_i,
    output logic [DESC_W-1:0]            m_task_desc_o,
    output logic [TILE_W-1:0]            m_task_tile_x_o,
    output logic [TILE_W-1:0]            m_task_tile_y_o,
    output logic                         m_task_first_o,
    output logic                         m_task_last_o,
    output logic                         m_task_culled_o,
    output logic                         culled_pulse_o,
    output logic                         idle_o
);
    localparam int unsigned PIPE_META_W = META_W + 13;
    localparam int WORLD_META_W=PIPE_META_W+(ENABLE_COMPRESSED_ATTRIBUTES?249:0);
    logic[WORLD_META_W-1:0]world_input_meta,world_result_meta;
    logic[248:0]world_aux;
    logic signed[COV3_W-1:0]computed_xx,computed_xy,computed_xz,computed_yy,computed_yz,computed_zz;
    logic computed_overflow;
    assign world_input_meta=ENABLE_COMPRESSED_ATTRIBUTES?WORLD_META_W'({s_meta_i,s_opacity_q12_i,s_attr_aux_i}):WORLD_META_W'({s_meta_i,s_opacity_q12_i});
    assign world_aux=ENABLE_COMPRESSED_ATTRIBUTES?249'(world_result_meta):249'd0;
    assign world_cov_meta=world_result_meta>>(ENABLE_COMPRESSED_ATTRIBUTES?249:0);
    assign world_cov_overflow=world_aux[246]?1'b0:computed_overflow;

    logic mean_s_ready,cov_s_ready;
    logic mean_valid,mean_ready;
    logic [PIPE_META_W-1:0] mean_meta;
    logic signed [COORD_W-1:0] camera_x,camera_y,camera_z;
    logic mean_overflow;

    logic world_cov_valid,world_cov_ready;
    logic [PIPE_META_W-1:0] world_cov_meta;
    logic signed [COV3_W-1:0] world_xx,world_xy,world_xz;
    logic signed [COV3_W-1:0] world_yy,world_yz,world_zz;
    logic world_cov_overflow;
    logic camera_cov_valid,camera_cov_ready;
    logic [PIPE_META_W-1:0] camera_cov_meta;
    logic signed [COV3_W-1:0] camera_xx,camera_xy,camera_xz;
    logic signed [COV3_W-1:0] camera_yy,camera_yz,camera_zz;
    logic camera_cov_overflow;
    logic camera_lane_ready,join_valid,meta_match;
    logic [15:0] inflight_count_q;
    logic input_accept,output_retire;

    assign s_ready_o=mean_s_ready&&cov_s_ready;
    assign join_valid=mean_valid&&camera_cov_valid;
    assign meta_match=mean_meta==camera_cov_meta;
    assign mean_ready=camera_cov_valid&&camera_lane_ready;
    assign camera_cov_ready=mean_valid&&camera_lane_ready;

    generate if(MEAN_IS_CAMERA)begin:g_camera_mean
      rv_reg_slice #(.DATA_W(PIPE_META_W+3*COORD_W+1))u_mean(
        .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i&&cov_s_ready),.s_ready_o(mean_s_ready),
        .s_data_i({s_meta_i,s_opacity_q12_i,s_world_x_q16_i,s_world_y_q16_i,s_world_z_q16_i,s_mean_overflow_i}),
        .m_valid_o(mean_valid),.m_ready_i(mean_ready),
        .m_data_o({mean_meta,camera_x,camera_y,camera_z,mean_overflow}));
    end else begin:g_world_mean
    world_to_camera_core #(.META_W(PIPE_META_W),.COORD_W(COORD_W),.ROT_W(ROT_W))u_mean(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i&&cov_s_ready),.s_ready_o(mean_s_ready),
      .s_meta_i({s_meta_i,s_opacity_q12_i}),.s_world_x_q16_i(s_world_x_q16_i),
      .s_world_y_q16_i(s_world_y_q16_i),.s_world_z_q16_i(s_world_z_q16_i),
      .cfg_r00_q20_i(cfg_r00_q20_i),.cfg_r01_q20_i(cfg_r01_q20_i),.cfg_r02_q20_i(cfg_r02_q20_i),
      .cfg_r10_q20_i(cfg_r10_q20_i),.cfg_r11_q20_i(cfg_r11_q20_i),.cfg_r12_q20_i(cfg_r12_q20_i),
      .cfg_r20_q20_i(cfg_r20_q20_i),.cfg_r21_q20_i(cfg_r21_q20_i),.cfg_r22_q20_i(cfg_r22_q20_i),
      .cfg_tx_q16_i(cfg_tx_q16_i),.cfg_ty_q16_i(cfg_ty_q16_i),.cfg_tz_q16_i(cfg_tz_q16_i),
      .m_valid_o(mean_valid),.m_ready_i(mean_ready),.m_meta_o(mean_meta),
      .m_camera_x_q16_o(camera_x),.m_camera_y_q16_o(camera_y),.m_camera_z_q16_o(camera_z),
      .m_overflow_o(mean_overflow));
    end endgenerate

    quaternion_scale_covariance_core #(.COV_FRAC_W(24),.META_W(WORLD_META_W),.QUAT_W(QUAT_W),
      .SCALE_W(SCALE_W),.COV_W(COV3_W))u_world_covariance(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i&&mean_s_ready),.s_ready_o(cov_s_ready),
      .s_meta_i(world_input_meta),.s_qw_q20_i(s_qw_q20_i),.s_qx_q20_i(s_qx_q20_i),
      .s_qy_q20_i(s_qy_q20_i),.s_qz_q20_i(s_qz_q20_i),
      .s_scale_x_q20_i(s_scale_x_q20_i),.s_scale_y_q20_i(s_scale_y_q20_i),
      .s_scale_z_q20_i(s_scale_z_q20_i),.m_valid_o(world_cov_valid),
      .m_ready_i(world_cov_ready),.m_meta_o(world_result_meta),
      .m_cov_xx_q16_o(computed_xx),.m_cov_xy_q16_o(computed_xy),.m_cov_xz_q16_o(computed_xz),
      .m_cov_yy_q16_o(computed_yy),.m_cov_yz_q16_o(computed_yz),.m_cov_zz_q16_o(computed_zz),
      .m_numeric_overflow_o(computed_overflow));

    // Same elastic stages/tag ordering for raw and precomputed records.
    assign world_xx=world_aux[246]?$signed(world_aux[245-:41]):computed_xx;
    assign world_xy=world_aux[246]?$signed(world_aux[204-:41]):computed_xy;
    assign world_xz=world_aux[246]?$signed(world_aux[163-:41]):computed_xz;
    assign world_yy=world_aux[246]?$signed(world_aux[122-:41]):computed_yy;
    assign world_yz=world_aux[246]?$signed(world_aux[81-:41]):computed_yz;
    assign world_zz=world_aux[246]?$signed(world_aux[40-:41]):computed_zz;
    covariance_view_rotate_core #(.META_W(PIPE_META_W),.COV_W(COV3_W),.ROT_W(ROT_W))u_view_covariance(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(world_cov_valid),.s_ready_o(world_cov_ready),
      .s_meta_i(world_cov_meta),.s_cov_xx_q16_i(world_xx),.s_cov_xy_q16_i(world_xy),
      .s_cov_xz_q16_i(world_xz),.s_cov_yy_q16_i(world_yy),.s_cov_yz_q16_i(world_yz),
      .s_cov_zz_q16_i(world_zz),.s_numeric_overflow_i(world_cov_overflow),
      .cfg_r00_q20_i(cfg_r00_q20_i),.cfg_r01_q20_i(cfg_r01_q20_i),.cfg_r02_q20_i(cfg_r02_q20_i),
      .cfg_r10_q20_i(cfg_r10_q20_i),.cfg_r11_q20_i(cfg_r11_q20_i),.cfg_r12_q20_i(cfg_r12_q20_i),
      .cfg_r20_q20_i(cfg_r20_q20_i),.cfg_r21_q20_i(cfg_r21_q20_i),.cfg_r22_q20_i(cfg_r22_q20_i),
      .m_valid_o(camera_cov_valid),.m_ready_i(camera_cov_ready),.m_meta_o(camera_cov_meta),
      .m_cov_xx_q16_o(camera_xx),.m_cov_xy_q16_o(camera_xy),.m_cov_xz_q16_o(camera_xz),
      .m_cov_yy_q16_o(camera_yy),.m_cov_yz_q16_o(camera_yz),.m_cov_zz_q16_o(camera_zz),
      .m_numeric_overflow_o(camera_cov_overflow));

    camera_projection_tile_lane #(.META_W(META_W),.COORD_W(COORD_W),.SCREEN_W(SCREEN_W),
      .COV3_W(COV3_W),.COV2_W(COV2_W),.PIXEL_W(PIXEL_W),.TILE_W(TILE_W),
      .RAW_DESC_W(RAW_DESC_W),.DESC_W(DESC_W))u_camera_lane(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(join_valid),.s_ready_o(camera_lane_ready),
      .s_meta_i(mean_meta[PIPE_META_W-1:13]),.s_camera_x_q16_i(camera_x),
      .s_camera_y_q16_i(camera_y),.s_camera_z_q16_i(camera_z),
      .s_cov_xx_q16_i(camera_xx),.s_cov_xy_q16_i(camera_xy),.s_cov_xz_q16_i(camera_xz),
      .s_cov_yy_q16_i(camera_yy),.s_cov_yz_q16_i(camera_yz),.s_cov_zz_q16_i(camera_zz),
      .s_opacity_q12_i(mean_meta[12:0]),
      .s_transform_overflow_i(mean_overflow||camera_cov_overflow||!meta_match),
      .cfg_fx_q16_i(cfg_fx_q16_i),.cfg_fy_q16_i(cfg_fy_q16_i),
      .cfg_cx_q16_i(cfg_cx_q16_i),.cfg_cy_q16_i(cfg_cy_q16_i),
      .cfg_near_q16_i(cfg_near_q16_i),.cfg_far_q16_i(cfg_far_q16_i),
      .cfg_regularizer_q8_i(cfg_regularizer_q8_i),
      .cfg_image_width_i(cfg_image_width_i),.cfg_image_height_i(cfg_image_height_i),
      .m_task_valid_o(m_task_valid_o),.m_task_ready_i(m_task_ready_i),
      .m_task_desc_o(m_task_desc_o),.m_task_tile_x_o(m_task_tile_x_o),
      .m_task_tile_y_o(m_task_tile_y_o),.m_task_first_o(m_task_first_o),
      .m_task_last_o(m_task_last_o),.m_task_culled_o(m_task_culled_o),
      .culled_pulse_o(culled_pulse_o));

    assign input_accept=s_valid_i&&s_ready_o;
    // A culled Gaussian is already represented by one backpressured task beat
    // with first=last=culled=1.  Count only that architectural handshake here;
    // culled_pulse_o is a delayed notification of the same event and including
    // it would retire the Gaussian twice, underflowing inflight_count_q.
    assign output_retire=m_task_valid_o&&m_task_ready_i&&m_task_last_o;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)inflight_count_q<='0;
        else case({input_accept,output_retire})
          2'b10:inflight_count_q<=inflight_count_q+1'b1;
          2'b01:inflight_count_q<=inflight_count_q-1'b1;
          default:inflight_count_q<=inflight_count_q;
        endcase
    end
    assign idle_o=inflight_count_q==0;

`ifndef SYNTHESIS
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      join_valid|->meta_match);
`endif
endmodule
