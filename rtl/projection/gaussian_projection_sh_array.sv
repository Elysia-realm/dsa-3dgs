// Complete ordered per-Gaussian projection + SH front end. A full sorted
// attribute record is forked atomically; projection may execute on 1/2/4 lanes
// and finish out of order, while its ordered-retire output joins the in-order
// SH color FIFO by {epoch,gid,sequence}. RGB is then held for all blocks of the
// current Gaussian. No Gaussian-tile bin or per-tile sort is present.
module gaussian_projection_sh_array #(
    parameter bit ENABLE_COMPRESSED_ATTRIBUTES=1'b0,
    parameter int unsigned LANES=4,parameter int unsigned SH_LANES=LANES,parameter int unsigned GID_W=32,
    parameter bit ENABLE_OPERAND_ISOLATION=1'b0,
    parameter bit USE_SHARED_PROJECTION_PE=1'b0,
    parameter bit SHARED_P_DOT3=1'b0,
    parameter int unsigned PE_DATA_W=32,parameter int unsigned PE_RESULT_W=2*PE_DATA_W+1,
    parameter int unsigned SEQ_W=16,parameter int unsigned EPOCH_W=16,
    parameter int unsigned COORD_W=27,parameter int unsigned QUAT_W=22,
    parameter int unsigned SCALE_W=24,parameter int unsigned ROT_W=22,
    parameter int unsigned COV2_W=35,parameter int unsigned SCREEN_W=27,
    parameter int unsigned PIXEL_W=16,parameter int unsigned TILE_W=12,
    parameter int unsigned COEFF_W=18,parameter int unsigned COEFFS=16,
    parameter int unsigned MODE_W=2,parameter int unsigned RETIRE_DEPTH=16,
    parameter int unsigned META_W=EPOCH_W+GID_W+SEQ_W,
    parameter int unsigned COEFF_FLAT_W=3*COEFFS*COEFF_W,
    parameter int unsigned PROJ_W=META_W+3*COORD_W+4*QUAT_W+3*SCALE_W+13+(ENABLE_COMPRESSED_ATTRIBUTES?249:0),
    parameter int unsigned SH_W=META_W+3*COORD_W+COEFF_FLAT_W,
    parameter int unsigned RAW_DESC_W=META_W+13+COORD_W+3*COV2_W+2*SCREEN_W+4*PIXEL_W+1,
    parameter int unsigned DESC_W=RAW_DESC_W+15+16+15+6+6+1,
    parameter int unsigned TASK_W=DESC_W+2*TILE_W,
    parameter int unsigned COLOR_W=3*13+2
) (

    input logic [248:0] s_attr_aux_i,
    input logic clk_i,input logic rst_ni,
    input logic shadow_mode_we_i,input logic[MODE_W-1:0]shadow_mode_i,
    input logic mode_commit_i,input logic epoch_boundary_i,input logic downstream_empty_i,
    output logic[MODE_W-1:0]active_mode_o,output logic[15:0]epoch_id_o,
    output logic mode_pending_o,mode_commit_pulse_o,mode_overrun_o,
    input logic s_valid_i,output logic s_ready_o,input logic[GID_W-1:0]s_gid_i,input logic[SEQ_W-1:0]s_seq_i,
    input logic signed[COORD_W-1:0]s_world_x_q16_i,s_world_y_q16_i,s_world_z_q16_i,
    input logic signed[QUAT_W-1:0]s_qw_q20_i,s_qx_q20_i,s_qy_q20_i,s_qz_q20_i,
    input logic[SCALE_W-1:0]s_scale_x_q20_i,s_scale_y_q20_i,s_scale_z_q20_i,
    input logic[12:0]s_opacity_q12_i,input logic[COEFF_FLAT_W-1:0]s_coeff_q12_flat_i,
    input logic signed[ROT_W-1:0]cfg_r00_q20_i,cfg_r01_q20_i,cfg_r02_q20_i,
    input logic signed[ROT_W-1:0]cfg_r10_q20_i,cfg_r11_q20_i,cfg_r12_q20_i,
    input logic signed[ROT_W-1:0]cfg_r20_q20_i,cfg_r21_q20_i,cfg_r22_q20_i,
    input logic signed[COORD_W-1:0]cfg_tx_q16_i,cfg_ty_q16_i,cfg_tz_q16_i,
    input logic signed[COORD_W-1:0]cfg_camera_x_q16_i,cfg_camera_y_q16_i,cfg_camera_z_q16_i,
    input logic signed[32:0]cfg_fx_q16_i,cfg_fy_q16_i,cfg_cx_q16_i,cfg_cy_q16_i,
    input logic signed[COORD_W-1:0]cfg_near_q16_i,cfg_far_q16_i,
    input logic[COV2_W-1:0]cfg_regularizer_q8_i,input logic[PIXEL_W-1:0]cfg_image_width_i,cfg_image_height_i,
    output logic m_valid_o,input logic m_ready_i,output logic[DESC_W-1:0]m_desc_o,
    output logic[TILE_W-1:0]m_block_x_o,m_block_y_o,output logic[12:0]m_r_q12_o,m_g_q12_o,m_b_q12_o,
    output logic m_first_o,m_last_o,m_culled_o,m_sh_fallback_o,m_numeric_overflow_o,
    output logic[LANES-1:0]projection_active_mask_o,output logic[SH_LANES-1:0]sh_active_mask_o,output logic all_idle_o,
    output logic retire_wait_o,output logic protocol_error_o,output logic stage_projection_busy_o,
    output logic pe_req_valid_o,input logic pe_req_ready_i,
    output logic signed[PE_DATA_W-1:0]pe_lhs_o,pe_rhs_o,
    output logic signed[PE_RESULT_W-1:0]pe_acc_o,
    input logic pe_rsp_valid_i,output logic pe_rsp_ready_o,
    input logic signed[PE_RESULT_W-1:0]pe_result_i
);
    localparam int unsigned COUNT_W=$clog2(LANES+1);localparam int unsigned SH_COUNT_W=$clog2(SH_LANES+1);
    localparam int unsigned SOURCE_COUNT_W=17;
    logic[248:0]projection_aux;
    logic[META_W-1:0]source_meta;logic[PROJ_W-1:0]fork_projection_in,fork_projection_out;
    logic[SH_W-1:0]fork_sh_in,fork_sh_out;logic fork_ready,fork_projection_valid,fork_projection_ready;
    logic fork_sh_valid,fork_sh_ready,fork_empty;logic[$clog2(4+1)-1:0]fork_occupancy;
    logic projection_valid,projection_ready,projection_first,projection_last,projection_culled;
    logic[DESC_W-1:0]projection_desc;logic[TILE_W-1:0]projection_x,projection_y;
    logic projection_idle,projection_protocol_error,projection_culled_pulse,projection_retire_wait;logic[COUNT_W-1:0]active_lanes;
    logic[META_W-1:0]projection_meta_in,sh_meta_in,sh_meta_out;logic signed[COORD_W-1:0]projection_wx,projection_wy,projection_wz;
    logic signed[QUAT_W-1:0]projection_qw,projection_qx,projection_qy,projection_qz;
    logic[SCALE_W-1:0]projection_sx,projection_sy,projection_sz;logic[12:0]projection_opacity;
    logic signed[COORD_W-1:0]sh_wx,sh_wy,sh_wz;logic[COEFF_FLAT_W-1:0]sh_coeff;
    logic sh_result_valid,sh_result_ready;logic[12:0]sh_r,sh_g,sh_b;logic sh_fallback,sh_overflow;
    logic[SH_COUNT_W-1:0]sh_active_lanes;logic sh_array_idle,sh_retire_wait,sh_protocol_error;
    logic[TASK_W-1:0]projection_task,joined_task;logic[COLOR_W-1:0]sh_color,joined_color;
    logic join_valid,join_first,join_last,join_culled,join_empty,join_mismatch;
    logic[$clog2(RETIRE_DEPTH+1)-1:0]sh_occupancy;logic[SOURCE_COUNT_W-1:0]source_count_q;
    logic source_accept,joined_retire,auxiliary_empty;

    assign source_meta={epoch_id_o,s_gid_i,s_seq_i};
    assign fork_projection_in=ENABLE_COMPRESSED_ATTRIBUTES?PROJ_W'({source_meta,s_world_x_q16_i,s_world_y_q16_i,s_world_z_q16_i,
      s_qw_q20_i,s_qx_q20_i,s_qy_q20_i,s_qz_q20_i,s_scale_x_q20_i,s_scale_y_q20_i,s_scale_z_q20_i,s_opacity_q12_i,s_attr_aux_i}):PROJ_W'({source_meta,s_world_x_q16_i,s_world_y_q16_i,s_world_z_q16_i,
      s_qw_q20_i,s_qx_q20_i,s_qy_q20_i,s_qz_q20_i,s_scale_x_q20_i,s_scale_y_q20_i,s_scale_z_q20_i,s_opacity_q12_i});
    assign fork_sh_in={source_meta,s_world_x_q16_i,s_world_y_q16_i,s_world_z_q16_i,s_coeff_q12_flat_i};
    // Stop new work as soon as a commit is requested so the affected state can drain.
    assign s_ready_o=fork_ready&&!mode_pending_o&&!mode_commit_i;assign source_accept=s_valid_i&&s_ready_o;
    gaussian_projection_sh_fork #(.PROJ_W(PROJ_W),.SH_W(SH_W),.DEPTH(4))u_fork(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i&&!mode_pending_o&&!mode_commit_i),.s_ready_o(fork_ready),
      .s_projection_data_i(fork_projection_in),.s_sh_data_i(fork_sh_in),
      .projection_valid_o(fork_projection_valid),.projection_ready_i(fork_projection_ready),.projection_data_o(fork_projection_out),
      .sh_valid_o(fork_sh_valid),.sh_ready_i(fork_sh_ready),.sh_data_o(fork_sh_out),.empty_o(fork_empty),.occupancy_o(fork_occupancy));
    assign {projection_meta_in,projection_wx,projection_wy,projection_wz,projection_qw,projection_qx,projection_qy,projection_qz,
      projection_sx,projection_sy,projection_sz,projection_opacity}=fork_projection_out>>(ENABLE_COMPRESSED_ATTRIBUTES?249:0);
    assign projection_aux=ENABLE_COMPRESSED_ATTRIBUTES?249'(fork_projection_out):249'd0;
    raw_gaussian_projection_array #(.ENABLE_COMPRESSED_ATTRIBUTES(ENABLE_COMPRESSED_ATTRIBUTES),.LANES(LANES),.META_W(META_W),.SEQ_W(SEQ_W),.RETIRE_DEPTH(RETIRE_DEPTH),
      .USE_SHARED_PROJECTION_PE(USE_SHARED_PROJECTION_PE),.SHARED_P_DOT3(SHARED_P_DOT3),.PE_DATA_W(PE_DATA_W),.PE_RESULT_W(PE_RESULT_W),
      .ENABLE_OPERAND_ISOLATION(ENABLE_OPERAND_ISOLATION))u_projection(
      .clk_i(clk_i),.rst_ni(rst_ni),.shadow_mode_we_i(shadow_mode_we_i),.shadow_mode_i(shadow_mode_i),
      .mode_commit_i(mode_commit_i),.epoch_boundary_i(epoch_boundary_i&&auxiliary_empty&&downstream_empty_i),
      .active_mode_o(active_mode_o),.active_lanes_o(active_lanes),.epoch_id_o(epoch_id_o),
      .mode_pending_o(mode_pending_o),.mode_commit_pulse_o(mode_commit_pulse_o),.mode_overrun_o(mode_overrun_o),
      .s_valid_i(fork_projection_valid),.s_ready_o(fork_projection_ready),.s_meta_i(projection_meta_in),
      .s_world_x_q16_i(projection_wx),.s_world_y_q16_i(projection_wy),.s_world_z_q16_i(projection_wz),
      .s_qw_q20_i(projection_qw),.s_qx_q20_i(projection_qx),.s_qy_q20_i(projection_qy),.s_qz_q20_i(projection_qz),
      .s_scale_x_q20_i(projection_sx),.s_scale_y_q20_i(projection_sy),.s_scale_z_q20_i(projection_sz),.s_attr_aux_i(projection_aux),.s_opacity_q12_i(projection_opacity),
      .cfg_r00_q20_i(cfg_r00_q20_i),.cfg_r01_q20_i(cfg_r01_q20_i),.cfg_r02_q20_i(cfg_r02_q20_i),
      .cfg_r10_q20_i(cfg_r10_q20_i),.cfg_r11_q20_i(cfg_r11_q20_i),.cfg_r12_q20_i(cfg_r12_q20_i),
      .cfg_r20_q20_i(cfg_r20_q20_i),.cfg_r21_q20_i(cfg_r21_q20_i),.cfg_r22_q20_i(cfg_r22_q20_i),
      .cfg_tx_q16_i(cfg_tx_q16_i),.cfg_ty_q16_i(cfg_ty_q16_i),.cfg_tz_q16_i(cfg_tz_q16_i),
      .cfg_fx_q16_i(cfg_fx_q16_i),.cfg_fy_q16_i(cfg_fy_q16_i),.cfg_cx_q16_i(cfg_cx_q16_i),.cfg_cy_q16_i(cfg_cy_q16_i),
      .cfg_near_q16_i(cfg_near_q16_i),.cfg_far_q16_i(cfg_far_q16_i),.cfg_regularizer_q8_i(cfg_regularizer_q8_i),
      .cfg_image_width_i(cfg_image_width_i),.cfg_image_height_i(cfg_image_height_i),
      .m_task_valid_o(projection_valid),.m_task_ready_i(projection_ready),.m_task_desc_o(projection_desc),
      .m_task_tile_x_o(projection_x),.m_task_tile_y_o(projection_y),.m_task_first_o(projection_first),
      .m_task_last_o(projection_last),.m_task_culled_o(projection_culled),.culled_pulse_o(projection_culled_pulse),
      .active_mask_o(projection_active_mask_o),.all_idle_o(projection_idle),.retire_wait_o(projection_retire_wait),
      .retire_protocol_error_o(projection_protocol_error),
      .pe_req_valid_o(pe_req_valid_o),.pe_req_ready_i(pe_req_ready_i),.pe_lhs_o(pe_lhs_o),.pe_rhs_o(pe_rhs_o),
      .pe_acc_o(pe_acc_o),.pe_rsp_valid_i(pe_rsp_valid_i),.pe_rsp_ready_o(pe_rsp_ready_o),.pe_result_i(pe_result_i));
    assign {sh_meta_in,sh_wx,sh_wy,sh_wz,sh_coeff}=fork_sh_out;
    gaussian_resource_mode_table #(.GROUP_LANES(1),.PROJECTION_LANES(LANES),.SH_LANES(SH_LANES),.RASTER_LANES(1))u_mode_table(
      .active_mode_i(active_mode_o),.group_active_lanes_o(),.projection_active_lanes_o(),.sh_active_lanes_o(sh_active_lanes),
      .raster_active_lanes_o(),.group_weight_o(),.projection_weight_o(),.raster_weight_o(),.shared_math_owner_o(),.aggressive_clock_gate_o());
    gaussian_sh_color_array #(.LANES(SH_LANES),.META_W(META_W),.SEQ_W(SEQ_W),.COORD_W(COORD_W),
      .COEFF_W(COEFF_W),.COEFFS(COEFFS),.RETIRE_DEPTH(RETIRE_DEPTH),
      .ENABLE_OPERAND_ISOLATION(ENABLE_OPERAND_ISOLATION))u_sh(
      .clk_i(clk_i),.rst_ni(rst_ni),.cfg_active_lanes_i(sh_active_lanes),
      .s_valid_i(fork_sh_valid),.s_ready_o(fork_sh_ready),.s_meta_i(sh_meta_in),
      .s_world_x_q16_i(sh_wx),.s_world_y_q16_i(sh_wy),.s_world_z_q16_i(sh_wz),
      .cfg_camera_x_q16_i(cfg_camera_x_q16_i),.cfg_camera_y_q16_i(cfg_camera_y_q16_i),.cfg_camera_z_q16_i(cfg_camera_z_q16_i),
      .s_coeff_q12_flat_i(sh_coeff),.m_valid_o(sh_result_valid),.m_ready_i(sh_result_ready),.m_meta_o(sh_meta_out),
      .m_r_q12_o(sh_r),.m_g_q12_o(sh_g),.m_b_q12_o(sh_b),.m_direction_fallback_o(sh_fallback),.m_numeric_overflow_o(sh_overflow),
      .active_mask_o(sh_active_mask_o),.all_idle_o(sh_array_idle),.retire_wait_o(sh_retire_wait),.protocol_error_o(sh_protocol_error));
    assign projection_task={projection_desc,projection_x,projection_y};assign sh_color={sh_r,sh_g,sh_b,sh_fallback,sh_overflow};
    ordered_projection_sh_join #(.TASK_W(TASK_W),.META_W(META_W),.SEQ_W(SEQ_W),.COLOR_W(COLOR_W),.SH_DEPTH(RETIRE_DEPTH))u_join(
      .clk_i(clk_i),.rst_ni(rst_ni),.projection_valid_i(projection_valid),.projection_ready_o(projection_ready),
      .projection_data_i(projection_task),.projection_first_i(projection_first),.projection_last_i(projection_last),
      .projection_culled_i(projection_culled),.sh_valid_i(sh_result_valid),.sh_ready_o(sh_result_ready),
      .sh_meta_i(sh_meta_out),.sh_color_i(sh_color),.m_valid_o(join_valid),.m_ready_i(m_ready_i),
      .m_projection_data_o(joined_task),.m_color_o(joined_color),.m_first_o(join_first),.m_last_o(join_last),
      .m_culled_o(join_culled),.sequence_mismatch_o(join_mismatch),.sh_occupancy_o(sh_occupancy),.empty_o(join_empty));
    assign m_valid_o=join_valid;assign {m_desc_o,m_block_x_o,m_block_y_o}=joined_task;
    assign {m_r_q12_o,m_g_q12_o,m_b_q12_o,m_sh_fallback_o,m_numeric_overflow_o}=joined_color;
    assign m_first_o=join_first;assign m_last_o=join_last;assign m_culled_o=join_culled;
    assign joined_retire=join_valid&&m_ready_i&&join_last;
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)source_count_q<='0;
      else case({source_accept,joined_retire})2'b10:source_count_q<=source_count_q+1'b1;
        2'b01:source_count_q<=source_count_q-1'b1;default:source_count_q<=source_count_q;endcase
    end
    assign auxiliary_empty=source_count_q==0&&fork_empty&&join_empty&&sh_array_idle;
    assign all_idle_o=auxiliary_empty&&projection_idle&&downstream_empty_i;
    assign stage_projection_busy_o=!projection_idle;
    assign retire_wait_o=projection_retire_wait||sh_retire_wait;
    assign protocol_error_o=projection_protocol_error||sh_protocol_error||join_mismatch;
endmodule
