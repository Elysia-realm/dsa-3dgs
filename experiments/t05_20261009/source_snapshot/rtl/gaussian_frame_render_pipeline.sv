// Frame-level Gaussian-wise render data path. A frame first advances the
// render epoch (also applying its requested G/P/R/E mode), then accepts the
// mean-only depth-prepass stream, performs coarse depth grouping and stable
// in-group sorting, fetches each complete Gaussian once by GID, and renders
// its internal 8x8 blocks. No Gaussian-tile bin or per-tile sort is created.
module gaussian_frame_render_pipeline #(
    parameter int unsigned ATTR_DEPTH=1024,
    parameter int unsigned LANES=4,
    parameter int unsigned GROUPS=4,
    parameter int unsigned GROUP_CAPACITY=8,
    parameter int unsigned SORT_CAPACITY=8,
    parameter int unsigned STATE_ENTRIES=4096,
    parameter int unsigned STATE_WINDOW_ENTRIES=2,
    parameter int unsigned STATE_MSHR_COUNT=2,
    parameter bit ENABLE_RESPONSE_BLEND_BYPASS=1'b0,
    parameter bit ENABLE_BLEND_COMMIT_BYPASS=1'b0,
    parameter bit ENABLE_OPERAND_ISOLATION=1'b0,
    parameter bit ENABLE_SHAPE_BLOCK_REJECT=1'b0,
    parameter int unsigned GID_W=32,
    parameter int unsigned SEQ_W=16,
    parameter int unsigned EPOCH_W=16,
    parameter int unsigned COORD_W=27,
    parameter int unsigned QUAT_W=22,
    parameter int unsigned SCALE_W=24,
    parameter int unsigned ROT_W=22,
    parameter int unsigned COV2_W=35,
    parameter int unsigned PIXEL_COORD_W=16,
    parameter int unsigned COEFF_W=18,
    parameter bit USE_SHARED_PE=1'b1,
    // Optional area/performance experiment.  When set, the collect-only Z
    // transform uses the three-multiplier streaming core while sorting and
    // the full XYZ transform continue to use the shared G/P PE.  Default is
    // the area-oriented fully shared prepass.
    parameter bit USE_STREAMING_DEPTH_PREPASS=1'b0,
    parameter bit USE_PARALLEL_GROUP_SORT=1'b0,
    parameter bit USE_BITONIC_SORT=1'b0,
    parameter bit SHARED_SORT_BINARY_SEARCH=1'b0,
    parameter bit PARALLEL_SORT_SERIAL_FALLBACK=1'b1,
    parameter bit PARALLEL_SORT_BATCH_FORWARDING=1'b1,
    parameter bit PARALLEL_SORT_PHASE_FORWARDING=1'b1,
    parameter bit PARALLEL_SORT_MONOTONIC_FASTPATH=1'b1,
    parameter bit PARALLEL_SORT_STABLE_RUN_FASTPATH=1'b1,
    parameter int unsigned PREPASS_CONTEXTS=4,
    parameter bit USE_SHARED_PROJECTION_PE=1'b1,
    parameter bit USE_SHARED_RASTER_PE=1'b0,
    parameter bit ENABLE_ALPHA_ZERO_SKIP=1'b0,
    parameter bit USE_EXTERNAL_ATTR_BACKEND=1'b0,
    parameter bit USE_STATE_CACHE_BACKEND=1'b0,
    parameter int unsigned COEFFS=16,
    parameter int unsigned GROUP_W=GROUPS<=2?1:$clog2(GROUPS),
    parameter int unsigned COEFF_FLAT_W=3*COEFFS*COEFF_W
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic frame_start_i,
    input  logic frame_continue_i,
    input  logic [1:0] frame_mode_i,
    output logic frame_ready_o,
    output logic frame_busy_o,
    output logic frame_done_pulse_o,
    output logic frame_error_o,
    output logic [9:0] frame_error_status_o,

    input  logic source_valid_i,
    output logic source_ready_o,
    input  logic [GID_W-1:0] source_gid_i,
    input  logic signed [COORD_W-1:0] source_world_x_q16_i,
    input  logic signed [COORD_W-1:0] source_world_y_q16_i,
    input  logic signed [COORD_W-1:0] source_world_z_q16_i,
    input  logic source_last_i,
    input  logic source_end_valid_i,
    output logic source_end_ready_o,

    input  logic runtime_mode_valid_i,
    input  logic [1:0] runtime_mode_i,
    output logic [1:0] active_mode_o,
    output logic [EPOCH_W-1:0] epoch_id_o,
    output logic mode_pending_o,
    output logic mode_commit_pulse_o,

    input  logic attr_clear_valid_i,
    input  logic attr_write_en_i,
    input  logic [GID_W-1:0] attr_write_gid_i,
    input  logic signed [COORD_W-1:0] attr_write_world_x_q16_i,
    input  logic signed [COORD_W-1:0] attr_write_world_y_q16_i,
    input  logic signed [COORD_W-1:0] attr_write_world_z_q16_i,
    input  logic signed [QUAT_W-1:0] attr_write_qw_q20_i,
    input  logic signed [QUAT_W-1:0] attr_write_qx_q20_i,
    input  logic signed [QUAT_W-1:0] attr_write_qy_q20_i,
    input  logic signed [QUAT_W-1:0] attr_write_qz_q20_i,
    input  logic [SCALE_W-1:0] attr_write_scale_x_q20_i,
    input  logic [SCALE_W-1:0] attr_write_scale_y_q20_i,
    input  logic [SCALE_W-1:0] attr_write_scale_z_q20_i,
    input  logic [12:0] attr_write_opacity_q12_i,
    input  logic [COEFF_FLAT_W-1:0] attr_write_coeff_q12_flat_i,
    output logic attr_req_valid_o,input logic attr_req_ready_i,output logic[GID_W-1:0]attr_req_gid_o,
    input logic attr_rsp_valid_i,output logic attr_rsp_ready_o,input logic attr_rsp_error_i,
    input logic[3*COORD_W+4*QUAT_W+3*SCALE_W+13+COEFF_FLAT_W-1:0]attr_rsp_data_i,

    input  logic signed [ROT_W-1:0] cfg_r00_q20_i,
    input  logic signed [ROT_W-1:0] cfg_r01_q20_i,
    input  logic signed [ROT_W-1:0] cfg_r02_q20_i,
    input  logic signed [ROT_W-1:0] cfg_r10_q20_i,
    input  logic signed [ROT_W-1:0] cfg_r11_q20_i,
    input  logic signed [ROT_W-1:0] cfg_r12_q20_i,
    input  logic signed [ROT_W-1:0] cfg_r20_q20_i,
    input  logic signed [ROT_W-1:0] cfg_r21_q20_i,
    input  logic signed [ROT_W-1:0] cfg_r22_q20_i,
    input  logic signed [COORD_W-1:0] cfg_tx_q16_i,
    input  logic signed [COORD_W-1:0] cfg_ty_q16_i,
    input  logic signed [COORD_W-1:0] cfg_tz_q16_i,
    input  logic signed [COORD_W-1:0] cfg_camera_x_q16_i,
    input  logic signed [COORD_W-1:0] cfg_camera_y_q16_i,
    input  logic signed [COORD_W-1:0] cfg_camera_z_q16_i,
    input  logic signed [32:0] cfg_fx_q16_i,
    input  logic signed [32:0] cfg_fy_q16_i,
    input  logic signed [32:0] cfg_cx_q16_i,
    input  logic signed [32:0] cfg_cy_q16_i,
    input  logic signed [COORD_W-1:0] cfg_near_q16_i,
    input  logic signed [COORD_W-1:0] cfg_far_q16_i,
    input  logic [COV2_W-1:0] cfg_regularizer_q8_i,
    input  logic signed [COORD_W-1:0] cfg_depth_pivot0_q16_i,
    input  logic signed [COORD_W-1:0] cfg_depth_pivot1_q16_i,
    input  logic signed [COORD_W-1:0] cfg_depth_pivot2_q16_i,
    input  logic [PIXEL_COORD_W-1:0] cfg_image_width_i,
    input  logic [PIXEL_COORD_W-1:0] cfg_image_height_i,

    output logic commit_valid_o,
    input  logic commit_ready_i,
    output logic [31:0] commit_task_id_o,
    output logic [31:0] commit_block_id_o,
    output logic [GID_W-1:0] commit_gid_o,
    output logic [EPOCH_W-1:0] commit_epoch_id_o,
    output logic [12:0] commit_alpha_q12_o,
    output logic commit_pass_alpha_o,
    output logic [31:0] commit_pixel_id_o,
    output logic [12:0] commit_r_q12_o,
    output logic [12:0] commit_g_q12_o,
    output logic [12:0] commit_b_q12_o,
    output logic [15:0] commit_t_q16_o,
    output logic commit_newly_terminated_o,
    output logic [LANES-1:0] projection_active_mask_o,
    output logic [LANES-1:0] sh_active_mask_o,
    output logic [LANES-1:0] raster_active_mask_o,
    output logic attribute_read_pulse_o,
    output logic event_group_pressure_o,
    output logic event_sort_busy_o,
    output logic event_projection_busy_o,
    output logic event_raster_busy_o,
    output logic event_block_candidate_o,
    output logic event_shape_block_reject_o,
    output logic event_terminated_skip_o,
    output logic shared_pe_group_grant_o,
    output logic shared_pe_projection_grant_o,
    output logic shared_pe_raster_grant_o,
    output logic shared_pe_group_stall_o,
    output logic shared_pe_projection_stall_o,
    output logic shared_pe_raster_stall_o,
    output logic shared_pe_utilization_o,
    output logic shared_pe_clock_enable_o,
    output logic shared_pe_busy_o,
    output logic[383:0]sort_work_totals_o,
    output logic state_miss_req_valid_o,input logic state_miss_req_ready_i,
    output logic[1:0]state_miss_req_tag_o,output logic[31:0]state_miss_req_pixel_id_o,input logic state_miss_rsp_valid_i,
    output logic state_miss_rsp_ready_o,input logic[1:0]state_miss_rsp_tag_i,input logic state_miss_rsp_error_i,
    input logic[127:0]state_miss_rsp_data_i,output logic state_cache_error_o,state_cache_idle_o
);
    typedef enum logic [1:0] {FRAME_IDLE,FRAME_PREP,FRAME_COLLECT,FRAME_DRAIN} frame_state_t;
    frame_state_t state_q;
    logic input_closed_q,group_done_seen_q;
    logic init_mode_pulse_q,accepted_start,mode_request;
    logic [1:0] init_mode_q,mode_shadow,deferred_mode_q;
    logic deferred_mode_valid_q,render_mode_pending;

    logic pre_s_ready,pre_valid,pre_ready,pre_visible,pre_numeric_overflow,pre_last;
    logic signed [COORD_W-1:0] pre_depth;
    logic [GID_W-1:0] pre_gid;
    logic [SEQ_W-1:0] pre_seq;

    logic group_s_valid,group_s_ready,group_valid,group_ready,group_first,group_last;
    logic signed [COORD_W-1:0] group_depth;
    logic [GID_W-1:0] group_gid;
    logic [SEQ_W-1:0] group_seq;
    logic [GROUP_W-1:0] group_id;
    logic group_frame_end,group_frame_done,group_overflow,group_busy;

    logic sorted_valid,sorted_ready,sorted_first,sorted_last,sort_overflow,sort_busy;
    logic signed [COORD_W-1:0] sorted_depth;
    logic [GID_W-1:0] sorted_gid;
    logic [SEQ_W-1:0] sorted_seq;
    logic [GROUP_W-1:0] sorted_group;
    localparam int unsigned GROUP_LANE_COUNT_W=LANES<1?1:$clog2(LANES+1);
    logic [GROUP_LANE_COUNT_W-1:0] group_active_lanes;
    logic group_sort_valid,group_sort_ready,group_service_grant,group_service_stall;
    localparam int unsigned PE_DATA_W=32;
    localparam int unsigned PE_RESULT_W=2*PE_DATA_W+1;
    logic[2:0]group_weight,projection_weight,raster_weight;
    logic[1:0]shared_math_owner;logic aggressive_clock_gate;
    logic pe_g_req_valid,pe_g_req_ready,pe_g_rsp_valid,pe_g_rsp_ready,pe_g_less;
    logic signed[PE_DATA_W-1:0]pe_g_lhs,pe_g_rhs;
    logic signed[PE_RESULT_W-1:0]pe_g_result;
    logic[GID_W-1:0]pe_g_lhs_gid,pe_g_rhs_gid;
    logic[SEQ_W-1:0]pe_g_lhs_seq,pe_g_rhs_seq;
    logic pe_p_req_valid,pe_p_req_ready,pe_p_rsp_valid,pe_p_rsp_ready;
    logic signed[PE_DATA_W-1:0]pe_p_lhs,pe_p_rhs;
    logic signed[PE_RESULT_W-1:0]pe_p_acc,pe_p_result;
    logic pe_r_req_valid,pe_r_req_ready,pe_r_rsp_valid,pe_r_rsp_ready;
    logic signed[PE_DATA_W-1:0]pe_r_lhs,pe_r_rhs;
    logic signed[PE_RESULT_W-1:0]pe_r_result;
    logic pre_pe_valid,pre_pe_ready,pre_pe_rsp_valid,pre_pe_rsp_ready;
    logic render_pe_valid,render_pe_ready,render_pe_rsp_valid,render_pe_rsp_ready;
    logic signed[PE_DATA_W-1:0]pre_pe_lhs,pre_pe_rhs,render_pe_lhs,render_pe_rhs;
    logic signed[PE_RESULT_W-1:0]pre_pe_acc,render_pe_acc;
    logic select_pre_pe;
    logic render_projection_busy;

    // The collect prepass is fully consumed before FRAME_DRAIN can issue
    // full attributes. P-client ownership therefore changes only when empty.
    assign select_pre_pe=state_q==FRAME_COLLECT;
    assign pe_p_req_valid=select_pre_pe?pre_pe_valid:render_pe_valid;
    assign pe_p_lhs=select_pre_pe?pre_pe_lhs:render_pe_lhs;
    assign pe_p_rhs=select_pre_pe?pre_pe_rhs:render_pe_rhs;
    assign pe_p_acc=select_pre_pe?pre_pe_acc:render_pe_acc;
    assign pre_pe_ready=select_pre_pe&&pe_p_req_ready;
    assign render_pe_ready=!select_pre_pe&&pe_p_req_ready;
    assign pre_pe_rsp_valid=select_pre_pe&&pe_p_rsp_valid;
    assign render_pe_rsp_valid=!select_pre_pe&&pe_p_rsp_valid;
    assign pe_p_rsp_ready=select_pre_pe?pre_pe_rsp_ready:render_pe_rsp_ready;

    logic render_idle,render_retire_wait,render_protocol_error,render_mode_overrun;
    logic attr_invalid,attr_unloaded,attr_write_invalid;
    logic block_terminated,skipped_terminated,empty_or_culled;
    logic clear_frame_errors;
    logic [9:0] error_q;
    logic [2*PIXEL_COORD_W-1:0] configured_pixels;
    logic frame_capacity_error;

    assign frame_ready_o=state_q==FRAME_IDLE;
    assign frame_busy_o=state_q!=FRAME_IDLE;
    assign accepted_start=frame_start_i&&frame_ready_o;
    assign clear_frame_errors=accepted_start&&!frame_continue_i;
    assign source_ready_o=state_q==FRAME_COLLECT&&!input_closed_q&&pre_s_ready;
    // Empty/error DMA end must not switch P ownership while accepted means
    // still have queued or outstanding depth work. The DMA holds end_valid.
    logic[$clog2(PREPASS_CONTEXTS+1)-1:0]pre_inflight_q;
    assign source_end_ready_o=state_q==FRAME_COLLECT&&!input_closed_q&&pre_inflight_q==0&&!source_valid_i;
    assign group_s_valid=pre_valid&&pre_visible;
    assign pre_ready=pre_visible?group_s_ready:1'b1;
    assign group_frame_end=pre_valid&&pre_ready&&pre_last;
    // Runtime recommendations never freeze a partially drained sorter. They
    // are deferred and atomically applied with the next frame's new epoch.
    assign mode_request=init_mode_pulse_q;
    assign mode_shadow=init_mode_q;
    assign mode_pending_o=render_mode_pending||deferred_mode_valid_q;
    assign frame_error_status_o=error_q;
    assign frame_error_o=|error_q;
    assign configured_pixels=cfg_image_width_i*cfg_image_height_i;
    assign frame_capacity_error=!USE_STATE_CACHE_BACKEND&&(configured_pixels>STATE_ENTRIES);

    generate
      if(USE_SHARED_PE&&!USE_STREAMING_DEPTH_PREPASS)begin:g_shared_prepass
        gaussian_depth_prepass_shared_mac #(.GID_W(GID_W),.SEQ_W(SEQ_W),.PAYLOAD_W(1),
          .COORD_W(COORD_W),.ROT_W(ROT_W),.PE_DATA_W(PE_DATA_W),.PE_RESULT_W(PE_RESULT_W),
          .CONTEXTS(PREPASS_CONTEXTS))u_prepass(
          .clk_i(clk_i),.rst_ni(rst_ni),.frame_start_i(accepted_start),
          .s_valid_i(source_valid_i&&state_q==FRAME_COLLECT&&!input_closed_q),.s_ready_o(pre_s_ready),
          .s_gid_i(source_gid_i),.s_payload_i(source_last_i),
          .s_world_x_q16_i(source_world_x_q16_i),.s_world_y_q16_i(source_world_y_q16_i),
          .s_world_z_q16_i(source_world_z_q16_i),.cfg_r20_q20_i(cfg_r20_q20_i),
          .cfg_r21_q20_i(cfg_r21_q20_i),.cfg_r22_q20_i(cfg_r22_q20_i),.cfg_tz_q16_i(cfg_tz_q16_i),
          .cfg_near_q16_i(cfg_near_q16_i),.cfg_far_q16_i(cfg_far_q16_i),
          .m_valid_o(pre_valid),.m_ready_i(pre_ready),.m_depth_q16_o(pre_depth),.m_gid_o(pre_gid),
          .m_seq_o(pre_seq),.m_payload_o(pre_last),.m_visible_o(pre_visible),
          .m_numeric_overflow_o(pre_numeric_overflow),.pe_req_valid_o(pre_pe_valid),
          .pe_req_ready_i(pre_pe_ready),.pe_lhs_o(pre_pe_lhs),.pe_rhs_o(pre_pe_rhs),.pe_acc_o(pre_pe_acc),
          .pe_rsp_valid_i(pre_pe_rsp_valid),.pe_rsp_ready_o(pre_pe_rsp_ready),.pe_result_i(pe_p_result));
      end else begin:g_local_prepass
        gaussian_depth_prepass_core #(.GID_W(GID_W),.SEQ_W(SEQ_W),.PAYLOAD_W(1),
          .COORD_W(COORD_W),.ROT_W(ROT_W))u_prepass(
          .clk_i(clk_i),.rst_ni(rst_ni),.frame_start_i(accepted_start),
          .s_valid_i(source_valid_i&&state_q==FRAME_COLLECT&&!input_closed_q),.s_ready_o(pre_s_ready),
          .s_gid_i(source_gid_i),.s_payload_i(source_last_i),
          .s_world_x_q16_i(source_world_x_q16_i),.s_world_y_q16_i(source_world_y_q16_i),
          .s_world_z_q16_i(source_world_z_q16_i),.cfg_r20_q20_i(cfg_r20_q20_i),
          .cfg_r21_q20_i(cfg_r21_q20_i),.cfg_r22_q20_i(cfg_r22_q20_i),.cfg_tz_q16_i(cfg_tz_q16_i),
          .cfg_near_q16_i(cfg_near_q16_i),.cfg_far_q16_i(cfg_far_q16_i),
          .m_valid_o(pre_valid),.m_ready_i(pre_ready),.m_depth_q16_o(pre_depth),.m_gid_o(pre_gid),
          .m_seq_o(pre_seq),.m_payload_o(pre_last),.m_visible_o(pre_visible),
          .m_numeric_overflow_o(pre_numeric_overflow));
        assign pre_pe_valid=0;assign pre_pe_lhs='0;assign pre_pe_rhs='0;assign pre_pe_acc='0;
        assign pre_pe_rsp_ready=1'b1;
      end
    endgenerate

    depth_group_buffer #(.GROUPS(GROUPS),.CAPACITY(GROUP_CAPACITY),.DEPTH_W(COORD_W),
      .GID_W(GID_W),.SEQ_W(SEQ_W),.PAYLOAD_W(1))u_group(
      .clk_i(clk_i),.rst_ni(rst_ni),.clear_overflow_i(clear_frame_errors),
      .s_valid_i(group_s_valid),.s_ready_o(group_s_ready),.s_depth_i(pre_depth),.s_gid_i(pre_gid),
      .s_seq_i(pre_seq),.s_payload_i(1'b0),.frame_end_i(group_frame_end),
      .frame_abort_i(source_end_valid_i&&source_end_ready_o),
      .cfg_pivot0_i(cfg_depth_pivot0_q16_i),.cfg_pivot1_i(cfg_depth_pivot1_q16_i),
      .cfg_pivot2_i(cfg_depth_pivot2_q16_i),.m_valid_o(group_valid),.m_ready_i(group_ready),
      .m_depth_o(group_depth),.m_gid_o(group_gid),.m_seq_o(group_seq),.m_payload_o(),
      .m_group_o(group_id),.m_group_first_o(group_first),.m_group_last_o(group_last),
      .frame_done_pulse_o(group_frame_done),.overflow_o(group_overflow),.busy_o(group_busy));

    gaussian_resource_mode_table #(.GROUP_LANES(LANES),.PROJECTION_LANES(LANES),
      .SH_LANES(LANES),.RASTER_LANES(LANES))u_group_resource_mode(
      .active_mode_i(active_mode_o),.group_active_lanes_o(group_active_lanes),
      .projection_active_lanes_o(),.sh_active_lanes_o(),.raster_active_lanes_o(),
      .group_weight_o(group_weight),.projection_weight_o(projection_weight),.raster_weight_o(raster_weight),
      .shared_math_owner_o(shared_math_owner),.aggressive_clock_gate_o(aggressive_clock_gate));

    shared_reconfigurable_pe_slice #(.DATA_W(PE_DATA_W),.GID_W(GID_W),.SEQ_W(SEQ_W),
      .RESULT_W(PE_RESULT_W))u_shared_pe(
      .clk_i(clk_i),.rst_ni(rst_ni),.group_weight_i(group_weight),
      .projection_weight_i(projection_weight),.raster_weight_i(raster_weight),
      .shared_owner_i(shared_math_owner),.aggressive_clock_gate_i(aggressive_clock_gate),
      .reconfigure_i(mode_commit_pulse_o),
      .g_valid_i(USE_SHARED_PE&&pe_g_req_valid),.g_ready_o(pe_g_req_ready),.g_op_mac_i(1'b0),
      .g_lhs_i(pe_g_lhs),.g_rhs_i(pe_g_rhs),.g_acc_i({PE_RESULT_W{1'b0}}),.g_lhs_gid_i(pe_g_lhs_gid),
      .g_rhs_gid_i(pe_g_rhs_gid),.g_lhs_seq_i(pe_g_lhs_seq),.g_rhs_seq_i(pe_g_rhs_seq),
      .g_rsp_valid_o(pe_g_rsp_valid),.g_rsp_ready_i(pe_g_rsp_ready),.g_result_o(pe_g_result),.g_less_o(pe_g_less),
      .p_valid_i(USE_SHARED_PE&&pe_p_req_valid),.p_ready_o(pe_p_req_ready),.p_op_mac_i(1'b1),
      .p_lhs_i(pe_p_lhs),.p_rhs_i(pe_p_rhs),.p_acc_i(pe_p_acc),
      .p_lhs_gid_i({GID_W{1'b0}}),.p_rhs_gid_i({GID_W{1'b0}}),
      .p_lhs_seq_i({SEQ_W{1'b0}}),.p_rhs_seq_i({SEQ_W{1'b0}}),.p_rsp_valid_o(pe_p_rsp_valid),
      .p_rsp_ready_i(pe_p_rsp_ready),.p_result_o(pe_p_result),.p_less_o(),
      .r_valid_i(USE_SHARED_PE&&USE_SHARED_RASTER_PE&&pe_r_req_valid),.r_ready_o(pe_r_req_ready),.r_op_mac_i(1'b1),
      .r_lhs_i(pe_r_lhs),.r_rhs_i(pe_r_rhs),.r_acc_i({PE_RESULT_W{1'b0}}),
      .r_lhs_gid_i({GID_W{1'b0}}),.r_rhs_gid_i({GID_W{1'b0}}),
      .r_lhs_seq_i({SEQ_W{1'b0}}),.r_rhs_seq_i({SEQ_W{1'b0}}),
      .r_rsp_valid_o(pe_r_rsp_valid),.r_rsp_ready_i(pe_r_rsp_ready),.r_result_o(pe_r_result),.r_less_o(),
      .group_grant_pulse_o(shared_pe_group_grant_o),
      .projection_grant_pulse_o(shared_pe_projection_grant_o),
      .raster_grant_pulse_o(shared_pe_raster_grant_o),
      .group_stall_o(shared_pe_group_stall_o),.projection_stall_o(shared_pe_projection_stall_o),
      .raster_stall_o(shared_pe_raster_stall_o),.utilization_pulse_o(shared_pe_utilization_o),
      .clock_enable_o(shared_pe_clock_enable_o),.busy_o(shared_pe_busy_o));

    group_sort_service_gate #(.PHYSICAL_LANES(LANES))u_group_sort_service(
      .clk_i(clk_i),.rst_ni(rst_ni),.cfg_active_lanes_i(group_active_lanes),
      .s_valid_i(group_valid),.s_ready_o(group_ready),
      .m_valid_o(group_sort_valid),.m_ready_i(group_sort_ready),
      .service_grant_o(group_service_grant),.service_stall_o(group_service_stall));

    generate
      if(USE_SHARED_PE)begin:g_shared_sort
        if(USE_BITONIC_SORT)begin:g_bitonic
          bitonic_group_sorter_shared #(.CAPACITY(SORT_CAPACITY),.DEPTH_W(COORD_W),.GID_W(GID_W),
            .SEQ_W(SEQ_W),.GROUP_W(GROUP_W),.PAYLOAD_W(1),.PE_DATA_W(PE_DATA_W),.COMPARE_LANES(LANES))u_sort(
            .clk_i(clk_i),.rst_ni(rst_ni),.clear_overflow_i(clear_frame_errors),.cfg_active_lanes_i(group_active_lanes),
            .s_valid_i(group_sort_valid),.s_ready_o(group_sort_ready),.s_empty_i(1'b0),
            .s_depth_i(group_depth),.s_gid_i(group_gid),.s_seq_i(group_seq),.s_group_i(group_id),
            .s_payload_i(1'b0),.s_group_last_i(group_last),
            .m_valid_o(sorted_valid),.m_ready_i(sorted_ready),.m_depth_o(sorted_depth),.m_gid_o(sorted_gid),
            .m_seq_o(sorted_seq),.m_group_o(sorted_group),.m_payload_o(),
            .m_group_first_o(sorted_first),.m_group_last_o(sorted_last),.overflow_o(sort_overflow),.busy_o(sort_busy),.subset_done_o(),
            .pe_req_valid_o(pe_g_req_valid),.pe_req_ready_i(pe_g_req_ready),.pe_lhs_o(pe_g_lhs),.pe_rhs_o(pe_g_rhs),
            .pe_lhs_gid_o(pe_g_lhs_gid),.pe_rhs_gid_o(pe_g_rhs_gid),.pe_lhs_seq_o(pe_g_lhs_seq),.pe_rhs_seq_o(pe_g_rhs_seq),
            .pe_rsp_valid_i(pe_g_rsp_valid),.pe_rsp_ready_o(pe_g_rsp_ready),.pe_less_i(pe_g_less),
            .perf_shared_compares_o(sort_work_totals_o[0+:32]),.perf_local_compares_o(sort_work_totals_o[32+:32]),
            .perf_swaps_o(sort_work_totals_o[64+:32]),.perf_phases_o(sort_work_totals_o[96+:32]),
            .perf_groups_o(sort_work_totals_o[128+:32]),.perf_stalls_o(sort_work_totals_o[224+:32]));
          assign sort_work_totals_o[160+:64]=0;assign sort_work_totals_o[256+:128]=0;
        end else if(USE_PARALLEL_GROUP_SORT)begin:g_parallel
          stable_group_sorter_parallel_shared #(.CAPACITY(SORT_CAPACITY),.DEPTH_W(COORD_W),.GID_W(GID_W),
            .SEQ_W(SEQ_W),.GROUP_W(GROUP_W),.PAYLOAD_W(1),.PE_DATA_W(PE_DATA_W),.COMPARE_LANES(LANES),
            .ENABLE_SERIAL_FALLBACK(PARALLEL_SORT_SERIAL_FALLBACK),.ENABLE_BATCH_FORWARDING(PARALLEL_SORT_BATCH_FORWARDING),
            .ENABLE_PHASE_FORWARDING(PARALLEL_SORT_PHASE_FORWARDING),
            .ENABLE_MONOTONIC_FASTPATH(PARALLEL_SORT_MONOTONIC_FASTPATH),
            .ENABLE_STABLE_RUN_FASTPATH(PARALLEL_SORT_STABLE_RUN_FASTPATH))u_sort(
            .clk_i(clk_i),.rst_ni(rst_ni),.clear_overflow_i(clear_frame_errors),.cfg_active_lanes_i(group_active_lanes),
            .s_valid_i(group_sort_valid),.s_ready_o(group_sort_ready),.s_depth_i(group_depth),.s_gid_i(group_gid),
            .s_seq_i(group_seq),.s_group_i(group_id),.s_payload_i(1'b0),.s_group_last_i(group_last),
            .m_valid_o(sorted_valid),.m_ready_i(sorted_ready),.m_depth_o(sorted_depth),.m_gid_o(sorted_gid),
            .m_seq_o(sorted_seq),.m_group_o(sorted_group),.m_payload_o(),
            .m_group_first_o(sorted_first),.m_group_last_o(sorted_last),.overflow_o(sort_overflow),.busy_o(sort_busy),
            .pe_req_valid_o(pe_g_req_valid),.pe_req_ready_i(pe_g_req_ready),.pe_lhs_o(pe_g_lhs),.pe_rhs_o(pe_g_rhs),
            .pe_lhs_gid_o(pe_g_lhs_gid),.pe_rhs_gid_o(pe_g_rhs_gid),.pe_lhs_seq_o(pe_g_lhs_seq),.pe_rhs_seq_o(pe_g_rhs_seq),
            .pe_rsp_valid_i(pe_g_rsp_valid),.pe_rsp_ready_o(pe_g_rsp_ready),.pe_less_i(pe_g_less),
            .perf_shared_compares_o(sort_work_totals_o[0+:32]),.perf_local_compares_o(sort_work_totals_o[32+:32]),
            .perf_swaps_o(sort_work_totals_o[64+:32]),.perf_phases_o(sort_work_totals_o[96+:32]),
            .perf_groups_o(sort_work_totals_o[128+:32]),.perf_fallback_groups_o(sort_work_totals_o[160+:32]),
            .perf_phase_grants_o(sort_work_totals_o[192+:32]),.perf_phase_stalls_o(sort_work_totals_o[224+:32]),
            .perf_shifts_o(sort_work_totals_o[256+:32]),.perf_collect_compares_o(sort_work_totals_o[288+:32]),
            .perf_fast_groups_o(sort_work_totals_o[320+:32]),.perf_reverse_groups_o(sort_work_totals_o[352+:32]));
        end else begin:g_serial
        assign sort_work_totals_o='0;
        stable_group_sorter_shared_compare #(.CAPACITY(SORT_CAPACITY),.DEPTH_W(COORD_W),.GID_W(GID_W),
          .SEQ_W(SEQ_W),.GROUP_W(GROUP_W),.PAYLOAD_W(1),.PE_DATA_W(PE_DATA_W),
          .ENABLE_BINARY_SEARCH(SHARED_SORT_BINARY_SEARCH))u_sort(
          .clk_i(clk_i),.rst_ni(rst_ni),.clear_overflow_i(clear_frame_errors),
          .s_valid_i(group_sort_valid),.s_ready_o(group_sort_ready),.s_depth_i(group_depth),.s_gid_i(group_gid),
          .s_seq_i(group_seq),.s_group_i(group_id),.s_payload_i(1'b0),.s_group_last_i(group_last),
          .m_valid_o(sorted_valid),.m_ready_i(sorted_ready),.m_depth_o(sorted_depth),.m_gid_o(sorted_gid),
          .m_seq_o(sorted_seq),.m_group_o(sorted_group),.m_payload_o(),
          .m_group_first_o(sorted_first),.m_group_last_o(sorted_last),
          .overflow_o(sort_overflow),.busy_o(sort_busy),.pe_req_valid_o(pe_g_req_valid),
          .pe_req_ready_i(pe_g_req_ready),.pe_lhs_o(pe_g_lhs),.pe_rhs_o(pe_g_rhs),
          .pe_lhs_gid_o(pe_g_lhs_gid),.pe_rhs_gid_o(pe_g_rhs_gid),
          .pe_lhs_seq_o(pe_g_lhs_seq),.pe_rhs_seq_o(pe_g_rhs_seq),
          .pe_rsp_valid_i(pe_g_rsp_valid),.pe_rsp_ready_o(pe_g_rsp_ready),.pe_less_i(pe_g_less));
        end
      end else begin:g_local_sort
        assign sort_work_totals_o='0;
        stable_group_sorter #(.CAPACITY(SORT_CAPACITY),.DEPTH_W(COORD_W),.GID_W(GID_W),
          .SEQ_W(SEQ_W),.GROUP_W(GROUP_W),.PAYLOAD_W(1))u_sort(
          .clk_i(clk_i),.rst_ni(rst_ni),.clear_overflow_i(clear_frame_errors),
          .s_valid_i(group_sort_valid),.s_ready_o(group_sort_ready),.s_depth_i(group_depth),.s_gid_i(group_gid),
          .s_seq_i(group_seq),.s_group_i(group_id),.s_payload_i(1'b0),.s_group_last_i(group_last),
          .m_valid_o(sorted_valid),.m_ready_i(sorted_ready),.m_depth_o(sorted_depth),.m_gid_o(sorted_gid),
          .m_seq_o(sorted_seq),.m_group_o(sorted_group),.m_payload_o(),
          .m_group_first_o(sorted_first),.m_group_last_o(sorted_last),
          .overflow_o(sort_overflow),.busy_o(sort_busy));
        assign pe_g_req_valid=0;assign pe_g_lhs='0;assign pe_g_rhs='0;
        assign pe_g_lhs_gid='0;assign pe_g_rhs_gid='0;assign pe_g_lhs_seq='0;assign pe_g_rhs_seq='0;
        assign pe_g_rsp_ready=1'b1;
      end
    endgenerate

    gaussian_sorted_render_pipeline #(.ATTR_DEPTH(ATTR_DEPTH),.LANES(LANES),.GID_W(GID_W),
      .USE_SHARED_PROJECTION_PE(USE_SHARED_PE&&USE_SHARED_PROJECTION_PE),
      .USE_SHARED_RASTER_PE(USE_SHARED_PE&&USE_SHARED_RASTER_PE),
      .ENABLE_ALPHA_ZERO_SKIP(ENABLE_ALPHA_ZERO_SKIP),
      .PE_DATA_W(PE_DATA_W),.PE_RESULT_W(PE_RESULT_W),
      .SEQ_W(SEQ_W),.EPOCH_W(EPOCH_W),.DEPTH_W(COORD_W),.GROUP_W(GROUP_W),
      .USE_EXTERNAL_ATTR_BACKEND(USE_EXTERNAL_ATTR_BACKEND),.USE_STATE_CACHE_BACKEND(USE_STATE_CACHE_BACKEND),
      .COORD_W(COORD_W),.QUAT_W(QUAT_W),.SCALE_W(SCALE_W),.ROT_W(ROT_W),
      .COV2_W(COV2_W),.PIXEL_COORD_W(PIXEL_COORD_W),.STATE_ENTRIES(STATE_ENTRIES),
      .STATE_WINDOW_ENTRIES(STATE_WINDOW_ENTRIES),.STATE_MSHR_COUNT(STATE_MSHR_COUNT),
      .ENABLE_RESPONSE_BLEND_BYPASS(ENABLE_RESPONSE_BLEND_BYPASS),
      .ENABLE_BLEND_COMMIT_BYPASS(ENABLE_BLEND_COMMIT_BYPASS),
      .ENABLE_OPERAND_ISOLATION(ENABLE_OPERAND_ISOLATION),
      .ENABLE_SHAPE_BLOCK_REJECT(ENABLE_SHAPE_BLOCK_REJECT),
      .COEFF_W(COEFF_W),.COEFFS(COEFFS))u_render(
      .clk_i(clk_i),.rst_ni(rst_ni),.attr_clear_valid_i(attr_clear_valid_i),
      .attr_clear_errors_i(clear_frame_errors),.attr_write_en_i(attr_write_en_i),.attr_write_gid_i(attr_write_gid_i),
      .attr_req_valid_o(attr_req_valid_o),.attr_req_ready_i(attr_req_ready_i),.attr_req_gid_o(attr_req_gid_o),
      .attr_rsp_valid_i(attr_rsp_valid_i),.attr_rsp_ready_o(attr_rsp_ready_o),
      .attr_rsp_error_i(attr_rsp_error_i),.attr_rsp_data_i(attr_rsp_data_i),
      .attr_write_world_x_q16_i(attr_write_world_x_q16_i),.attr_write_world_y_q16_i(attr_write_world_y_q16_i),
      .attr_write_world_z_q16_i(attr_write_world_z_q16_i),.attr_write_qw_q20_i(attr_write_qw_q20_i),
      .attr_write_qx_q20_i(attr_write_qx_q20_i),.attr_write_qy_q20_i(attr_write_qy_q20_i),
      .attr_write_qz_q20_i(attr_write_qz_q20_i),.attr_write_scale_x_q20_i(attr_write_scale_x_q20_i),
      .attr_write_scale_y_q20_i(attr_write_scale_y_q20_i),.attr_write_scale_z_q20_i(attr_write_scale_z_q20_i),
      .attr_write_opacity_q12_i(attr_write_opacity_q12_i),.attr_write_coeff_q12_flat_i(attr_write_coeff_q12_flat_i),
      .sorted_valid_i(sorted_valid),.sorted_ready_o(sorted_ready),.sorted_depth_i(sorted_depth),
      .sorted_gid_i(sorted_gid),.sorted_seq_i(sorted_seq),.sorted_group_i(sorted_group),
      .sorted_group_first_i(sorted_first),.sorted_group_last_i(sorted_last),
      .shadow_mode_we_i(mode_request),.shadow_mode_i(mode_shadow),.mode_commit_i(mode_request),
      .epoch_boundary_i(1'b1),.active_mode_o(active_mode_o),.epoch_id_o(epoch_id_o),
      .mode_pending_o(render_mode_pending),.mode_commit_pulse_o(mode_commit_pulse_o),.mode_overrun_o(render_mode_overrun),
      .cfg_r00_q20_i(cfg_r00_q20_i),.cfg_r01_q20_i(cfg_r01_q20_i),.cfg_r02_q20_i(cfg_r02_q20_i),
      .cfg_r10_q20_i(cfg_r10_q20_i),.cfg_r11_q20_i(cfg_r11_q20_i),.cfg_r12_q20_i(cfg_r12_q20_i),
      .cfg_r20_q20_i(cfg_r20_q20_i),.cfg_r21_q20_i(cfg_r21_q20_i),.cfg_r22_q20_i(cfg_r22_q20_i),
      .cfg_tx_q16_i(cfg_tx_q16_i),.cfg_ty_q16_i(cfg_ty_q16_i),.cfg_tz_q16_i(cfg_tz_q16_i),
      .cfg_camera_x_q16_i(cfg_camera_x_q16_i),.cfg_camera_y_q16_i(cfg_camera_y_q16_i),
      .cfg_camera_z_q16_i(cfg_camera_z_q16_i),.cfg_fx_q16_i(cfg_fx_q16_i),.cfg_fy_q16_i(cfg_fy_q16_i),
      .cfg_cx_q16_i(cfg_cx_q16_i),.cfg_cy_q16_i(cfg_cy_q16_i),.cfg_near_q16_i(cfg_near_q16_i),
      .cfg_far_q16_i(cfg_far_q16_i),.cfg_regularizer_q8_i(cfg_regularizer_q8_i),
      .cfg_image_width_i(cfg_image_width_i),.cfg_image_height_i(cfg_image_height_i),
      .commit_valid_o(commit_valid_o),.commit_ready_i(commit_ready_i),.commit_task_id_o(commit_task_id_o),
      .commit_block_id_o(commit_block_id_o),.commit_gid_o(commit_gid_o),.commit_epoch_id_o(commit_epoch_id_o),
      .commit_alpha_q12_o(commit_alpha_q12_o),.commit_pass_alpha_o(commit_pass_alpha_o),
      .commit_pixel_id_o(commit_pixel_id_o),.commit_r_q12_o(commit_r_q12_o),.commit_g_q12_o(commit_g_q12_o),
      .commit_b_q12_o(commit_b_q12_o),.commit_t_q16_o(commit_t_q16_o),
      .commit_newly_terminated_o(commit_newly_terminated_o),.block_terminated_pulse_o(block_terminated),
      .skipped_terminated_pulse_o(skipped_terminated),.empty_or_culled_pulse_o(empty_or_culled),
      .shape_rejected_pulse_o(event_shape_block_reject_o),
      .all_idle_o(render_idle),.retire_wait_o(render_retire_wait),.protocol_error_o(render_protocol_error),
       .stage_projection_busy_o(render_projection_busy),.stage_raster_busy_o(event_raster_busy_o),
      .block_candidate_pulse_o(event_block_candidate_o),
      .projection_active_mask_o(projection_active_mask_o),.sh_active_mask_o(sh_active_mask_o),
      .raster_active_mask_o(raster_active_mask_o),.attribute_read_pulse_o(attribute_read_pulse_o),
      .attribute_invalid_sticky_o(attr_invalid),.attribute_unloaded_sticky_o(attr_unloaded),
      .attribute_write_invalid_sticky_o(attr_write_invalid),
      .state_miss_req_valid_o(state_miss_req_valid_o),.state_miss_req_ready_i(state_miss_req_ready_i),
      .state_miss_req_tag_o(state_miss_req_tag_o),.state_miss_req_pixel_id_o(state_miss_req_pixel_id_o),.state_miss_rsp_valid_i(state_miss_rsp_valid_i),
      .state_miss_rsp_tag_i(state_miss_rsp_tag_i),
      .state_miss_rsp_ready_o(state_miss_rsp_ready_o),.state_miss_rsp_error_i(state_miss_rsp_error_i),
      .state_miss_rsp_data_i(state_miss_rsp_data_i),.state_cache_error_o(state_cache_error_o),
      .state_cache_idle_o(state_cache_idle_o),
      .pe_req_valid_o(render_pe_valid),.pe_req_ready_i(render_pe_ready),.pe_lhs_o(render_pe_lhs),.pe_rhs_o(render_pe_rhs),
      .pe_acc_o(render_pe_acc),.pe_rsp_valid_i(render_pe_rsp_valid),.pe_rsp_ready_o(render_pe_rsp_ready),.pe_result_i(pe_p_result),
      .r_pe_req_valid_o(pe_r_req_valid),.r_pe_req_ready_i(pe_r_req_ready),
      .r_pe_lhs_o(pe_r_lhs),.r_pe_rhs_o(pe_r_rhs),
      .r_pe_rsp_valid_i(pe_r_rsp_valid),.r_pe_rsp_ready_o(pe_r_rsp_ready),.r_pe_result_i(pe_r_result));

    assign event_group_pressure_o=group_service_stall||(group_s_valid&&!group_s_ready)||shared_pe_group_stall_o;
    assign event_sort_busy_o=sort_busy;
    assign event_projection_busy_o=render_projection_busy||shared_pe_projection_stall_o;
    assign event_terminated_skip_o=skipped_terminated;

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)pre_inflight_q<='0;
      else if(accepted_start)pre_inflight_q<='0;
      else case({source_valid_i&&source_ready_o,pre_valid&&pre_ready})
        2'b10:pre_inflight_q<=pre_inflight_q+1'b1;
        2'b01:pre_inflight_q<=pre_inflight_q-1'b1;
        default:begin end
      endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if(!rst_ni)begin
        state_q<=FRAME_IDLE;input_closed_q<=1'b0;group_done_seen_q<=1'b0;
        init_mode_pulse_q<=1'b0;init_mode_q<=2'b0;deferred_mode_q<=2'b0;deferred_mode_valid_q<=1'b0;
        frame_done_pulse_o<=1'b0;error_q<='0;
      end else begin
        frame_done_pulse_o<=1'b0;
        init_mode_pulse_q<=1'b0;
        if(runtime_mode_valid_i)begin deferred_mode_q<=runtime_mode_i;deferred_mode_valid_q<=1'b1;end
        if(accepted_start)begin
          input_closed_q<=1'b0;group_done_seen_q<=1'b0;
          if(!frame_continue_i)error_q<='0;
          if(frame_capacity_error)begin
            state_q<=FRAME_IDLE;frame_done_pulse_o<=1'b1;error_q[9]<=1'b1;
          end else if(frame_continue_i)begin
            state_q<=FRAME_COLLECT;
          end else begin
            state_q<=FRAME_PREP;
            init_mode_q<=runtime_mode_valid_i?runtime_mode_i:(deferred_mode_valid_q?deferred_mode_q:frame_mode_i);
            init_mode_pulse_q<=1'b1;deferred_mode_valid_q<=1'b0;
          end
        end else begin
          if(frame_start_i&&!frame_ready_o)error_q[8]<=1'b1;
          if(pre_valid&&pre_ready&&pre_numeric_overflow)error_q[0]<=1'b1;
          if(group_overflow)error_q[1]<=1'b1;
          if(sort_overflow)error_q[2]<=1'b1;
          if(attr_invalid)error_q[3]<=1'b1;
          if(attr_unloaded)error_q[4]<=1'b1;
          if(attr_write_invalid)error_q[5]<=1'b1;
          if(render_protocol_error)error_q[6]<=1'b1;
          if(render_mode_overrun)error_q[7]<=1'b1;
        end
        case(state_q)
          FRAME_IDLE:begin end
          FRAME_PREP:if(mode_commit_pulse_o)state_q<=FRAME_COLLECT;
          FRAME_COLLECT:begin
            if(source_valid_i&&source_ready_o&&source_last_i)input_closed_q<=1'b1;
            if(source_end_valid_i&&source_end_ready_o)input_closed_q<=1'b1;
            if(group_frame_end||(source_end_valid_i&&source_end_ready_o))state_q<=FRAME_DRAIN;
          end
          FRAME_DRAIN:begin
            if(group_frame_done)group_done_seen_q<=1'b1;
            if((group_done_seen_q||group_frame_done)&&!group_busy&&!sort_busy&&render_idle&&!render_mode_pending)begin
              state_q<=FRAME_IDLE;frame_done_pulse_o<=1'b1;
            end
          end
          default:state_q<=FRAME_IDLE;
        endcase
      end
    end

`ifndef SYNTHESIS
    assert property(@(posedge clk_i)disable iff(!rst_ni)source_valid_i&&source_ready_o&&source_last_i|=>!source_ready_o);
    assert property(@(posedge clk_i)disable iff(!rst_ni)frame_done_pulse_o|->render_idle&&!sort_busy&&!group_busy&&!shared_pe_busy_o);
    assert property(@(posedge clk_i)disable iff(!rst_ni)mode_commit_pulse_o|->!shared_pe_busy_o);
    assert property(@(posedge clk_i)disable iff(!rst_ni)pre_pe_valid|->select_pre_pe);
    assert property(@(posedge clk_i)disable iff(!rst_ni)state_q==FRAME_DRAIN|->pre_inflight_q==0);
    assert property(@(posedge clk_i)disable iff(!rst_ni)render_pe_valid|->!select_pre_pe);
    assert property(@(posedge clk_i)disable iff(!rst_ni)state_q==FRAME_COLLECT|->epoch_id_o!=0);
    assert property(@(posedge clk_i)disable iff(!rst_ni)accepted_start&&frame_continue_i|->epoch_id_o!=0);
`endif
endmodule
