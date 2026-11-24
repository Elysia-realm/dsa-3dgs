// Dynamically reconfigurable Gaussian-wise projection front-end array. The fixed baseline
// uses the shared G/P/R/E resource mode; enabled projection lanes follow the
// central mode table contract half/all/half/one.
// All modes share arithmetic, descriptor widths, camera configuration, and
// output arbitration. It creates no tile bins/per-tile sorting; block outputs
// are one Gaussian's internal traversal. Commits require a drained epoch boundary.
module raw_gaussian_projection_array #(
    parameter bit ENABLE_COMPRESSED_ATTRIBUTES=1'b0,
    parameter int unsigned LANES    = 4,
    parameter int unsigned META_W   = 64,
    parameter int unsigned COORD_W  = 27,
    parameter int unsigned QUAT_W   = 22,
    parameter int unsigned SCALE_W  = 24,
    parameter int unsigned ROT_W    = 22,
    parameter int unsigned COV2_W   = 35,
    parameter int unsigned SCREEN_W = 27,
    parameter int unsigned PIXEL_W  = 16,
    parameter int unsigned TILE_W   = 12,
    parameter int unsigned MODE_W   = 2,
    parameter int unsigned SEQ_W    = 16,
    parameter int unsigned RETIRE_DEPTH = 16,
    parameter bit ENABLE_OPERAND_ISOLATION = 1'b0,
    parameter bit USE_SHARED_PROJECTION_PE = 1'b0,
    parameter bit SHARED_P_DOT3=1'b0,
    parameter int unsigned PE_DATA_W=32,parameter int unsigned PE_RESULT_W=2*PE_DATA_W+1,
    parameter int unsigned COUNT_W  = $clog2(LANES+1),
    parameter int unsigned INPUT_W  = META_W+3*COORD_W+4*QUAT_W+3*SCALE_W+13+1+(ENABLE_COMPRESSED_ATTRIBUTES?249:0),
    parameter int unsigned RAW_DESC_W = META_W+13+COORD_W+3*COV2_W
        +2*SCREEN_W+4*PIXEL_W+1,
    parameter int unsigned DESC_W = RAW_DESC_W+15+16+15+6+6+1,
    parameter int unsigned TASK_W = DESC_W+2*TILE_W
) (

    input logic [248:0] s_attr_aux_i,
    input logic clk_i,input logic rst_ni,
    input logic shadow_mode_we_i,input logic[MODE_W-1:0]shadow_mode_i,
    input logic mode_commit_i,input logic epoch_boundary_i,
    output logic[MODE_W-1:0]active_mode_o,output logic[COUNT_W-1:0]active_lanes_o,
    output logic[15:0]epoch_id_o,output logic mode_pending_o,
    output logic mode_commit_pulse_o,output logic mode_overrun_o,

    input logic s_valid_i,output logic s_ready_o,input logic[META_W-1:0]s_meta_i,
    input logic signed[COORD_W-1:0]s_world_x_q16_i,s_world_y_q16_i,s_world_z_q16_i,
    input logic signed[QUAT_W-1:0]s_qw_q20_i,s_qx_q20_i,s_qy_q20_i,s_qz_q20_i,
    input logic[SCALE_W-1:0]s_scale_x_q20_i,s_scale_y_q20_i,s_scale_z_q20_i,
    input logic[12:0]s_opacity_q12_i,

    input logic signed[ROT_W-1:0]cfg_r00_q20_i,cfg_r01_q20_i,cfg_r02_q20_i,
    input logic signed[ROT_W-1:0]cfg_r10_q20_i,cfg_r11_q20_i,cfg_r12_q20_i,
    input logic signed[ROT_W-1:0]cfg_r20_q20_i,cfg_r21_q20_i,cfg_r22_q20_i,
    input logic signed[COORD_W-1:0]cfg_tx_q16_i,cfg_ty_q16_i,cfg_tz_q16_i,
    input logic signed[32:0]cfg_fx_q16_i,cfg_fy_q16_i,cfg_cx_q16_i,cfg_cy_q16_i,
    input logic signed[COORD_W-1:0]cfg_near_q16_i,cfg_far_q16_i,
    input logic[COV2_W-1:0]cfg_regularizer_q8_i,
    input logic[PIXEL_W-1:0]cfg_image_width_i,cfg_image_height_i,

    output logic m_task_valid_o,input logic m_task_ready_i,
    output logic[DESC_W-1:0]m_task_desc_o,
    output logic[TILE_W-1:0]m_task_tile_x_o,m_task_tile_y_o,
    output logic m_task_first_o,m_task_last_o,output logic m_task_culled_o,
    output logic culled_pulse_o,
    output logic[LANES-1:0]active_mask_o,output logic all_idle_o,
    output logic retire_wait_o,output logic retire_protocol_error_o,
    output logic pe_req_valid_o,input logic pe_req_ready_i,
    output logic signed[PE_DATA_W-1:0]pe_lhs_o,pe_rhs_o,
    output logic signed[PE_RESULT_W-1:0]pe_acc_o,
    input logic pe_rsp_valid_i,output logic pe_rsp_ready_o,
    input logic signed[PE_RESULT_W-1:0]pe_result_i
);
    logic[MODE_W-1:0]shadow_mode_unused;
    logic[INPUT_W-1:0]input_packet;
    logic[LANES-1:0]lane_s_valid,lane_s_ready;
    logic[LANES-1:0][INPUT_W-1:0]lane_s_data;
    logic[LANES-1:0]lane_task_valid,lane_task_ready,lane_task_first,lane_task_last,lane_task_culled;
    logic[LANES-1:0][TASK_W-1:0]lane_task_data;
    logic[LANES-1:0]lane_culled,lane_idle;
    logic[TASK_W-1:0]merged_task_data;
    genvar lane;
    localparam int unsigned MEAN_META_W=META_W+4*QUAT_W+3*SCALE_W+13+(ENABLE_COMPRESSED_ATTRIBUTES?249:0);
    logic[MEAN_META_W-1:0]source_mean_meta;
    assign source_mean_meta=ENABLE_COMPRESSED_ATTRIBUTES?MEAN_META_W'({s_meta_i,s_qw_q20_i,s_qx_q20_i,s_qy_q20_i,s_qz_q20_i,s_scale_x_q20_i,s_scale_y_q20_i,s_scale_z_q20_i,s_opacity_q12_i,s_attr_aux_i}):MEAN_META_W'({s_meta_i,s_qw_q20_i,s_qx_q20_i,s_qy_q20_i,s_qz_q20_i,s_scale_x_q20_i,s_scale_y_q20_i,s_scale_z_q20_i,s_opacity_q12_i});
    logic dispatch_valid,dispatch_ready,mean_busy,scheduler_idle,dispatch_overflow;
    logic[MEAN_META_W-1:0]mean_meta;
    logic signed[COORD_W-1:0]dispatch_x,dispatch_y,dispatch_z;

    generate if(USE_SHARED_PROJECTION_PE)begin:g_shared_mean
      world_to_camera_shared_mac #(.META_W(MEAN_META_W),.COORD_W(COORD_W),.ROT_W(ROT_W),
        .PE_DATA_W(PE_DATA_W),.PE_RESULT_W(PE_RESULT_W),.USE_DOT3(SHARED_P_DOT3))u_mean(
        .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i),.s_ready_o(s_ready_o),
        .s_meta_i(source_mean_meta),
        .s_world_x_q16_i(s_world_x_q16_i),.s_world_y_q16_i(s_world_y_q16_i),.s_world_z_q16_i(s_world_z_q16_i),
        .cfg_r00_q20_i(cfg_r00_q20_i),.cfg_r01_q20_i(cfg_r01_q20_i),.cfg_r02_q20_i(cfg_r02_q20_i),
        .cfg_r10_q20_i(cfg_r10_q20_i),.cfg_r11_q20_i(cfg_r11_q20_i),.cfg_r12_q20_i(cfg_r12_q20_i),
        .cfg_r20_q20_i(cfg_r20_q20_i),.cfg_r21_q20_i(cfg_r21_q20_i),.cfg_r22_q20_i(cfg_r22_q20_i),
        .cfg_tx_q16_i(cfg_tx_q16_i),.cfg_ty_q16_i(cfg_ty_q16_i),.cfg_tz_q16_i(cfg_tz_q16_i),
        .m_valid_o(dispatch_valid),.m_ready_i(dispatch_ready),.m_meta_o(mean_meta),
        .m_camera_x_q16_o(dispatch_x),.m_camera_y_q16_o(dispatch_y),.m_camera_z_q16_o(dispatch_z),
        .m_overflow_o(dispatch_overflow),.busy_o(mean_busy),
        .pe_req_valid_o(pe_req_valid_o),.pe_req_ready_i(pe_req_ready_i),.pe_lhs_o(pe_lhs_o),.pe_rhs_o(pe_rhs_o),
        .pe_acc_o(pe_acc_o),.pe_rsp_valid_i(pe_rsp_valid_i),.pe_rsp_ready_o(pe_rsp_ready_o),.pe_result_i(pe_result_i));
    end else begin:g_local_mean
      assign s_ready_o=dispatch_ready;assign dispatch_valid=s_valid_i;assign mean_busy=1'b0;
      assign mean_meta=source_mean_meta;
      assign dispatch_x=s_world_x_q16_i;assign dispatch_y=s_world_y_q16_i;assign dispatch_z=s_world_z_q16_i;
      assign dispatch_overflow=1'b0;assign pe_req_valid_o=1'b0;assign pe_lhs_o='0;assign pe_rhs_o='0;
      assign pe_acc_o='0;assign pe_rsp_ready_o=1'b1;
    end endgenerate
    assign input_packet={mean_meta[MEAN_META_W-1 -: META_W],dispatch_x,dispatch_y,dispatch_z,
      mean_meta[MEAN_META_W-META_W-1:0],dispatch_overflow};
    assign all_idle_o=scheduler_idle&&!mean_busy;

    projection_epoch_lane_ctrl #(.LANES(LANES),.MODE_W(MODE_W),.COUNT_W(COUNT_W))u_mode(
      .clk_i(clk_i),.rst_ni(rst_ni),.shadow_we_i(shadow_mode_we_i),
      .shadow_mode_i(shadow_mode_i),.commit_i(mode_commit_i),
      .epoch_boundary_i(epoch_boundary_i),.lane_array_idle_i(all_idle_o),
      .shadow_mode_o(shadow_mode_unused),.active_mode_o(active_mode_o),
      .active_lanes_o(active_lanes_o),.epoch_id_o(epoch_id_o),
      .commit_pending_o(mode_pending_o),.commit_pulse_o(mode_commit_pulse_o),
      .commit_overrun_o(mode_overrun_o));

    ordered_projection_lane_scheduler #(.LANES(LANES),.INPUT_W(INPUT_W),.TASK_W(TASK_W),
      .META_W(META_W),.SEQ_W(SEQ_W),.RETIRE_DEPTH(RETIRE_DEPTH),
      .ENABLE_OPERAND_ISOLATION(ENABLE_OPERAND_ISOLATION),.COUNT_W(COUNT_W))u_scheduler(
      .clk_i(clk_i),.rst_ni(rst_ni),.cfg_active_lanes_i(active_lanes_o),
      .s_valid_i(dispatch_valid),.s_ready_o(dispatch_ready),.s_data_i(input_packet),
      .lane_s_valid_o(lane_s_valid),.lane_s_ready_i(lane_s_ready),
      .lane_s_data_o(lane_s_data),.lane_task_valid_i(lane_task_valid),
      .lane_task_ready_o(lane_task_ready),.lane_task_data_i(lane_task_data),
      .lane_task_first_i(lane_task_first),.lane_task_last_i(lane_task_last),
      .lane_task_culled_i(lane_task_culled),.lane_idle_i(lane_idle),
      .m_valid_o(m_task_valid_o),.m_ready_i(m_task_ready_i),.m_data_o(merged_task_data),
      .m_first_o(m_task_first_o),.m_last_o(m_task_last_o),
      .m_culled_o(m_task_culled_o),.culled_pulse_o(culled_pulse_o),
      .active_mask_o(active_mask_o),.all_idle_o(scheduler_idle),.retire_wait_o(retire_wait_o),
      .retire_protocol_error_o(retire_protocol_error_o),.retire_occupancy_o());
    assign {m_task_desc_o,m_task_tile_x_o,m_task_tile_y_o}=merged_task_data;

    generate for(lane=0;lane<LANES;lane=lane+1)begin:g_lane
      logic[248:0]lane_aux;
      logic[META_W-1:0]lane_meta;logic signed[COORD_W-1:0]lane_x,lane_y,lane_z;
      logic signed[QUAT_W-1:0]lane_qw,lane_qx,lane_qy,lane_qz;
      logic[SCALE_W-1:0]lane_sx,lane_sy,lane_sz;logic[12:0]lane_opacity;logic lane_mean_overflow;
      logic[DESC_W-1:0]lane_desc;logic[TILE_W-1:0]lane_tile_x,lane_tile_y;
      assign {lane_meta,lane_x,lane_y,lane_z,lane_qw,lane_qx,lane_qy,lane_qz,
        lane_sx,lane_sy,lane_sz,lane_opacity}=lane_s_data[lane]>>(1+(ENABLE_COMPRESSED_ATTRIBUTES?249:0));
      assign lane_mean_overflow=lane_s_data[lane][0];
      assign lane_aux=ENABLE_COMPRESSED_ATTRIBUTES?249'(lane_s_data[lane]>>1):249'd0;
      raw_gaussian_projection_lane #(.ENABLE_COMPRESSED_ATTRIBUTES(ENABLE_COMPRESSED_ATTRIBUTES),.META_W(META_W),.COORD_W(COORD_W),
        .QUAT_W(QUAT_W),.SCALE_W(SCALE_W),.ROT_W(ROT_W),.COV2_W(COV2_W),.MEAN_IS_CAMERA(USE_SHARED_PROJECTION_PE),
        .SCREEN_W(SCREEN_W),.PIXEL_W(PIXEL_W),.TILE_W(TILE_W),
        .RAW_DESC_W(RAW_DESC_W),.DESC_W(DESC_W))u_lane(
        .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(lane_s_valid[lane]),
        .s_ready_o(lane_s_ready[lane]),.s_meta_i(lane_meta),
        .s_world_x_q16_i(lane_x),.s_world_y_q16_i(lane_y),.s_world_z_q16_i(lane_z),
        .s_mean_overflow_i(lane_mean_overflow),
        .s_qw_q20_i(lane_qw),.s_qx_q20_i(lane_qx),.s_qy_q20_i(lane_qy),.s_qz_q20_i(lane_qz),
        .s_scale_x_q20_i(lane_sx),.s_scale_y_q20_i(lane_sy),.s_scale_z_q20_i(lane_sz),
        .s_attr_aux_i(lane_aux),.s_opacity_q12_i(lane_opacity),.cfg_r00_q20_i(cfg_r00_q20_i),
        .cfg_r01_q20_i(cfg_r01_q20_i),.cfg_r02_q20_i(cfg_r02_q20_i),
        .cfg_r10_q20_i(cfg_r10_q20_i),.cfg_r11_q20_i(cfg_r11_q20_i),.cfg_r12_q20_i(cfg_r12_q20_i),
        .cfg_r20_q20_i(cfg_r20_q20_i),.cfg_r21_q20_i(cfg_r21_q20_i),.cfg_r22_q20_i(cfg_r22_q20_i),
        .cfg_tx_q16_i(cfg_tx_q16_i),.cfg_ty_q16_i(cfg_ty_q16_i),.cfg_tz_q16_i(cfg_tz_q16_i),
        .cfg_fx_q16_i(cfg_fx_q16_i),.cfg_fy_q16_i(cfg_fy_q16_i),
        .cfg_cx_q16_i(cfg_cx_q16_i),.cfg_cy_q16_i(cfg_cy_q16_i),
        .cfg_near_q16_i(cfg_near_q16_i),.cfg_far_q16_i(cfg_far_q16_i),
        .cfg_regularizer_q8_i(cfg_regularizer_q8_i),.cfg_image_width_i(cfg_image_width_i),
        .cfg_image_height_i(cfg_image_height_i),.m_task_valid_o(lane_task_valid[lane]),
        .m_task_ready_i(lane_task_ready[lane]),.m_task_desc_o(lane_desc),
        .m_task_tile_x_o(lane_tile_x),.m_task_tile_y_o(lane_tile_y),
        .m_task_first_o(lane_task_first[lane]),.m_task_last_o(lane_task_last[lane]),
        .m_task_culled_o(lane_task_culled[lane]),.culled_pulse_o(lane_culled[lane]),
        .idle_o(lane_idle[lane]));
      assign lane_task_data[lane]={lane_desc,lane_tile_x,lane_tile_y};
    end endgenerate
endmodule
