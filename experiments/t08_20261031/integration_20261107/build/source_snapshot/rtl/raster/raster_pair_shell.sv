// One paired raster lane with early-termination filtering and the block-float
// Cholesky alpha core. Every live task reaches the commit interface with its
// tags, quantized alpha, and pass/prune decision intact under backpressure.
module raster_pair_shell #(
    parameter int unsigned LANES           = 4,
    parameter int unsigned TASK_W        = 32,
    parameter int unsigned BLOCK_W       = 24,
    parameter int unsigned GID_W         = 32,
    parameter int unsigned EPOCH_W       = 16,
    parameter int unsigned PIXEL_W       = 12,
    parameter int unsigned STATE_ENTRIES = 4096,
    parameter int unsigned STATE_WINDOW_ENTRIES = 2,
    parameter int unsigned STATE_MSHR_COUNT = 2,
    parameter bit ENABLE_RESPONSE_BLEND_BYPASS = 1'b0,
    parameter bit ENABLE_BLEND_COMMIT_BYPASS = 1'b0,
    parameter bit ENABLE_OPERAND_ISOLATION = 1'b0,
    parameter bit USE_STATE_CACHE_BACKEND = 1'b0,
    parameter bit USE_SHARED_RASTER_PE = 1'b0,
    parameter bit ENABLE_PIXEL_TERMINATION_SKIP=1'b0,
    parameter bit ENABLE_ALPHA_ZERO_SKIP = 1'b0
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [$clog2(LANES+1)-1:0] cfg_active_lanes_i,
    input  logic task_valid_i,
    output logic task_ready_o,
    input  logic [TASK_W-1:0]  task_id_i,
    input  logic [BLOCK_W-1:0] block_id_i,
    input  logic [GID_W-1:0]   gid_i,
    input  logic [EPOCH_W-1:0] epoch_id_i,
    input  logic [PIXEL_W-1:0] pixel_id_i,
    input  logic [5:0]         pixel_in_block_i,
    input  logic [12:0]        color_r_q12_i,
    input  logic [12:0]        color_g_q12_i,
    input  logic [12:0]        color_b_q12_i,
    input  logic signed [15:0] alpha_dx_q10_i,
    input  logic signed [15:0] alpha_dy_q10_i,
    input  logic [14:0]        alpha_l00_q12_i,
    input  logic signed [15:0] alpha_l10_q12_i,
    input  logic [14:0]        alpha_l11_q12_i,
    input  logic signed [5:0]  alpha_coordinate_shift_i,
    input  logic signed [5:0]  alpha_factor_shift_i,
    input  logic [12:0]        alpha_opacity_q12_i,
    output logic               block_terminated_pulse_o,
    output logic               skipped_terminated_pulse_o,
    output logic commit_valid_o,
    input  logic commit_ready_i,
    output logic [TASK_W-1:0]  commit_task_id_o,
    output logic [BLOCK_W-1:0] commit_block_id_o,
    output logic [GID_W-1:0]   commit_gid_o,
    output logic [EPOCH_W-1:0] commit_epoch_id_o,
    output logic [12:0]        commit_alpha_q12_o,
    output logic               commit_pass_alpha_o,
    output logic [PIXEL_W-1:0] commit_pixel_id_o,
    output logic [12:0]        commit_r_q12_o,
    output logic [12:0]        commit_g_q12_o,
    output logic [12:0]        commit_b_q12_o,
    output logic [15:0]        commit_t_q16_o,
    output logic               commit_newly_terminated_o,
    output logic [2:0]         result_occupancy_o,
    output logic [LANES-1:0]   active_mask_o,
    output logic               retire_wait_o,
    output logic               protocol_error_o,
    output logic               idle_o,
    output logic state_miss_req_valid_o,input logic state_miss_req_ready_i,
    output logic[1:0]state_miss_req_tag_o,output logic[PIXEL_W-1:0]state_miss_req_pixel_id_o,
    input logic state_miss_rsp_valid_i,output logic state_miss_rsp_ready_o,
    input logic[1:0]state_miss_rsp_tag_i,input logic state_miss_rsp_error_i,input logic[127:0]state_miss_rsp_data_i,
    output logic state_cache_error_o,output logic state_cache_idle_o,
    output logic r_pe_req_valid_o,input logic r_pe_req_ready_i,
    output logic signed[31:0]r_pe_lhs_o,r_pe_rhs_o,
    input logic r_pe_rsp_valid_i,output logic r_pe_rsp_ready_o,
    input logic signed[64:0]r_pe_result_i
);

    localparam int unsigned TAG_W = TASK_W + BLOCK_W + GID_W + EPOCH_W;
    localparam int unsigned META_W = TAG_W + PIXEL_W + 6 + 3*13;
    localparam int unsigned BLEND_META_W = META_W + 14;
    localparam int unsigned NUMERIC_W = 16+16+15+16+15+6+6+13;
    localparam int unsigned PAYLOAD_W = META_W + NUMERIC_W;
    logic [PAYLOAD_W-1:0] input_payload;
    logic [PAYLOAD_W-1:0] filtered_payload;
    logic filtered_valid;
    logic filtered_ready;
    logic [META_W-1:0] alpha_meta_i;
    logic signed [15:0] alpha_dx_q10;
    logic signed [15:0] alpha_dy_q10;
    logic [14:0] alpha_l00_q12;
    logic signed [15:0] alpha_l10_q12;
    logic [14:0] alpha_l11_q12;
    logic signed [5:0] alpha_coordinate_shift;
    logic signed [5:0] alpha_factor_shift;
    logic [12:0] alpha_opacity_q12;
    logic alpha_valid;
    logic alpha_ready;
    logic blend_in_valid,blend_in_ready,alpha_skip_candidate,alpha_skip_fire;
    logic [META_W-1:0] alpha_meta_o;
    logic [12:0] alpha_q12;
    logic alpha_pass;
    logic [PIXEL_W-1:0] blend_pixel_id;
    logic [5:0] blend_pixel_in_block;
    logic [12:0] blend_color_r, blend_color_g, blend_color_b;
    logic [EPOCH_W-1:0] blend_epoch;
    logic [GID_W-1:0] blend_gid_unused;
    logic [BLOCK_W-1:0] blend_block_unused;
    logic [TASK_W-1:0] blend_task_unused;
    logic [BLEND_META_W-1:0] blend_meta_commit;
    logic [META_W-1:0] commit_meta;
    logic [PIXEL_W-1:0] commit_pixel_meta_unused;
    logic [EPOCH_W-1:0] commit_epoch_meta_unused;
    logic [5:0] commit_pixel_in_block;
    logic [12:0] commit_color_r_unused, commit_color_g_unused, commit_color_b_unused;
    logic [63:0] new_terminated_mask;
    logic [BLOCK_W-1:0] block_terminated_id;
    logic [EPOCH_W-1:0] block_terminated_epoch;
    logic legacy_task_ready,legacy_live_valid,legacy_skip,legacy_block_terminated;
    logic [PAYLOAD_W-1:0] legacy_filtered_payload;
    logic [31:0] inflight_count_q;
    logic [31:0] alpha_sequence_q;logic [31:0]alpha_result_sequence;
    logic alpha_array_idle,alpha_retire_wait,alpha_protocol_error;
    logic task_accept,commit_complete,skip_complete;logic[1:0]state_query_tag,state_response_tag;
    logic[31:0]alpha_skipped_count_q;
    logic state_query_tag_2,state_response_tag_2;logic[1:0]occupancy_2;
    logic state_query_valid,state_query_ready,state_response_valid,state_response_ready,state_update_valid;
    logic[PIXEL_W-1:0]state_query_pixel,state_update_pixel;logic[EPOCH_W-1:0]state_query_epoch,state_update_epoch;
    logic[12:0]state_response_r,state_response_g,state_response_b,state_update_r,state_update_g,state_update_b;
    logic[15:0]state_response_t,state_update_t;

    assign input_payload = {
        epoch_id_i, gid_i, block_id_i, task_id_i,
        pixel_id_i, pixel_in_block_i, color_r_q12_i, color_g_q12_i, color_b_q12_i,
        alpha_dx_q10_i, alpha_dy_q10_i, alpha_l00_q12_i,
        alpha_l10_q12_i, alpha_l11_q12_i,
        alpha_coordinate_shift_i, alpha_factor_shift_i, alpha_opacity_q12_i
    };
    assign {
        alpha_meta_i, alpha_dx_q10, alpha_dy_q10, alpha_l00_q12,
        alpha_l10_q12, alpha_l11_q12, alpha_coordinate_shift,
        alpha_factor_shift, alpha_opacity_q12
    } = filtered_payload;
    assign {
        blend_epoch, blend_gid_unused, blend_block_unused, blend_task_unused,
        blend_pixel_id, blend_pixel_in_block,
        blend_color_r, blend_color_g, blend_color_b
    } = alpha_meta_o;
    assign {commit_meta, commit_alpha_q12_o, commit_pass_alpha_o} = blend_meta_commit;
    assign {
        commit_epoch_meta_unused, commit_gid_o, commit_block_id_o, commit_task_id_o,
        commit_pixel_meta_unused, commit_pixel_in_block, commit_color_r_unused,
        commit_color_g_unused, commit_color_b_unused
    } = commit_meta;
    assign new_terminated_mask = commit_valid_o && commit_ready_i
        && commit_newly_terminated_o ? (64'b1 << commit_pixel_in_block) : 64'b0;

    raster_termination_filter #(
        .PAYLOAD_W(PAYLOAD_W), .BLOCK_W(BLOCK_W), .EPOCH_W(EPOCH_W)
    ) u_termination_filter (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .task_valid_i(task_valid_i&&!ENABLE_PIXEL_TERMINATION_SKIP), .task_ready_o(legacy_task_ready),
        .task_payload_i(input_payload),
        .task_block_id_i(block_id_i), .task_epoch_id_i(epoch_id_i),
        .live_valid_o(legacy_live_valid), .live_ready_i(filtered_ready),
        .live_payload_o(legacy_filtered_payload),
        .term_update_valid_i(legacy_block_terminated),
        .term_update_block_id_i(block_terminated_id),
        .term_update_epoch_id_i(block_terminated_epoch),
        .skipped_pulse_o(legacy_skip)
    );

    // Blend commit supplies only newly terminated pixels. The mask store
    // monotonically accumulates them and emits one coarse-table update when
    // the 8x8 block first becomes fully terminated.
    pixel_termination_mask #(
        .BLOCK_W(BLOCK_W), .EPOCH_W(EPOCH_W), .PIXELS(64)
    ) u_pixel_termination_mask (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .query_valid_i(1'b0), .query_ready_o(),
        .query_block_id_i({BLOCK_W{1'b0}}),
        .query_epoch_id_i({EPOCH_W{1'b0}}),
        .response_valid_o(), .response_ready_i(1'b1),
        .response_mask_o(), .response_all_terminated_o(),
        .update_valid_i((|new_terminated_mask)&&!ENABLE_PIXEL_TERMINATION_SKIP),
        .update_block_id_i(commit_block_id_o),
        .update_epoch_id_i(commit_epoch_id_o),
        .update_new_terminated_i(new_terminated_mask),
        .block_terminated_pulse_o(legacy_block_terminated),
        .block_terminated_id_o(block_terminated_id),
        .block_terminated_epoch_o(block_terminated_epoch)
    );

    generate if(ENABLE_PIXEL_TERMINATION_SKIP)begin:g_pixel_termination
      raster_pixel_termination_filter #(
        .PAYLOAD_W(PAYLOAD_W),.BLOCK_W(BLOCK_W),.EPOCH_W(EPOCH_W)
      )u_filter(
        .clk_i(clk_i),.rst_ni(rst_ni),.task_valid_i(task_valid_i),.task_ready_o(task_ready_o),
        .task_payload_i(input_payload),.task_block_id_i(block_id_i),.task_epoch_id_i(epoch_id_i),
        .task_pixel_i(pixel_in_block_i),.live_valid_o(filtered_valid),.live_ready_i(filtered_ready),
        .live_payload_o(filtered_payload),.update_valid_i(|new_terminated_mask),
        .update_block_id_i(commit_block_id_o),.update_epoch_id_i(commit_epoch_id_o),
        .update_mask_i(new_terminated_mask),.skipped_pulse_o(skipped_terminated_pulse_o),
        .block_terminated_pulse_o(block_terminated_pulse_o));
    end else begin:g_legacy_termination
      assign task_ready_o=legacy_task_ready;
      assign filtered_valid=legacy_live_valid;
      assign filtered_payload=legacy_filtered_payload;
      assign skipped_terminated_pulse_o=legacy_skip;
      assign block_terminated_pulse_o=legacy_block_terminated;
    end endgenerate

    raster_alpha_lane_array #(.LANES(LANES),.META_W(META_W),.SEQ_W(32),
      .ENABLE_OPERAND_ISOLATION(ENABLE_OPERAND_ISOLATION)) u_alpha_array (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .cfg_active_lanes_i(cfg_active_lanes_i),
        .s_valid_i(filtered_valid), .s_ready_o(filtered_ready),
        .s_seq_i(alpha_sequence_q),.s_meta_i(alpha_meta_i), .s_dx_q10_i(alpha_dx_q10),
        .s_dy_q10_i(alpha_dy_q10), .s_l00_q12_i(alpha_l00_q12),
        .s_l10_q12_i(alpha_l10_q12), .s_l11_q12_i(alpha_l11_q12),
        .s_coordinate_shift_i(alpha_coordinate_shift),
        .s_factor_shift_i(alpha_factor_shift),
        .s_opacity_q12_i(alpha_opacity_q12),
        .m_valid_o(alpha_valid), .m_ready_i(alpha_ready),.m_seq_o(alpha_result_sequence),
        .m_meta_o(alpha_meta_o), .m_alpha_q12_o(alpha_q12),
        .m_pass_alpha_o(alpha_pass),.active_mask_o(active_mask_o),.all_idle_o(alpha_array_idle),
        .retire_wait_o(alpha_retire_wait),.protocol_error_o(alpha_protocol_error)
    );

    // An alpha below the architectural pass threshold is already replaced by
    // zero at the blend input. Reading and writing unchanged pixel state is
    // unnecessary; retire this no-op task at the ordered alpha boundary.
    assign alpha_skip_candidate=ENABLE_ALPHA_ZERO_SKIP&&alpha_valid&&!alpha_pass;
    assign alpha_ready=alpha_skip_candidate?1'b1:blend_in_ready;
    assign blend_in_valid=alpha_valid&&!alpha_skip_candidate;
    assign alpha_skip_fire=alpha_skip_candidate&&alpha_ready;

    generate if(STATE_WINDOW_ENTRIES==2)begin:g_blend_window_2
    blend_state_commit #(
        .META_W(BLEND_META_W), .PIXEL_W(PIXEL_W), .EPOCH_W(EPOCH_W),.STATE_ENTRIES(STATE_ENTRIES),
        .USE_EXTERNAL_STATE_BACKEND(USE_STATE_CACHE_BACKEND),
        .USE_SHARED_RASTER_PE(USE_SHARED_RASTER_PE)
    ) u_blend_state_commit (
        .clk_i(clk_i), .rst_ni(rst_ni),
        // Keep the small state window active in every G/P/R/E mode. A measured
        // single-entry E experiment regressed end-to-end cycles by >20%; an
        // independent epoch-safe depth control may be reconsidered only with
        // target-library power evidence.
        .enable_two_entries_i(1'b1),
        .s_valid_i(blend_in_valid), .s_ready_o(blend_in_ready),
        .s_meta_i({alpha_meta_o, alpha_q12, alpha_pass}), .s_pixel_id_i(blend_pixel_id),
        .s_epoch_id_i(blend_epoch), .s_color_r_q12_i(blend_color_r),
        .s_color_g_q12_i(blend_color_g), .s_color_b_q12_i(blend_color_b),
        .s_alpha_q12_i(alpha_pass ? alpha_q12 : 13'd0),
        .m_valid_o(commit_valid_o), .m_ready_i(commit_ready_i),
        .m_meta_o(blend_meta_commit), .m_pixel_id_o(commit_pixel_id_o),
        .m_epoch_id_o(commit_epoch_id_o), .m_r_q12_o(commit_r_q12_o),
        .m_g_q12_o(commit_g_q12_o), .m_b_q12_o(commit_b_q12_o),
        .m_t_q16_o(commit_t_q16_o),
        .m_newly_terminated_o(commit_newly_terminated_o),
        .occupancy_o(occupancy_2),
        .state_query_valid_o(state_query_valid),.state_query_ready_i(state_query_ready),
        .state_query_pixel_id_o(state_query_pixel),.state_query_epoch_id_o(state_query_epoch),
        .state_query_tag_o(state_query_tag_2),
        .state_response_valid_i(state_response_valid),.state_response_ready_o(state_response_ready),
        .state_response_tag_i(state_response_tag_2),
        .state_response_r_q12_i(state_response_r),.state_response_g_q12_i(state_response_g),
        .state_response_b_q12_i(state_response_b),.state_response_t_q16_i(state_response_t),
        .state_update_valid_o(state_update_valid),.state_update_pixel_id_o(state_update_pixel),
        .state_update_epoch_id_o(state_update_epoch),.state_update_r_q12_o(state_update_r),
        .state_update_g_q12_o(state_update_g),.state_update_b_q12_o(state_update_b),
        .state_update_t_q16_o(state_update_t),
        .r_pe_req_valid_o(r_pe_req_valid_o),.r_pe_req_ready_i(r_pe_req_ready_i),
        .r_pe_lhs_o(r_pe_lhs_o),.r_pe_rhs_o(r_pe_rhs_o),
        .r_pe_rsp_valid_i(r_pe_rsp_valid_i),.r_pe_rsp_ready_o(r_pe_rsp_ready_o),.r_pe_result_i(r_pe_result_i)
    );
    assign state_query_tag={1'b0,state_query_tag_2};
    assign state_response_tag_2=state_response_tag[0];
    assign result_occupancy_o={1'b0,occupancy_2};
    end else begin:g_blend_window_4
      blend_state_commit_4 #(.META_W(BLEND_META_W),.PIXEL_W(PIXEL_W),.EPOCH_W(EPOCH_W),
        .ENABLE_RESPONSE_BLEND_BYPASS(ENABLE_RESPONSE_BLEND_BYPASS),
        .ENABLE_BLEND_COMMIT_BYPASS(ENABLE_BLEND_COMMIT_BYPASS),
        .USE_SHARED_RASTER_PE(USE_SHARED_RASTER_PE))
      u_blend_state_commit(
        .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(blend_in_valid),.s_ready_o(blend_in_ready),
        .s_meta_i({alpha_meta_o,alpha_q12,alpha_pass}),.s_pixel_id_i(blend_pixel_id),
        .s_epoch_id_i(blend_epoch),.s_color_r_q12_i(blend_color_r),
        .s_color_g_q12_i(blend_color_g),.s_color_b_q12_i(blend_color_b),
        .s_alpha_q12_i(alpha_pass?alpha_q12:13'd0),.m_valid_o(commit_valid_o),
        .m_ready_i(commit_ready_i),.m_meta_o(blend_meta_commit),.m_pixel_id_o(commit_pixel_id_o),
        .m_epoch_id_o(commit_epoch_id_o),.m_r_q12_o(commit_r_q12_o),.m_g_q12_o(commit_g_q12_o),
        .m_b_q12_o(commit_b_q12_o),.m_t_q16_o(commit_t_q16_o),
        .m_newly_terminated_o(commit_newly_terminated_o),.occupancy_o(result_occupancy_o),
        .state_query_valid_o(state_query_valid),.state_query_ready_i(state_query_ready),
        .state_query_pixel_id_o(state_query_pixel),.state_query_epoch_id_o(state_query_epoch),
        .state_query_tag_o(state_query_tag),.state_response_valid_i(state_response_valid),
        .state_response_ready_o(state_response_ready),.state_response_tag_i(state_response_tag),
        .state_response_r_q12_i(state_response_r),.state_response_g_q12_i(state_response_g),
        .state_response_b_q12_i(state_response_b),.state_response_t_q16_i(state_response_t),
        .state_update_valid_o(state_update_valid),.state_update_pixel_id_o(state_update_pixel),
        .state_update_epoch_id_o(state_update_epoch),.state_update_r_q12_o(state_update_r),
        .state_update_g_q12_o(state_update_g),.state_update_b_q12_o(state_update_b),
        .state_update_t_q16_o(state_update_t),
        .r_pe_req_valid_o(r_pe_req_valid_o),.r_pe_req_ready_i(r_pe_req_ready_i),
        .r_pe_lhs_o(r_pe_lhs_o),.r_pe_rhs_o(r_pe_rhs_o),
        .r_pe_rsp_valid_i(r_pe_rsp_valid_i),.r_pe_rsp_ready_o(r_pe_rsp_ready_o),.r_pe_result_i(r_pe_result_i));
    end endgenerate
    generate if(USE_STATE_CACHE_BACKEND&&STATE_MSHR_COUNT==4)begin:g_state_cache_quad
      image_state_cache_backend_4 #(.PIXEL_W(PIXEL_W),.EPOCH_W(EPOCH_W),.ENTRIES(STATE_ENTRIES))u_state_cache(
        .clk_i(clk_i),.rst_ni(rst_ni),.query_valid_i(state_query_valid),.query_ready_o(state_query_ready),
        .query_pixel_id_i(state_query_pixel),.query_epoch_id_i(state_query_epoch),.query_tag_i(state_query_tag),
        .response_valid_o(state_response_valid),.response_ready_i(state_response_ready),.response_tag_o(state_response_tag),
        .response_r_q12_o(state_response_r),.response_g_q12_o(state_response_g),.response_b_q12_o(state_response_b),
        .response_t_q16_o(state_response_t),.update_valid_i(state_update_valid),.update_pixel_id_i(state_update_pixel),
        .update_epoch_id_i(state_update_epoch),.update_r_q12_i(state_update_r),.update_g_q12_i(state_update_g),
        .update_b_q12_i(state_update_b),.update_t_q16_i(state_update_t),
        .miss_req_valid_o(state_miss_req_valid_o),.miss_req_ready_i(state_miss_req_ready_i),
        .miss_req_tag_o(state_miss_req_tag_o),.miss_req_pixel_id_o(state_miss_req_pixel_id_o),
        .miss_rsp_valid_i(state_miss_rsp_valid_i),.miss_rsp_tag_i(state_miss_rsp_tag_i),
        .miss_rsp_ready_o(state_miss_rsp_ready_o),.miss_rsp_error_i(state_miss_rsp_error_i),
        .miss_rsp_data_i(state_miss_rsp_data_i),.error_sticky_o(state_cache_error_o),.idle_o(state_cache_idle_o));
    end else if(USE_STATE_CACHE_BACKEND&&STATE_MSHR_COUNT==2)begin:g_state_cache
      assign state_response_tag[1]=1'b0;
      assign state_miss_req_tag_o[1]=1'b0;
      image_state_cache_backend #(.PIXEL_W(PIXEL_W),.EPOCH_W(EPOCH_W),.ENTRIES(STATE_ENTRIES),
        .ACTIVE_MSHRS(2))u_state_cache(
        .clk_i(clk_i),.rst_ni(rst_ni),.query_valid_i(state_query_valid),.query_ready_o(state_query_ready),
        .query_pixel_id_i(state_query_pixel),.query_epoch_id_i(state_query_epoch),
        .query_tag_i(state_query_tag[0]),
        .response_valid_o(state_response_valid),.response_ready_i(state_response_ready),
        .response_tag_o(state_response_tag[0]),
        .response_r_q12_o(state_response_r),.response_g_q12_o(state_response_g),
        .response_b_q12_o(state_response_b),.response_t_q16_o(state_response_t),
        .update_valid_i(state_update_valid),.update_pixel_id_i(state_update_pixel),
        .update_epoch_id_i(state_update_epoch),.update_r_q12_i(state_update_r),
        .update_g_q12_i(state_update_g),.update_b_q12_i(state_update_b),.update_t_q16_i(state_update_t),
        .miss_req_valid_o(state_miss_req_valid_o),.miss_req_ready_i(state_miss_req_ready_i),
        .miss_req_tag_o(state_miss_req_tag_o[0]),.miss_req_pixel_id_o(state_miss_req_pixel_id_o),
        .miss_rsp_valid_i(state_miss_rsp_valid_i),.miss_rsp_tag_i(state_miss_rsp_tag_i[0]),
        .miss_rsp_ready_o(state_miss_rsp_ready_o),.miss_rsp_error_i(state_miss_rsp_error_i),
        .miss_rsp_data_i(state_miss_rsp_data_i),.error_sticky_o(state_cache_error_o),.idle_o(state_cache_idle_o));
    end else if(USE_STATE_CACHE_BACKEND)begin:g_state_cache_single
      assign state_response_tag[1]=1'b0;
      assign state_miss_req_tag_o[1]=1'b0;
      image_state_cache_backend_single #(.PIXEL_W(PIXEL_W),.EPOCH_W(EPOCH_W),.ENTRIES(STATE_ENTRIES))u_state_cache(
        .clk_i(clk_i),.rst_ni(rst_ni),.query_valid_i(state_query_valid),.query_ready_o(state_query_ready),
        .query_pixel_id_i(state_query_pixel),.query_epoch_id_i(state_query_epoch),.query_tag_i(state_query_tag[0]),
        .response_valid_o(state_response_valid),.response_ready_i(state_response_ready),.response_tag_o(state_response_tag[0]),
        .response_r_q12_o(state_response_r),.response_g_q12_o(state_response_g),.response_b_q12_o(state_response_b),
        .response_t_q16_o(state_response_t),.update_valid_i(state_update_valid),.update_pixel_id_i(state_update_pixel),
        .update_epoch_id_i(state_update_epoch),.update_r_q12_i(state_update_r),.update_g_q12_i(state_update_g),
        .update_b_q12_i(state_update_b),.update_t_q16_i(state_update_t),
        .miss_req_valid_o(state_miss_req_valid_o),.miss_req_ready_i(state_miss_req_ready_i),
        .miss_req_tag_o(state_miss_req_tag_o[0]),.miss_req_pixel_id_o(state_miss_req_pixel_id_o),
        .miss_rsp_valid_i(state_miss_rsp_valid_i),.miss_rsp_tag_i(state_miss_rsp_tag_i[0]),
        .miss_rsp_ready_o(state_miss_rsp_ready_o),.miss_rsp_error_i(state_miss_rsp_error_i),
        .miss_rsp_data_i(state_miss_rsp_data_i),.error_sticky_o(state_cache_error_o),.idle_o(state_cache_idle_o));
    end else begin:g_no_state_cache
      assign state_miss_req_valid_o=0;assign state_miss_req_tag_o=0;assign state_miss_req_pixel_id_o='0;assign state_miss_rsp_ready_o=0;
      assign state_cache_error_o=0;assign state_cache_idle_o=1;
    end endgenerate
`ifndef SYNTHESIS
    initial begin
      assert((STATE_WINDOW_ENTRIES==2&&(STATE_MSHR_COUNT==1||STATE_MSHR_COUNT==2))||
             (STATE_WINDOW_ENTRIES==4&&STATE_MSHR_COUNT==4));
      assert(STATE_WINDOW_ENTRIES==2||USE_STATE_CACHE_BACKEND);
    end
`endif
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)alpha_sequence_q<='0;
      else if(filtered_valid&&filtered_ready)alpha_sequence_q<=alpha_sequence_q+1'b1;
    end
    assign task_accept=task_valid_i&&task_ready_o;
    assign commit_complete=commit_valid_o&&commit_ready_i;
    assign skip_complete=skipped_terminated_pulse_o;
    generate if(ENABLE_ALPHA_ZERO_SKIP)begin:g_alpha_skip_accounting
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)alpha_skipped_count_q<='0;
      else if(alpha_skip_fire)alpha_skipped_count_q<=alpha_skipped_count_q+1'b1;
    end
    logic[2:0]completion_count;
    assign completion_count=3'(commit_complete)+3'(skip_complete)+3'(alpha_skip_fire);
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)inflight_count_q<='0;
      else case({task_accept,completion_count})
        4'b1000:inflight_count_q<=inflight_count_q+1'b1;
        4'b0001,4'b1010:inflight_count_q<=inflight_count_q-1'b1;
        4'b0010,4'b1011:inflight_count_q<=inflight_count_q-32'd2;
        4'b0011:inflight_count_q<=inflight_count_q-32'd3;
        default:inflight_count_q<=inflight_count_q;
      endcase
    end
    end else begin:g_original_accounting
    assign alpha_skipped_count_q='0;
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)inflight_count_q<='0;
      // Commit and termination-filter skip are independent completion ports.
      // Both may fire in one cycle, so an OR would leak one inflight credit.
      else case({task_accept,commit_complete,skip_complete})
        3'b100:inflight_count_q<=inflight_count_q+1'b1;
        3'b010,3'b001:inflight_count_q<=inflight_count_q-1'b1;
        3'b011:inflight_count_q<=inflight_count_q-2'd2;
        3'b111:inflight_count_q<=inflight_count_q-1'b1;
        default:inflight_count_q<=inflight_count_q;
      endcase
    end
    end endgenerate
    assign retire_wait_o=alpha_retire_wait;
    assign protocol_error_o=alpha_protocol_error;
    assign idle_o=inflight_count_q==0&&alpha_array_idle&&state_cache_idle_o;

`ifndef SYNTHESIS
    logic [63:0] accepted_q;
    logic [63:0] committed_q;
    logic [63:0] skipped_q;
    logic [63:0] alpha_skipped_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            accepted_q  <= '0;
            committed_q <= '0;
            skipped_q   <= '0;
            alpha_skipped_q <= '0;
        end else begin
            if (task_valid_i && task_ready_o) accepted_q <= accepted_q + 64'd1;
            if (commit_valid_o && commit_ready_i) committed_q <= committed_q + 64'd1;
            if (skipped_terminated_pulse_o) skipped_q <= skipped_q + 64'd1;
            if (alpha_skip_fire) alpha_skipped_q <= alpha_skipped_q + 64'd1;
        end
    end
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        committed_q + skipped_q + alpha_skipped_q <= accepted_q);
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        ({29'b0,commit_complete} + {29'b0,skip_complete} + {29'b0,alpha_skip_fire}) <= inflight_count_q + 32'(task_accept));
`endif

endmodule
