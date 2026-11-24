// Conservative 3-sigma screen bounding box and tile range generator.
// The largest covariance eigenvalue is upper-bounded with Gershgorin:
// max(cov00+abs(cov01), cov11+abs(cov01)). This may issue extra tiles but
// cannot shrink the true 3-sigma support. Bounding boxes are [x0,x1),[y0,y1).
module bbox_tile_bounds_core #(
    parameter int unsigned META_W = 64,
    parameter int unsigned SCREEN_W = 27,
    parameter int unsigned COV_W = 35,
    parameter int unsigned PIXEL_W = 16,
    parameter int unsigned TILE_W = 12,
    parameter int unsigned TILE_LOG2 = 3
) (
    input  logic                       clk_i,
    input  logic                       rst_ni,
    input  logic                       s_valid_i,
    output logic                       s_ready_o,
    input  logic [META_W-1:0]          s_meta_i,
    input  logic signed [SCREEN_W-1:0] s_mean_x_q8_i,
    input  logic signed [SCREEN_W-1:0] s_mean_y_q8_i,
    input  logic [COV_W-1:0]           s_cov00_q8_i,
    input  logic signed [COV_W-1:0]    s_cov01_q8_i,
    input  logic [COV_W-1:0]           s_cov11_q8_i,
    input  logic [12:0]                s_opacity_q12_i,
    input  logic                       s_visible_i,
    input  logic                       s_numeric_overflow_i,
    input  logic [PIXEL_W-1:0]         cfg_image_width_i,
    input  logic [PIXEL_W-1:0]         cfg_image_height_i,
    output logic                       m_valid_o,
    input  logic                       m_ready_i,
    output logic [META_W-1:0]          m_meta_o,
    output logic signed [SCREEN_W-1:0] m_mean_x_q8_o,
    output logic signed [SCREEN_W-1:0] m_mean_y_q8_o,
    output logic [PIXEL_W-1:0]         m_x0_o,
    output logic [PIXEL_W-1:0]         m_y0_o,
    output logic [PIXEL_W-1:0]         m_x1_o,
    output logic [PIXEL_W-1:0]         m_y1_o,
    output logic [TILE_W-1:0]          m_tile_x0_o,
    output logic [TILE_W-1:0]          m_tile_y0_o,
    output logic [TILE_W-1:0]          m_tile_x1_o,
    output logic [TILE_W-1:0]          m_tile_y1_o,
    output logic                       m_keep_o,
    output logic                       m_numeric_invalid_o
);
    localparam int unsigned RESULT_W = META_W + 2*SCREEN_W + 4*PIXEL_W + 4*TILE_W + 2;
    localparam int unsigned SQRT_ROOT_W=(COV_W+1)/2;
    localparam int unsigned SQRT_META_W=META_W+2*SCREEN_W+13+2+2*PIXEL_W;
    localparam int unsigned RADIUS_PRODUCT_W=SQRT_ROOT_W+1+4;
    logic [COV_W-1:0] cov01_abs, eigen_bound_q8;
    logic [COV_W:0] row0_bound, row1_bound;
    logic sqrt_valid,sqrt_ready,sqrt_exact;
    logic[SQRT_ROOT_W-1:0]sqrt_floor_q4;
    logic[SQRT_ROOT_W:0]sqrt_q4;
    logic[SQRT_META_W-1:0]sqrt_meta_in,sqrt_meta_out;
    logic[META_W-1:0]meta_sqrt;
    logic signed[SCREEN_W-1:0]mean_x_sqrt,mean_y_sqrt;
    logic[12:0]opacity_sqrt;logic visible_sqrt,numeric_overflow_sqrt;
    logic[PIXEL_W-1:0]image_width_sqrt,image_height_sqrt;
    logic [3:0] radius_sigma_q2;
    logic [RADIUS_PRODUCT_W-1:0] radius_product_q6,radius_pixels;
    logic signed [SCREEN_W-1:0] center_x, center_y;
    logic signed [SCREEN_W:0] raw_x0, raw_y0, raw_x1, raw_y1;
    logic signed [SCREEN_W:0] center_x_ext,center_y_ext,radius_ext;
    logic signed [SCREEN_W:0] image_width_ext,image_height_ext;
    logic [PIXEL_W-1:0] x0, y0, x1, y1;
    logic [TILE_W-1:0] tile_x0, tile_y0, tile_x1, tile_y1;
    logic keep, numeric_invalid;
    logic [RESULT_W-1:0] result_data;

    assign cov01_abs = s_cov01_q8_i[COV_W-1]
        ? -$signed(s_cov01_q8_i) : s_cov01_q8_i;
    assign row0_bound = {1'b0,s_cov00_q8_i} + {1'b0,cov01_abs};
    assign row1_bound = {1'b0,s_cov11_q8_i} + {1'b0,cov01_abs};
    assign eigen_bound_q8 = (|row0_bound[COV_W:COV_W] || |row1_bound[COV_W:COV_W])
        ? {COV_W{1'b1}}
        : row0_bound >= row1_bound ? row0_bound[COV_W-1:0] : row1_bound[COV_W-1:0];
    // A restoring square-root pipeline replaces the former 32-step
    // combinational multiply/compare chain. Throughput remains one Gaussian
    // per cycle while the critical path is bounded to one restoring stage.
    assign sqrt_meta_in={s_meta_i,s_mean_x_q8_i,s_mean_y_q8_i,s_opacity_q12_i,
        s_visible_i,s_numeric_overflow_i,cfg_image_width_i,cfg_image_height_i};
    fixed_sqrt_pipe #(.RAD_W(COV_W),.META_W(SQRT_META_W))u_radius_sqrt(
        .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i),.s_ready_o(s_ready_o),
        .s_radicand_i(eigen_bound_q8),.s_meta_i(sqrt_meta_in),
        .m_valid_o(sqrt_valid),.m_ready_i(sqrt_ready),.m_root_o(sqrt_floor_q4),
        .m_meta_o(sqrt_meta_out),.m_exact_o(sqrt_exact));
    assign {meta_sqrt,mean_x_sqrt,mean_y_sqrt,opacity_sqrt,visible_sqrt,
        numeric_overflow_sqrt,image_width_sqrt,image_height_sqrt}=sqrt_meta_out;
    // ceil(sqrt(Q8)) produces a conservative Q4 value. The opacity-aware Q2.2 multiplier is rounded
    // upward, so ceil(product/64) remains a conservative pixel support.
    assign sqrt_q4={1'b0,sqrt_floor_q4}+(!sqrt_exact);
    opacity_radius_bound u_opacity_radius(
        .opacity_q12_i(opacity_sqrt),.radius_q2_o(radius_sigma_q2));
    assign radius_product_q6 = sqrt_q4 * radius_sigma_q2;
    assign radius_pixels=(radius_product_q6+RADIUS_PRODUCT_W'(63))>>6;
    assign center_x = $signed(mean_x_sqrt) >>> 8;
    assign center_y = $signed(mean_y_sqrt) >>> 8;
    assign center_x_ext={center_x[SCREEN_W-1],center_x};
    assign center_y_ext={center_y[SCREEN_W-1],center_y};
    assign radius_ext=$signed({{(SCREEN_W+1-RADIUS_PRODUCT_W){1'b0}},radius_pixels});
    assign image_width_ext=$signed({{(SCREEN_W+1-PIXEL_W){1'b0}},image_width_sqrt});
    assign image_height_ext=$signed({{(SCREEN_W+1-PIXEL_W){1'b0}},image_height_sqrt});
    assign raw_x0=center_x_ext-radius_ext;assign raw_y0=center_y_ext-radius_ext;
    assign raw_x1=center_x_ext+radius_ext+(SCREEN_W+1)'(1);
    assign raw_y1=center_y_ext+radius_ext+(SCREEN_W+1)'(1);

    always_comb begin
        numeric_invalid = numeric_overflow_sqrt;
        if (numeric_invalid) begin
            // A saturated projection has no trustworthy conic or support.
            // Retire it as one ordered culled event instead of expanding a
            // fake full-screen Gaussian through every 8x8 block.
            x0='0; y0='0; x1='0; y1='0;
        end else begin
            x0 = raw_x0 <= 0 ? '0
                : raw_x0 >= image_width_ext
                    ? image_width_sqrt : raw_x0[PIXEL_W-1:0];
            y0 = raw_y0 <= 0 ? '0
                : raw_y0 >= image_height_ext
                    ? image_height_sqrt : raw_y0[PIXEL_W-1:0];
            x1 = raw_x1 <= 0 ? '0
                : raw_x1 >= image_width_ext
                    ? image_width_sqrt : raw_x1[PIXEL_W-1:0];
            y1 = raw_y1 <= 0 ? '0
                : raw_y1 >= image_height_ext
                    ? image_height_sqrt : raw_y1[PIXEL_W-1:0];
        end
        keep = !numeric_invalid && visible_sqrt
            && image_width_sqrt != 0 && image_height_sqrt != 0
            && x0 < x1 && y0 < y1;
        tile_x0=TILE_W'(x0>>TILE_LOG2);tile_y0=TILE_W'(y0>>TILE_LOG2);
        tile_x1=keep?TILE_W'((x1-1'b1)>>TILE_LOG2):'0;
        tile_y1=keep?TILE_W'((y1-1'b1)>>TILE_LOG2):'0;
    end

    assign result_data = {meta_sqrt,mean_x_sqrt,mean_y_sqrt,x0,y0,x1,y1,
                          tile_x0,tile_y0,tile_x1,tile_y1,keep,numeric_invalid};
    rv_reg_slice #(.DATA_W(RESULT_W)) u_result(
        .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(sqrt_valid),.s_ready_o(sqrt_ready),
        .s_data_i(result_data),.m_valid_o(m_valid_o),.m_ready_i(m_ready_i),
        .m_data_o({m_meta_o,m_mean_x_q8_o,m_mean_y_q8_o,m_x0_o,m_y0_o,m_x1_o,m_y1_o,
                   m_tile_x0_o,m_tile_y0_o,m_tile_x1_o,m_tile_y1_o,m_keep_o,
                   m_numeric_invalid_o}));
endmodule
