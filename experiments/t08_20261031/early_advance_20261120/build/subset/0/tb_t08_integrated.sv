`timescale 1ns/1ps
module tb_t08_integrated;
`ifndef TB_LANES
`define TB_LANES 1
`endif
`ifndef TB_PIXEL_TERMINATION_SKIP
`define TB_PIXEL_TERMINATION_SKIP 0
`endif
  longint unsigned t07_accepted=0,t07_issued=0,t07_skipped=0,t07_updates=0,t07_full_blocks=0;
  always @(posedge clk_i)if(rst_ni)begin
    if(dut.u_frame.u_render.u_render.u_raster.u_raster.task_valid_i&&dut.u_frame.u_render.u_render.u_raster.u_raster.task_ready_o)begin
      t07_accepted<=t07_accepted+1;
      if(`TB_PIXEL_TERMINATION_SKIP&&
        (dut.u_frame.u_render.u_render.u_raster.u_raster.color_r_q12_i>4096||
         dut.u_frame.u_render.u_render.u_raster.u_raster.color_g_q12_i>4096||
         dut.u_frame.u_render.u_render.u_raster.u_raster.color_b_q12_i>4096))
        $fatal(1,"T07 termination color bound violated");
    end
    if(dut.u_frame.u_render.u_render.u_raster.u_raster.filtered_valid&&dut.u_frame.u_render.u_render.u_raster.u_raster.filtered_ready)t07_issued<=t07_issued+1;
    if(dut.u_frame.u_render.u_render.u_raster.u_raster.skipped_terminated_pulse_o)t07_skipped<=t07_skipped+1;
    if(dut.u_frame.u_render.u_render.u_raster.u_raster.new_terminated_mask!=0)t07_updates<=t07_updates+1;
    if(dut.u_frame.u_render.u_render.u_raster.u_raster.block_terminated_pulse_o)t07_full_blocks<=t07_full_blocks+1;
  end
`ifndef TB_RGB_READ_BURST
`define TB_RGB_READ_BURST 1
`endif
  integer t08_format=0;
  longint unsigned t08_expected_beats=0,t08_precomputed=0,t08_requests=0;
  longint unsigned t08_world_pre[0:`TB_LANES-1];
  function automatic integer t08_record_beats(input logic[15:0]h);
    if(h[10])return 9;
    case(h[12:11])0:return 3;1:return 4;2:return 6;3:return h[13]?9:8;endcase
  endfunction
  always @(posedge clk_i)if(rst_ni)begin
    if(dut.attr_req_valid&&dut.attr_req_ready)begin
      t08_requests<=t08_requests+1;
      t08_expected_beats<=t08_expected_beats+(t08_format==0?9:t08_record_beats(attr_mem[dut.attr_req_gid*9][15:0]));
    end
    if(dut.attr_rsp_valid&&dut.attr_rsp_ready&&dut.compressed_precomputed)t08_precomputed<=t08_precomputed+1;
  end
  generate for(genvar l=0;l<`TB_LANES;l++)begin:g_t08_observe
    initial t08_world_pre[l]=0;
    always @(posedge clk_i)if(rst_ni&&
      dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[l].u_lane.world_cov_valid&&
      dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[l].u_lane.world_cov_ready&&
      dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[l].u_lane.world_aux[246])t08_world_pre[l]<=t08_world_pre[l]+1;
  end endgenerate
  integer state_pending_beats[0:3];
  initial $display("REAL_RGB_BURST configured=%0d",`TB_RGB_READ_BURST);
`ifndef TB_SHARED_P_DOT3
`define TB_SHARED_P_DOT3 0
`endif
`ifndef TB_QSU_LOCAL_RECORDS
`define TB_QSU_LOCAL_RECORDS 0
`endif
`ifndef TB_QSU_PRECOUNT
`define TB_QSU_PRECOUNT 0
`endif
`include "verification/rtl/t06_scratch_signals.svh"
`ifndef TB_BSU_PIPELINED
`define TB_BSU_PIPELINED 0
`endif
`ifndef TB_BITONIC_SORT
`define TB_BITONIC_SORT 0
`endif
`ifndef TB_FINAL_RGB
`define TB_FINAL_RGB 0
`endif
`ifndef TB_MAX_COUNT
`define TB_MAX_COUNT 8
`endif
`ifndef TB_MAX_PIXELS
`define TB_MAX_PIXELS 1024
`endif
`ifndef TB_WRITE_BUFFER_DEPTH
`define TB_WRITE_BUFFER_DEPTH 2
`endif
`ifndef TB_STATE_ENTRIES
`define TB_STATE_ENTRIES 2
`endif
`ifndef TB_STATE_MSHR_COUNT
`define TB_STATE_MSHR_COUNT 2
`endif
`ifndef TB_STATE_WINDOW_ENTRIES
`define TB_STATE_WINDOW_ENTRIES 2
`endif
`ifndef TB_RESPONSE_BLEND_BYPASS
`define TB_RESPONSE_BLEND_BYPASS 0
`endif
`ifndef TB_BLEND_COMMIT_BYPASS
`define TB_BLEND_COMMIT_BYPASS 0
`endif
`ifndef TB_OPERAND_ISOLATION
`define TB_OPERAND_ISOLATION 0
`endif
`ifndef TB_USE_SHARED_PE
`define TB_USE_SHARED_PE 1
`endif
`ifndef TB_USE_STREAMING_DEPTH_PREPASS
`define TB_USE_STREAMING_DEPTH_PREPASS 0
`endif
`ifndef TB_ENABLE_SHAPE_BLOCK_REJECT
`define TB_ENABLE_SHAPE_BLOCK_REJECT 0
`endif
`ifndef TB_USE_SHARED_PROJECTION_PE
`define TB_USE_SHARED_PROJECTION_PE 1
`endif
`ifndef TB_USE_SHARED_RASTER_PE
`define TB_USE_SHARED_RASTER_PE 0
`endif
`ifndef TB_ENABLE_ALPHA_ZERO_SKIP
`define TB_ENABLE_ALPHA_ZERO_SKIP 0
`endif
`ifndef TB_USE_PARALLEL_GROUP_SORT
`define TB_USE_PARALLEL_GROUP_SORT 0
`endif
`ifndef TB_SHARED_SORT_BINARY_SEARCH
`define TB_SHARED_SORT_BINARY_SEARCH 0
`endif
`ifndef TB_SORT_SERIAL_FALLBACK
`define TB_SORT_SERIAL_FALLBACK 1
`endif
`ifndef TB_SORT_BATCH_FORWARDING
`define TB_SORT_BATCH_FORWARDING 1
`endif
`ifndef TB_SORT_PHASE_FORWARDING
`define TB_SORT_PHASE_FORWARDING 1
`endif
`ifndef TB_SORT_MONOTONIC_FASTPATH
`define TB_SORT_MONOTONIC_FASTPATH 1
`endif
`ifndef TB_SORT_STABLE_RUN_FASTPATH
`define TB_SORT_STABLE_RUN_FASTPATH 1
`endif
`ifndef TB_USE_WRITEBACK
`define TB_USE_WRITEBACK 0
`endif
`ifndef TB_WRITEBACK_DEPTH
`define TB_WRITEBACK_DEPTH 32
`endif
`ifndef TB_USE_MULTIWRITE
`define TB_USE_MULTIWRITE 1
`endif
`ifndef TB_MULTIWRITE_DEPTH
`define TB_MULTIWRITE_DEPTH 8
`endif
`ifndef TB_MULTIWRITE_FORWARDING
`define TB_MULTIWRITE_FORWARDING 0
`endif
`ifndef TB_MAX_AXI_WRITES
`define TB_MAX_AXI_WRITES 16384
`endif
`ifndef TB_LANES
`define TB_LANES 1
`endif
`ifndef TB_GID_W
`define TB_GID_W 8
`endif
`ifndef TB_SEQ_W
`define TB_SEQ_W 8
`endif
`ifndef TB_GROUP_CAPACITY
`define TB_GROUP_CAPACITY `TB_MAX_COUNT
`endif
`ifndef TB_SORT_CAPACITY
`define TB_SORT_CAPACITY `TB_GROUP_CAPACITY
`endif
  localparam GID_W=`TB_GID_W,LANES=`TB_LANES,COEFF_W=18,FLAT_W=3*16*COEFF_W;
  localparam MAX_COUNT=`TB_MAX_COUNT,MAX_PIXELS=`TB_MAX_PIXELS;
`include "verification/rtl/t06_perf_measurements.svh"
`include "verification/rtl/t06_memory_layout.svh"
`include "verification/rtl/t06_memory_scratch.svh"
  logic clk_i=0,rst_ni=0,psel_i=0,penable_i=0,pwrite_i=0;logic[11:0]paddr_i=0;
  logic[31:0]pwdata_i=0;logic[3:0]pstrb_i=0;logic[31:0]prdata_o;logic pready_o,pslverr_o,irq_o;
  logic source_valid_i=0,source_ready_o;logic[GID_W-1:0]source_gid_i=0;logic signed[26:0]source_world_x_q16_i=0,source_world_y_q16_i=0,source_world_z_q16_i=0;logic source_last_i=0;
  logic attr_clear_valid_i=0,attr_write_en_i=0;logic[GID_W-1:0]attr_write_gid_i=0;
  logic signed[26:0]attr_write_world_x_q16_i=0,attr_write_world_y_q16_i=0,attr_write_world_z_q16_i=0;
  logic signed[21:0]attr_write_qw_q20_i=0,attr_write_qx_q20_i=0,attr_write_qy_q20_i=0,attr_write_qz_q20_i=0;
  logic[23:0]attr_write_scale_x_q20_i=0,attr_write_scale_y_q20_i=0,attr_write_scale_z_q20_i=0;
  logic[12:0]attr_write_opacity_q12_i=0;logic[FLAT_W-1:0]attr_write_coeff_q12_flat_i=0;
  logic signed[21:0]cfg_r00_q20_i=-155152,cfg_r01_q20_i=-664437,cfg_r02_q20_i=796218;
  logic signed[21:0]cfg_r10_q20_i=317646,cfg_r11_q20_i=735934,cfg_r12_q20_i=676028;
  logic signed[21:0]cfg_r20_q20_i=-987188,cfg_r21_q20_i=341227,cfg_r22_q20_i=92387;
  logic signed[26:0]cfg_tx_q16_i=2765,cfg_ty_q16_i=-162664,cfg_tz_q16_i=260242;
  logic signed[26:0]cfg_camera_x_q16_i=294691,cfg_camera_y_q16_i=31228,cfg_camera_z_q16_i=79842;
  logic signed[32:0]cfg_fx_q16_i=2167573,cfg_fy_q16_i=2167573,cfg_cx_q16_i=1015808,cfg_cy_q16_i=655360;
  logic signed[26:0]cfg_near_q16_i=13107,cfg_far_q16_i=65536000;logic[34:0]cfg_regularizer_q8_i=77;
  logic signed[26:0]cfg_depth_pivot0_q16_i=785541,cfg_depth_pivot1_q16_i=952701,cfg_depth_pivot2_q16_i=1007945;
  logic commit_valid_o,commit_ready_i=1;logic[31:0]commit_task_id_o,commit_block_id_o;logic[GID_W-1:0]commit_gid_o;
  logic[15:0]commit_epoch_id_o;logic[12:0]commit_alpha_q12_o;logic commit_pass_alpha_o;logic[31:0]commit_pixel_id_o;
  logic[12:0]commit_r_q12_o,commit_g_q12_o,commit_b_q12_o;logic[15:0]commit_t_q16_o;logic commit_newly_terminated_o;
  logic[LANES-1:0]projection_active_mask_o,sh_active_mask_o,raster_active_mask_o;logic attribute_read_pulse_o;
  logic frame_busy_o,frame_done_pulse_o,frame_error_o;logic[31:0]frame_error_status_o;logic[1:0]active_mode_o;logic[15:0]epoch_id_o;
  logic[63:0]perf_cycle_count_o,perf_commit_count_o,perf_state_miss_count_o,perf_state_read_stall_count_o,perf_output_stall_count_o;
  logic[1:0]m_axi_mean_arid_o,m_axi_mean_rid_i=0;logic[63:0]m_axi_mean_araddr_o;logic[7:0]m_axi_mean_arlen_o;logic[2:0]m_axi_mean_arsize_o;logic[1:0]m_axi_mean_arburst_o;logic m_axi_mean_arvalid_o,m_axi_mean_arready_i;logic[127:0]m_axi_mean_rdata_i;logic[1:0]m_axi_mean_rresp_i=0;logic m_axi_mean_rlast_i,m_axi_mean_rvalid_i=0,m_axi_mean_rready_o;
  logic[1:0]m_axi_camera_arid_o,m_axi_camera_rid_i=0;logic[63:0]m_axi_camera_araddr_o;logic[7:0]m_axi_camera_arlen_o;logic[2:0]m_axi_camera_arsize_o;logic[1:0]m_axi_camera_arburst_o;logic m_axi_camera_arvalid_o,m_axi_camera_arready_i;logic[127:0]m_axi_camera_rdata_i=0;logic[1:0]m_axi_camera_rresp_i=0;logic m_axi_camera_rlast_i=0,m_axi_camera_rvalid_i=0,m_axi_camera_rready_o;
  logic[1:0]m_axi_attr_arid_o,m_axi_attr_rid_i=0;logic[63:0]m_axi_attr_araddr_o;logic[7:0]m_axi_attr_arlen_o;logic[2:0]m_axi_attr_arsize_o;logic[1:0]m_axi_attr_arburst_o;logic m_axi_attr_arvalid_o,m_axi_attr_arready_i;logic[127:0]m_axi_attr_rdata_i;logic[1:0]m_axi_attr_rresp_i=0;logic m_axi_attr_rlast_i,m_axi_attr_rvalid_i=0,m_axi_attr_rready_o;
  logic[1:0]m_axi_out_awid_o,m_axi_out_bid_i=0;logic[63:0]m_axi_out_awaddr_o;logic[7:0]m_axi_out_awlen_o;logic[2:0]m_axi_out_awsize_o;logic[1:0]m_axi_out_awburst_o;logic m_axi_out_awvalid_o,m_axi_out_awready_i;logic[127:0]m_axi_out_wdata_o;logic[15:0]m_axi_out_wstrb_o;logic m_axi_out_wlast_o,m_axi_out_wvalid_o,m_axi_out_wready_i;logic[1:0]m_axi_out_bresp_i=0;logic m_axi_out_bvalid_i=0,m_axi_out_bready_o;
  logic[1:0]m_axi_state_arid_o,m_axi_state_rid_i=0;logic[63:0]m_axi_state_araddr_o;logic[7:0]m_axi_state_arlen_o;logic[2:0]m_axi_state_arsize_o;logic[1:0]m_axi_state_arburst_o;logic m_axi_state_arvalid_o,m_axi_state_arready_i;logic[127:0]m_axi_state_rdata_i=0;logic[1:0]m_axi_state_rresp_i=0;logic m_axi_state_rlast_i=1,m_axi_state_rvalid_i=0,m_axi_state_rready_o;
  logic[127:0]mean_mem[0:MAX_COUNT-1],attr_mem[0:MAX_COUNT*9-1],state_mem[0:MAX_PIXELS-1];
  logic[54:0]auto_observe_render_mem[0:MAX_PIXELS-1];
  logic[31:0]global_gid_mem[0:MAX_COUNT-1];
  logic[63:0]camera_mem[0:27];
  integer workload_count=4,workload_width=32,workload_height=21;
  integer camera_ptr=0,camera_left=0;
  integer mean_ptr=0,mean_left=0,attr_ptr=0,attr_left=0;
  integer shared_competing_cycles=0,shared_main_mac_grants=0;
  integer attr_lookup_slot,attr_lookup_index,attr_request_gid,attr_record_byte;
  integer state_pending[0:3];integer state_delay[0:3];logic[1:0]state_rsp_select=0;
  integer state_rsp_pixel_q=-1;logic[1:0]state_rsp_active_tag_q=0;integer state_rsp_candidate;
  logic state_trace=0;
  wire[3:0]debug_cache_mshr_valid,debug_cache_mshr_issued;
  wire debug_cache_query_hit,debug_cache_response_valid,debug_cache_response_ready;
  wire[2:0]debug_blend_count;wire[2:0]debug_blend_head_state;
  wire[15:0]debug_blend_head_epoch;wire[31:0]debug_blend_head_pixel;
  wire[15:0]debug_blend_epoch_0,debug_blend_epoch_1;wire[31:0]debug_blend_pixel_0,debug_blend_pixel_1;
  wire debug_blend_out_valid,debug_blend_out_ready,debug_response_blend_bypass_fire;
  wire debug_blend_commit_bypass_fire;
  wire[2:0]debug_mshr_occupancy={2'b0,debug_cache_mshr_valid[0]}+
    {2'b0,debug_cache_mshr_valid[1]}+{2'b0,debug_cache_mshr_valid[2]}+
    {2'b0,debug_cache_mshr_valid[3]};
  generate if(`TB_STATE_MSHR_COUNT==4)begin:g_debug_quad_mshr
    assign debug_cache_mshr_valid=
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache_quad.u_state_cache.mshr_valid_q;
    assign debug_cache_mshr_issued=
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache_quad.u_state_cache.mshr_issued_q;
    assign debug_cache_query_hit=
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache_quad.u_state_cache.query_hit;
    assign debug_cache_response_valid=
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache_quad.u_state_cache.response_valid_o;
    assign debug_cache_response_ready=
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache_quad.u_state_cache.response_ready_i;
  end else if(`TB_STATE_MSHR_COUNT==2)begin:g_debug_dual_mshr
    assign debug_cache_mshr_valid=
      {2'b0,dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache.u_state_cache.mshr_valid_q};
    assign debug_cache_mshr_issued=
      {2'b0,dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache.u_state_cache.mshr_issued_q};
    assign debug_cache_query_hit=
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache.u_state_cache.query_hit;
    assign debug_cache_response_valid=
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache.u_state_cache.response_valid_o;
    assign debug_cache_response_ready=
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache.u_state_cache.response_ready_i;
  end else begin:g_debug_single_mshr
    assign debug_cache_mshr_valid={3'b0,
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache_single.u_state_cache.mshr_valid_q};
    assign debug_cache_mshr_issued={3'b0,
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache_single.u_state_cache.mshr_issued_q};
    assign debug_cache_query_hit=
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache_single.u_state_cache.query_hit;
    assign debug_cache_response_valid=
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache_single.u_state_cache.response_valid_o;
    assign debug_cache_response_ready=
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache_single.u_state_cache.response_ready_i;
  end endgenerate
  generate if(`TB_STATE_WINDOW_ENTRIES==4)begin:g_debug_window4
    assign debug_blend_count=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.count_q;
    assign debug_blend_head_state=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.slot_state_q[
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.head_q];
    assign debug_blend_head_epoch=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.epoch_q[
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.head_q];
    assign debug_blend_head_pixel=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.pixel_q[
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.head_q];
    assign debug_blend_epoch_0=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.epoch_q[0];
    assign debug_blend_epoch_1=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.epoch_q[1];
    assign debug_blend_pixel_0=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.pixel_q[0];
    assign debug_blend_pixel_1=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.pixel_q[1];
    assign debug_blend_out_valid=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.blend_out_valid;
    assign debug_blend_out_ready=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.blend_out_ready;
    assign debug_response_blend_bypass_fire=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.response_bypass_fire;
    assign debug_blend_commit_bypass_fire=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_4.u_blend_state_commit.blend_commit_bypass_fire;
  end else begin:g_debug_window2
    assign debug_blend_count={1'b0,dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_2.u_blend_state_commit.count_q};
    assign debug_blend_head_state=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_2.u_blend_state_commit.slot_state_q[
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_2.u_blend_state_commit.head_q];
    assign debug_blend_head_epoch=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_2.u_blend_state_commit.epoch_q[
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_2.u_blend_state_commit.head_q];
    assign debug_blend_head_pixel=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_2.u_blend_state_commit.pixel_q[
      dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_2.u_blend_state_commit.head_q];
    assign debug_blend_epoch_0=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_2.u_blend_state_commit.epoch_q[0];
    assign debug_blend_epoch_1=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_2.u_blend_state_commit.epoch_q[1];
    assign debug_blend_pixel_0=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_2.u_blend_state_commit.pixel_q[0];
    assign debug_blend_pixel_1=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_2.u_blend_state_commit.pixel_q[1];
    assign debug_blend_out_valid=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_2.u_blend_state_commit.blend_out_valid;
    assign debug_blend_out_ready=dut.u_frame.u_render.u_render.u_raster.u_raster.g_blend_window_2.u_blend_state_commit.blend_out_ready;
    assign debug_response_blend_bypass_fire=1'b0;
    assign debug_blend_commit_bypass_fire=1'b0;
  end endgenerate
  integer read_latency=0,read_gap=0,ready_period=1,ready_low=0,axi_cycle=0,frame_mode=3,max_timeout=1000000;
  integer mean_delay=0,attr_delay=0,write_response_latency=2;
  string mean_path="experiments/rtl_workloads/bonsai_cammid_n4_d32/mean.memh";
  string attr_path="experiments/rtl_workloads/bonsai_cammid_n4_d32/attribute.memh";
  string global_gid_path="";
  string camera_path="experiments/rtl_workloads/bonsai_cammid_n4_d32/camera.memh";
  string frame_path="experiments/rtl_workloads/bonsai_cammid_n4_d32/frame_state.memh";
  string workload_label="bonsai_camera146";
  string rgb_path="";
  string sorted_trace_path="";integer sorted_trace_file=0,sorted_trace_count=0;
  logic[7:0]rgb_mem[0:MAX_PIXELS*16-1];
  integer rgb_stride,rgb_bytes,rgb_read_count=0,rgb_write_beats=0,rgb_bursts=0;
  integer rgb_beats_left=0,rgb_write_offset=0;
  wire[63:0]backing_base=OUTPUT_BASE+(`TB_FINAL_RGB ? 64'(rgb_bytes) : 64'd0);
  string mean2_path="",attr2_path="",global_gid2_path="",camera2_path="";
  string batch_root_path="",state_in_path="";
  logic sparse_global_gid_mode=0,two_batch_mode=0,batch_list_mode=0,state_in_mode=0;
  logic auto_mode=0,advisor_trace=0;
  integer auto_repeat_frames=1,auto_observe_cycles=0,auto_selected_cycles=0;
  integer auto_observe_windows=0;
  integer auto_observe_mode=0,auto_selected_mode=0,auto_image_mismatches=0;
  integer auto_observe_state_reads=0,auto_observe_state_writes=0;
  integer reported_state_reads=0,reported_state_writes=0;
  logic[31:0]auto_status=0;logic[1:0]auto_recommended_mode=0,auto_window_winner=0;
  logic auto_recommendation_valid=0;
  integer batch_list_count=0,batch_list_index=0,batch_first_index=0,batch_last_index=0,batch_control=0;
  integer first_workload_count=0,total_workload_count=0;
  logic[15:0]first_batch_epoch=0;
  logic out_aw_seen=0,out_w_seen=0;logic[63:0]out_addr_q;logic[127:0]out_data_q;
  integer b_due[0:`TB_MAX_AXI_WRITES-1];integer b_put=0,b_get=0;
  logic[1:0]b_id[0:`TB_MAX_AXI_WRITES-1];
  integer mean_beats=0,attr_beats=0,state_reads=0,state_writes=0;
  integer consecutive_same_pixel_commits=0;logic last_commit_valid=0;logic[31:0]last_commit_pixel=0;
  integer collect_cycles=0,drain_cycles=0,group_busy_cycles=0,sort_busy_cycles=0;
  integer group_service_stall_cycles=0;
  integer attr_wait_cycles=0,projection_busy_cycles=0,sh_busy_cycles=0,raster_busy_cycles=0;
  integer projection_raster_overlap_cycles=0,sorted_backpressure_cycles=0,block_backpressure_cycles=0;
  integer retire_wait_cycles=0,state_cache_busy_cycles=0;
  integer state_window_wait_cycles=0,state_window_same_key_cycles=0,state_window_different_key_cycles=0;
  integer blend_window_full_cycles=0,mshr_zero_cycles=0,mshr_one_cycles=0,mshr_two_cycles=0;
  integer mshr_full_query_block_cycles=0,cache_response_block_cycles=0,miss_issue_block_cycles=0;
  integer state_ar_stall_cycles=0,state_r_stall_cycles=0,reader_response_block_cycles=0;
  integer third_candidate_cycles=0,third_with_two_mshr_cycles=0,third_with_one_mshr_cycles=0;
  integer third_distinct_key_cycles=0,third_distinct_with_two_mshr_cycles=0,third_raw_hazard_cycles=0;
  integer head_need_query_cycles=0,head_wait_response_cycles=0,head_need_blend_cycles=0;
  integer head_wait_blend_cycles=0,head_done_blocked_cycles=0;
  integer projection_issue_count=0,sh_issue_count=0,raster_issue_count=0,response_blend_bypass_count=0;
  integer shape_block_reject_count=0;
  integer blend_commit_bypass_count=0;
  integer projection_trace_limit=0,projection_trace_count=0;
  integer covariance_trace_limit=0,covariance_trace_count=0;
  integer projection_inactive_issue_count=0,sh_inactive_issue_count=0,raster_inactive_issue_count=0;
  always#5 clk_i=~clk_i;
  wire axi_ready=(ready_period<=1)||(axi_cycle%ready_period>=ready_low);
  wire out_aw_fire=m_axi_out_awvalid_o&&m_axi_out_awready_i;
  wire out_w_fire=m_axi_out_wvalid_o&&m_axi_out_wready_i;
  always@(posedge clk_i)if(rst_ni&&dut.u_frame.sorted_valid&&dut.u_frame.sorted_ready)begin
    if(sorted_trace_file!=0)$fdisplay(sorted_trace_file,"%0d %0d %0d",
      $signed(dut.u_frame.sorted_depth),dut.u_frame.sorted_gid,dut.u_frame.sorted_seq);
    sorted_trace_count<=sorted_trace_count+1;
  end
  assign m_axi_camera_arready_i=axi_ready;
  assign m_axi_mean_arready_i=axi_ready;assign m_axi_attr_arready_i=axi_ready;
  assign m_axi_state_arready_i=axi_ready;assign m_axi_out_awready_i=axi_ready;
  assign m_axi_out_wready_i=axi_ready;
  always@(posedge clk_i)begin
    if(rst_ni&&projection_trace_count<projection_trace_limit&&
       dut.u_frame.u_render.u_render.block_valid&&dut.u_frame.u_render.u_render.block_ready&&
       dut.u_frame.u_render.u_render.block_first)begin
      $display("PROJECTION_DESC index=%0d gid=%0d culled=%0d keep=%0d overflow=%0d mean_q8=%0d,%0d bbox=%0d,%0d,%0d,%0d l=%0d,%0d,%0d shift=%0d,%0d opacity=%0d color=%0d,%0d,%0d",
        projection_trace_count,dut.u_frame.u_render.u_render.block_gid,
        dut.u_frame.u_render.u_render.block_culled,dut.u_frame.u_render.u_render.keep,
        dut.u_frame.u_render.u_render.descriptor_overflow,
        $signed(dut.u_frame.u_render.u_render.block_mean_x),
        $signed(dut.u_frame.u_render.u_render.block_mean_y),
        dut.u_frame.u_render.u_render.bbox_x0,dut.u_frame.u_render.u_render.bbox_y0,
        dut.u_frame.u_render.u_render.bbox_x1,dut.u_frame.u_render.u_render.bbox_y1,
        dut.u_frame.u_render.u_render.l00,$signed(dut.u_frame.u_render.u_render.l10),
        dut.u_frame.u_render.u_render.l11,$signed(dut.u_frame.u_render.u_render.coordinate_shift),
        $signed(dut.u_frame.u_render.u_render.factor_shift),dut.u_frame.u_render.u_render.block_opacity,
        dut.u_frame.u_render.u_render.block_r,dut.u_frame.u_render.u_render.block_g,
        dut.u_frame.u_render.u_render.block_b);
      projection_trace_count=projection_trace_count+1;
    end
  end
  // Trace the exact Q24.8 covariance accepted by each Cholesky encoder.  This
  // separates upstream projection/covariance errors from encoder arithmetic
  // errors without changing the synthesizable datapath.
  always@(posedge clk_i)begin
    if(rst_ni&&covariance_trace_count<covariance_trace_limit&&
       dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[0].u_lane.u_camera_lane.bbox_valid&&
       dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[0].u_lane.u_camera_lane.encoder_ready)begin
      $display("COVARIANCE_INPUT index=%0d lane=0 gid=%0d cov_q8=%0d,%0d,%0d upstream_overflow=%0d fullscreen=%0d",
        covariance_trace_count,
        $unsigned(dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[0].u_lane.u_camera_lane.bbox_projection_meta[60:29]),
        dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[0].u_lane.u_camera_lane.bbox_cov00,
        $signed(dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[0].u_lane.u_camera_lane.bbox_cov01),
        dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[0].u_lane.u_camera_lane.bbox_cov11,
        dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[0].u_lane.u_camera_lane.covariance_overflow,
        dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[0].u_lane.u_camera_lane.bbox_numeric_invalid);
      covariance_trace_count=covariance_trace_count+1;
    end
  end
  gs_accel_system_top #(.ENABLE_COMPRESSED_ATTRIBUTES(1'b1),.ATTR_DMA_EARLY_ADVANCE(1'b0),.ATTR_DEPTH(MAX_COUNT),.LANES(LANES),.AUTO_QSU_LOCAL_RECORDS(`TB_QSU_LOCAL_RECORDS),.AUTO_QSU_PRECOUNT_CHILDREN(`TB_QSU_PRECOUNT),.SHARED_P_DOT3(`TB_SHARED_P_DOT3),.FINAL_RGB_READ_BURST_BEATS(`TB_RGB_READ_BURST),
`ifndef TB_RELEASE_DEFAULTS
    .GROUP_CAPACITY(`TB_GROUP_CAPACITY),.SORT_CAPACITY(`TB_SORT_CAPACITY),.USE_FINAL_RGB_DMA(`TB_FINAL_RGB),
    .USE_BITONIC_SORT(`TB_BITONIC_SORT),
    .BSU_PIPELINED(`TB_BSU_PIPELINED),
`endif
    .STATE_ENTRIES(`TB_STATE_ENTRIES),.STATE_WINDOW_ENTRIES(`TB_STATE_WINDOW_ENTRIES),
    .STATE_MSHR_COUNT(`TB_STATE_MSHR_COUNT),
    .ENABLE_RESPONSE_BLEND_BYPASS(`TB_RESPONSE_BLEND_BYPASS),
    .ENABLE_BLEND_COMMIT_BYPASS(`TB_BLEND_COMMIT_BYPASS),
    .ENABLE_OPERAND_ISOLATION(`TB_OPERAND_ISOLATION),
    .USE_SHARED_PE(`TB_USE_SHARED_PE),
    .USE_STREAMING_DEPTH_PREPASS(`TB_USE_STREAMING_DEPTH_PREPASS),
    .ENABLE_SHAPE_BLOCK_REJECT(`TB_ENABLE_SHAPE_BLOCK_REJECT),
    .USE_PARALLEL_GROUP_SORT(`TB_USE_PARALLEL_GROUP_SORT),
    .SHARED_SORT_BINARY_SEARCH(`TB_SHARED_SORT_BINARY_SEARCH),
    .PARALLEL_SORT_SERIAL_FALLBACK(`TB_SORT_SERIAL_FALLBACK),
    .PARALLEL_SORT_BATCH_FORWARDING(`TB_SORT_BATCH_FORWARDING),
    .PARALLEL_SORT_PHASE_FORWARDING(`TB_SORT_PHASE_FORWARDING),
    .PARALLEL_SORT_MONOTONIC_FASTPATH(`TB_SORT_MONOTONIC_FASTPATH),
    .PARALLEL_SORT_STABLE_RUN_FASTPATH(`TB_SORT_STABLE_RUN_FASTPATH),
    .USE_SHARED_PROJECTION_PE(`TB_USE_SHARED_PROJECTION_PE),
`ifndef TB_RELEASE_DEFAULTS
    .USE_SHARED_RASTER_PE(`TB_USE_SHARED_RASTER_PE),
`endif
    .ENABLE_PIXEL_TERMINATION_SKIP(`TB_PIXEL_TERMINATION_SKIP),.ENABLE_ALPHA_ZERO_SKIP(`TB_ENABLE_ALPHA_ZERO_SKIP),
    .GID_W(GID_W),.SEQ_W(`TB_SEQ_W),.USE_AXI_MEAN_DMA(1),.USE_AXI_CAMERA_DMA(1),.USE_AXI_ATTR_DMA(1),
    .USE_AXI_PIXEL_WRITE(1),.USE_STATE_CACHE_BACKEND(1),.PIXEL_WRITE_BUFFER_DEPTH(`TB_WRITE_BUFFER_DEPTH),
    .USE_PIXEL_WRITEBACK_BUFFER(`TB_USE_WRITEBACK),.PIXEL_WRITEBACK_DEPTH(`TB_WRITEBACK_DEPTH),
    .USE_PIXEL_MULTIWRITE_BUFFER(`TB_USE_MULTIWRITE),.PIXEL_MULTIWRITE_DEPTH(`TB_MULTIWRITE_DEPTH),
    .USE_PIXEL_MULTIWRITE_FORWARDING(`TB_MULTIWRITE_FORWARDING))dut(.*);
`ifdef TB_RELEASE_DEFAULTS
  initial begin
    if(!dut.USE_BITONIC_SORT||!dut.BSU_PIPELINED||dut.GROUP_CAPACITY!=16||dut.SORT_CAPACITY!=16||
       !dut.USE_SHARED_RASTER_PE||!dut.USE_FINAL_RGB_DMA)$fatal(1,"production defaults not enabled");
    $display("T05_RELEASE_DEFAULTS K=%0d pipeline=%0d shared_R=%0d RGB=%0d",dut.SORT_CAPACITY,dut.BSU_PIPELINED,dut.USE_SHARED_RASTER_PE,dut.USE_FINAL_RGB_DMA);
  end
`endif

  always@(posedge clk_i)begin
    if(!rst_ni)begin shared_competing_cycles<=0;shared_main_mac_grants<=0;end
    else begin
      if(dut.u_frame.pe_g_req_valid&&dut.u_frame.pe_p_req_valid)
        shared_competing_cycles<=shared_competing_cycles+1;
      if(dut.u_frame.render_pe_valid&&dut.u_frame.render_pe_ready)
        shared_main_mac_grants<=shared_main_mac_grants+1;
    end
  end
  always@(posedge clk_i)begin
    if(!rst_ni)begin
      m_axi_camera_rvalid_i<=0;m_axi_mean_rvalid_i<=0;m_axi_attr_rvalid_i<=0;
      m_axi_state_rvalid_i<=0;m_axi_out_bvalid_i<=0;
      camera_ptr<=0;camera_left<=0;mean_ptr<=0;mean_left<=0;attr_ptr<=0;attr_left<=0;
      state_pending[0]<=-1;state_pending[1]<=-1;state_pending[2]<=-1;state_pending[3]<=-1;
      state_delay[0]<=0;state_delay[1]<=0;state_delay[2]<=0;state_delay[3]<=0;
      state_rsp_select<=0;state_rsp_pixel_q<=-1;state_rsp_active_tag_q<=0;b_put<=0;b_get<=0;
      mean_delay<=0;attr_delay<=0;axi_cycle<=0;
      consecutive_same_pixel_commits<=0;last_commit_valid<=0;last_commit_pixel<=0;
      collect_cycles<=0;drain_cycles<=0;group_busy_cycles<=0;sort_busy_cycles<=0;
      group_service_stall_cycles<=0;
      attr_wait_cycles<=0;projection_busy_cycles<=0;sh_busy_cycles<=0;raster_busy_cycles<=0;
      projection_raster_overlap_cycles<=0;sorted_backpressure_cycles<=0;block_backpressure_cycles<=0;
      retire_wait_cycles<=0;state_cache_busy_cycles<=0;
      state_window_wait_cycles<=0;state_window_same_key_cycles<=0;state_window_different_key_cycles<=0;
      blend_window_full_cycles<=0;mshr_zero_cycles<=0;mshr_one_cycles<=0;mshr_two_cycles<=0;
      mshr_full_query_block_cycles<=0;cache_response_block_cycles<=0;miss_issue_block_cycles<=0;
      state_ar_stall_cycles<=0;state_r_stall_cycles<=0;reader_response_block_cycles<=0;
      third_candidate_cycles<=0;third_with_two_mshr_cycles<=0;third_with_one_mshr_cycles<=0;
      third_distinct_key_cycles<=0;third_distinct_with_two_mshr_cycles<=0;third_raw_hazard_cycles<=0;
      head_need_query_cycles<=0;head_wait_response_cycles<=0;head_need_blend_cycles<=0;
      head_wait_blend_cycles<=0;head_done_blocked_cycles<=0;
      projection_issue_count<=0;sh_issue_count<=0;raster_issue_count<=0;shape_block_reject_count<=0;
      response_blend_bypass_count<=0;
      blend_commit_bypass_count<=0;
      projection_inactive_issue_count<=0;sh_inactive_issue_count<=0;raster_inactive_issue_count<=0;
    end else begin
      axi_cycle<=axi_cycle+1;
      if(dut.event_shape_block_reject)shape_block_reject_count<=shape_block_reject_count+1;
      if(frame_busy_o)begin
        if(|(dut.u_frame.u_render.u_render.u_front.u_projection.u_scheduler.lane_s_valid_o&
             dut.u_frame.u_render.u_render.u_front.u_projection.u_scheduler.lane_s_ready_i))
          projection_issue_count<=projection_issue_count+1;
        if(|(dut.u_frame.u_render.u_render.u_front.u_sh.u_schedule.lane_s_valid_o&
             dut.u_frame.u_render.u_render.u_front.u_sh.u_schedule.lane_s_ready_i))
          sh_issue_count<=sh_issue_count+1;
        if(|(dut.u_frame.u_render.u_render.u_raster.u_raster.u_alpha_array.u_order.lane_s_valid_o&
             dut.u_frame.u_render.u_render.u_raster.u_raster.u_alpha_array.u_order.lane_s_ready_i))
          raster_issue_count<=raster_issue_count+1;
        if(debug_response_blend_bypass_fire)
          response_blend_bypass_count<=response_blend_bypass_count+1;
        if(debug_blend_commit_bypass_fire)
          blend_commit_bypass_count<=blend_commit_bypass_count+1;
        if(|(dut.u_frame.u_render.u_render.u_front.u_projection.u_scheduler.lane_s_valid_o&
             ~projection_active_mask_o))projection_inactive_issue_count<=projection_inactive_issue_count+1;
        if(|(dut.u_frame.u_render.u_render.u_front.u_sh.u_schedule.lane_s_valid_o&
             ~sh_active_mask_o))sh_inactive_issue_count<=sh_inactive_issue_count+1;
        if(|(dut.u_frame.u_render.u_render.u_raster.u_raster.u_alpha_array.u_order.lane_s_valid_o&
             ~raster_active_mask_o))raster_inactive_issue_count<=raster_inactive_issue_count+1;
        if(dut.u_frame.state_q==2)collect_cycles<=collect_cycles+1;
        if(dut.u_frame.state_q==3)drain_cycles<=drain_cycles+1;
        if(dut.u_frame.group_busy)group_busy_cycles<=group_busy_cycles+1;
        if(dut.u_frame.sort_busy)sort_busy_cycles<=sort_busy_cycles+1;
        if(dut.u_frame.group_service_stall)group_service_stall_cycles<=group_service_stall_cycles+1;
        if(dut.u_frame.u_render.backend_req_valid&&!dut.u_frame.u_render.backend_req_ready)
          attr_wait_cycles<=attr_wait_cycles+1;
        if(!dut.u_frame.u_render.u_render.u_front.projection_idle)
          projection_busy_cycles<=projection_busy_cycles+1;
        if(!dut.u_frame.u_render.u_render.u_front.sh_array_idle)
          sh_busy_cycles<=sh_busy_cycles+1;
        if(!dut.u_frame.u_render.u_render.raster_idle)
          raster_busy_cycles<=raster_busy_cycles+1;
        if(!dut.u_frame.u_render.u_render.u_front.projection_idle&&!dut.u_frame.u_render.u_render.raster_idle)
          projection_raster_overlap_cycles<=projection_raster_overlap_cycles+1;
        if(dut.u_frame.sorted_valid&&!dut.u_frame.sorted_ready)
          sorted_backpressure_cycles<=sorted_backpressure_cycles+1;
        if(dut.u_frame.u_render.u_render.block_valid&&!dut.u_frame.u_render.u_render.block_ready)
          block_backpressure_cycles<=block_backpressure_cycles+1;
        if(dut.u_frame.render_retire_wait)retire_wait_cycles<=retire_wait_cycles+1;
        if(!dut.u_frame.u_render.u_render.state_cache_idle_o)
          state_cache_busy_cycles<=state_cache_busy_cycles+1;
        if(debug_blend_count==`TB_STATE_WINDOW_ENTRIES)
          blend_window_full_cycles<=blend_window_full_cycles+1;
        case(debug_mshr_occupancy)
          0:mshr_zero_cycles<=mshr_zero_cycles+1;
          1:mshr_one_cycles<=mshr_one_cycles+1;
          default:mshr_two_cycles<=mshr_two_cycles+1;
        endcase
        if(dut.u_frame.u_render.u_render.u_raster.u_raster.state_query_valid&&
           !dut.u_frame.u_render.u_render.u_raster.u_raster.state_query_ready&&
           !debug_cache_query_hit&&debug_mshr_occupancy==`TB_STATE_MSHR_COUNT)
          mshr_full_query_block_cycles<=mshr_full_query_block_cycles+1;
        if(debug_cache_response_valid&&!debug_cache_response_ready)
          cache_response_block_cycles<=cache_response_block_cycles+1;
        if(dut.state_miss_req_valid&&!dut.state_miss_req_ready)
          miss_issue_block_cycles<=miss_issue_block_cycles+1;
        if(m_axi_state_arvalid_o&&!m_axi_state_arready_i)
          state_ar_stall_cycles<=state_ar_stall_cycles+1;
        if(m_axi_state_rvalid_i&&!m_axi_state_rready_o)
          state_r_stall_cycles<=state_r_stall_cycles+1;
        if(dut.state_axi_rsp_valid&&!dut.state_axi_rsp_ready)
          reader_response_block_cycles<=reader_response_block_cycles+1;
        if(dut.u_frame.u_render.u_render.u_raster.u_raster.alpha_valid&&
           !dut.u_frame.u_render.u_render.u_raster.u_raster.alpha_ready&&
           debug_blend_count==`TB_STATE_WINDOW_ENTRIES)begin
          third_candidate_cycles<=third_candidate_cycles+1;
          if(debug_mshr_occupancy==`TB_STATE_MSHR_COUNT)third_with_two_mshr_cycles<=third_with_two_mshr_cycles+1;
          if(debug_mshr_occupancy==1)
            third_with_one_mshr_cycles<=third_with_one_mshr_cycles+1;
          if(({dut.u_frame.u_render.u_render.u_raster.u_raster.blend_epoch,
               dut.u_frame.u_render.u_render.u_raster.u_raster.blend_pixel_id}!=
              {debug_blend_epoch_0,debug_blend_pixel_0})&&
             ({dut.u_frame.u_render.u_render.u_raster.u_raster.blend_epoch,
               dut.u_frame.u_render.u_render.u_raster.u_raster.blend_pixel_id}!=
              {debug_blend_epoch_1,debug_blend_pixel_1}))begin
            third_distinct_key_cycles<=third_distinct_key_cycles+1;
            if(debug_mshr_occupancy==`TB_STATE_MSHR_COUNT)
              third_distinct_with_two_mshr_cycles<=third_distinct_with_two_mshr_cycles+1;
          end else third_raw_hazard_cycles<=third_raw_hazard_cycles+1;
          case(debug_blend_head_state)
            1:head_need_query_cycles<=head_need_query_cycles+1;
            2:head_wait_response_cycles<=head_wait_response_cycles+1;
            3:head_need_blend_cycles<=head_need_blend_cycles+1;
            4:head_wait_blend_cycles<=head_wait_blend_cycles+1;
            5:head_done_blocked_cycles<=head_done_blocked_cycles+1;
          endcase
        end
        // Validation-only opportunity probe for a future ordered state window.
        // alpha_valid is the next strictly ordered pixel. If the current
        // single-transaction state path blocks it, a different {epoch,pixel}
        // key is a potential overlap candidate; an equal key is a mandatory
        // RAW serialization case.
        if(dut.u_frame.u_render.u_render.u_raster.u_raster.alpha_valid&&
           !dut.u_frame.u_render.u_render.u_raster.u_raster.alpha_ready)begin
          state_window_wait_cycles<=state_window_wait_cycles+1;
          if({dut.u_frame.u_render.u_render.u_raster.u_raster.blend_epoch,
              dut.u_frame.u_render.u_render.u_raster.u_raster.blend_pixel_id}==
             {debug_blend_head_epoch,debug_blend_head_pixel})
            state_window_same_key_cycles<=state_window_same_key_cycles+1;
          else state_window_different_key_cycles<=state_window_different_key_cycles+1;
        end
      end
      if(dut.core_commit_valid&&dut.core_commit_ready)begin
        if(last_commit_valid&&last_commit_pixel==dut.core_commit_pixel)consecutive_same_pixel_commits<=consecutive_same_pixel_commits+1;
        last_commit_valid<=1;last_commit_pixel<=dut.core_commit_pixel;
      end
      if(m_axi_camera_arvalid_o&&m_axi_camera_arready_i)begin
        if(m_axi_camera_araddr_o!=CAMERA_BASE)
          $fatal(1,"unexpected camera descriptor address %h",m_axi_camera_araddr_o);
        camera_ptr<=0;camera_left<=m_axi_camera_arlen_o+1;
        m_axi_camera_rid_i<=m_axi_camera_arid_o;
      end
      if(!m_axi_camera_rvalid_i&&camera_left>0)begin
        m_axi_camera_rdata_i<={camera_mem[2*camera_ptr+1],camera_mem[2*camera_ptr]};
        m_axi_camera_rlast_i<=camera_left==1;m_axi_camera_rresp_i<=0;m_axi_camera_rvalid_i<=1;
      end else if(m_axi_camera_rvalid_i&&m_axi_camera_rready_o)begin
        m_axi_camera_rvalid_i<=0;camera_ptr<=camera_ptr+1;camera_left<=camera_left-1;
      end
      if(m_axi_mean_arvalid_o&&m_axi_mean_arready_i)begin
        check_region(m_axi_mean_araddr_o, (64'(m_axi_mean_arlen_o)+1)*16, MEAN_BASE, 64'(MAX_COUNT)*16);
        mean_ptr<=(m_axi_mean_araddr_o-MEAN_BASE)>>4;mean_left<=m_axi_mean_arlen_o+1;mean_delay<=read_latency;
      end
      if(mean_delay>0)mean_delay<=mean_delay-1;
      else if(!m_axi_mean_rvalid_i&&mean_left>0)begin
        m_axi_mean_rdata_i<=mean_mem[mean_ptr];m_axi_mean_rlast_i<=mean_left==1;m_axi_mean_rvalid_i<=1;
      end else if(m_axi_mean_rvalid_i&&m_axi_mean_rready_o)begin
        m_axi_mean_rvalid_i<=0;mean_ptr<=mean_ptr+1;mean_left<=mean_left-1;mean_beats<=mean_beats+1;mean_delay<=read_gap;
      end
      if(m_axi_attr_arvalid_o&&m_axi_attr_arready_i)begin
        check_region(m_axi_attr_araddr_o, (64'(m_axi_attr_arlen_o)+1)*16, ATTR_BASE, 64'(MAX_COUNT)*144);
        if(sparse_global_gid_mode)begin
          attr_record_byte=m_axi_attr_araddr_o-ATTR_BASE;
          attr_request_gid=attr_record_byte/144;
          attr_record_byte=attr_record_byte%144;
          if(attr_record_byte[3:0]!=0)$fatal(1,"unaligned sparse attribute address %h",m_axi_attr_araddr_o);
          attr_lookup_slot=-1;
          for(attr_lookup_index=0;attr_lookup_index<workload_count;attr_lookup_index=attr_lookup_index+1)
            if(global_gid_mem[attr_lookup_index]==attr_request_gid[31:0])attr_lookup_slot=attr_lookup_index;
          if(attr_lookup_slot<0)$fatal(1,"sparse attribute lookup missed global GID %0d",attr_request_gid);
          attr_ptr<=attr_lookup_slot*9+(attr_record_byte>>4);
        end else attr_ptr<=(m_axi_attr_araddr_o-ATTR_BASE)>>4;
        attr_left<=m_axi_attr_arlen_o+1;attr_delay<=read_latency;
      end
      if(attr_delay>0)attr_delay<=attr_delay-1;
      else if(!m_axi_attr_rvalid_i&&attr_left>0)begin
        m_axi_attr_rdata_i<=attr_mem[attr_ptr];m_axi_attr_rlast_i<=attr_left==1;m_axi_attr_rvalid_i<=1;
      end else if(m_axi_attr_rvalid_i&&m_axi_attr_rready_o)begin
        m_axi_attr_rvalid_i<=0;attr_ptr<=attr_ptr+1;attr_left<=attr_left-1;attr_beats<=attr_beats+1;attr_delay<=read_gap;
      end
      if(m_axi_state_arvalid_o&&m_axi_state_arready_i)begin
        if(m_axi_state_araddr_o[3:0]!=0||m_axi_state_arsize_o!=4||m_axi_state_arburst_o!=1||
           {1'b0,m_axi_state_araddr_o[11:0]}+(m_axi_state_arlen_o+1)*16>4096)$fatal(1,"invalid state/RGB read burst");
        state_pending_beats[m_axi_state_arid_o[1:0]]<=m_axi_state_arlen_o+1;
        check_region(m_axi_state_araddr_o, (64'(m_axi_state_arlen_o)+1)*16, backing_base, 64'(workload_width)*workload_height*16);
        if(state_trace&&state_reads>=60)$display("STATE_TRACE t=%0t AR id=%0d pixel=%0d",
          $time,m_axi_state_arid_o[1:0],(m_axi_state_araddr_o-backing_base)>>4);
        if(m_axi_state_araddr_o<backing_base||((m_axi_state_araddr_o-backing_base)>>4)>=workload_width*workload_height)
          $fatal(1,"state read outside scratch %h",m_axi_state_araddr_o);
        if(state_pending[m_axi_state_arid_o[1:0]]>=0)
          $fatal(1,"AXI state read reused pending ID %0d",m_axi_state_arid_o[1:0]);
        state_pending[m_axi_state_arid_o[1:0]]<=(m_axi_state_araddr_o-backing_base)>>4;
        state_delay[m_axi_state_arid_o[1:0]]<=read_latency;
      end
      if(state_delay[0]>0)state_delay[0]<=state_delay[0]-1;
      if(state_delay[1]>0)state_delay[1]<=state_delay[1]-1;
      if(state_delay[2]>0)state_delay[2]<=state_delay[2]-1;
      if(state_delay[3]>0)state_delay[3]<=state_delay[3]-1;
      if(!m_axi_state_rvalid_i)begin
        state_rsp_candidate=-1;
        if(state_pending[state_rsp_select]>=0&&state_delay[state_rsp_select]==0)
          state_rsp_candidate=state_rsp_select;
        else if(state_pending[(state_rsp_select+1)&3]>=0&&state_delay[(state_rsp_select+1)&3]==0)
          state_rsp_candidate=(state_rsp_select+1)&3;
        else if(state_pending[(state_rsp_select+2)&3]>=0&&state_delay[(state_rsp_select+2)&3]==0)
          state_rsp_candidate=(state_rsp_select+2)&3;
        else if(state_pending[(state_rsp_select+3)&3]>=0&&state_delay[(state_rsp_select+3)&3]==0)
          state_rsp_candidate=(state_rsp_select+3)&3;
        if(state_rsp_candidate>=0)begin
          if(state_trace&&state_reads>=60)$display("STATE_TRACE t=%0t OFFER id=%0d pixel=%0d",
            $time,state_rsp_candidate,state_pending[state_rsp_candidate]);
          m_axi_state_rid_i<=state_rsp_candidate[1:0];
          m_axi_state_rdata_i<=state_mem[state_pending[state_rsp_candidate]];
          m_axi_state_rlast_i<=state_pending_beats[state_rsp_candidate]==1;
          m_axi_state_rvalid_i<=1;
          state_rsp_active_tag_q<=state_rsp_candidate[1:0];
          state_rsp_pixel_q<=state_pending[state_rsp_candidate];
          state_rsp_select<=state_rsp_candidate+1'b1;
        end
      end else if(m_axi_state_rready_o)begin
        if(state_trace&&state_reads>=60)$display("STATE_TRACE t=%0t R_FIRE active=%0d rid=%b pixel=%0d rvalid=%b rready=%b",
          $time,state_rsp_active_tag_q,m_axi_state_rid_i,state_rsp_pixel_q,
          m_axi_state_rvalid_i,m_axi_state_rready_o);
        if(m_axi_state_rid_i[1:0]!=state_rsp_active_tag_q)
          $fatal(1,"AXI state RID changed while RVALID was active");
        if(state_pending[state_rsp_active_tag_q]!=state_rsp_pixel_q)
          $fatal(1,"AXI state pending entry changed before response handshake");
        state_pending_beats[state_rsp_active_tag_q]<=state_pending_beats[state_rsp_active_tag_q]-1;
        if(state_pending_beats[state_rsp_active_tag_q]>1)begin
          state_pending[state_rsp_active_tag_q]<=state_pending[state_rsp_active_tag_q]+1;
          state_rsp_pixel_q<=state_rsp_pixel_q+1;
          if(read_gap==0)begin
            m_axi_state_rvalid_i<=1;
            m_axi_state_rdata_i<=state_mem[state_pending[state_rsp_active_tag_q]+1];
            m_axi_state_rlast_i<=state_pending_beats[state_rsp_active_tag_q]==2;
          end else begin m_axi_state_rvalid_i<=0;state_delay[state_rsp_active_tag_q]<=read_gap;end
        end else begin
          m_axi_state_rvalid_i<=0;state_pending[state_rsp_active_tag_q]<=-1;state_rsp_pixel_q<=-1;
        end
        if(`TB_FINAL_RGB&&dut.final_rgb_busy)rgb_read_count<=rgb_read_count+1;
        else state_reads<=state_reads+1;
      end
      if(`TB_FINAL_RGB&&dut.final_rgb_busy)begin
        if(out_aw_fire)begin
          if(rgb_beats_left!=0)$fatal(1,"overlapping RGB AW");
          if(m_axi_out_awsize_o!=4||m_axi_out_awburst_o!=1||
             {1'b0,m_axi_out_awaddr_o[11:0]}+((int'(m_axi_out_awlen_o)+1)*16)>4096)
            $fatal(1,"invalid RGB burst/4KiB boundary");
          rgb_write_offset<=int'(m_axi_out_awaddr_o-OUTPUT_BASE);
          rgb_beats_left<=int'(m_axi_out_awlen_o)+1;rgb_bursts<=rgb_bursts+1;
        end
        if(out_w_fire)begin
          if(rgb_beats_left<=0||m_axi_out_wlast_o!=(rgb_beats_left==1))$fatal(1,"RGB WLAST mismatch");
          if(rgb_write_offset<0||rgb_write_offset+16>rgb_bytes)$fatal(1,"RGB write outside frame");
          for(integer lane=0;lane<16;lane=lane+1)
            if(m_axi_out_wstrb_o[lane])rgb_mem[rgb_write_offset+lane]<=m_axi_out_wdata_o[8*lane+:8];
          rgb_write_offset<=rgb_write_offset+16;rgb_beats_left<=rgb_beats_left-1;
          rgb_write_beats<=rgb_write_beats+1;
          if(m_axi_out_wlast_o)begin
            b_due[b_put%`TB_MAX_AXI_WRITES]<=axi_cycle+write_response_latency+1;
            b_id[b_put%`TB_MAX_AXI_WRITES]<=2; b_put<=b_put+1;
          end
        end
      end else begin
      if(out_aw_fire)begin check_region(m_axi_out_awaddr_o, (64'(m_axi_out_awlen_o)+1)*16, backing_base, 64'(workload_width)*workload_height*16); out_aw_seen<=1;out_addr_q<=m_axi_out_awaddr_o;end
      if(out_w_fire)begin out_w_seen<=1;out_data_q<=m_axi_out_wdata_o;end
      if((out_aw_seen||out_aw_fire)&&(out_w_seen||out_w_fire))begin
        if(out_aw_seen)state_mem[(out_addr_q-backing_base)>>4]<=out_w_seen?out_data_q:m_axi_out_wdata_o;
        else state_mem[(m_axi_out_awaddr_o-backing_base)>>4]<=out_w_seen?out_data_q:m_axi_out_wdata_o;
        if(b_put-b_get>=`TB_MAX_AXI_WRITES)$fatal(1,"AXI write response outstanding queue overflow");
        b_due[b_put%`TB_MAX_AXI_WRITES]<=axi_cycle+write_response_latency+1;b_put<=b_put+1;
        b_id[b_put%`TB_MAX_AXI_WRITES]<=0;
        out_aw_seen<=0;out_w_seen<=0;state_writes<=state_writes+1;
      end
      end
      // AXI permits back-to-back B responses.  Keep BVALID asserted after a
      // handshake when the next ordered response is already due; inserting a
      // compulsory idle cycle here would create an artificial 0.5 response/cycle
      // limit in the supposedly ideal memory profile.
      if(m_axi_out_bvalid_i&&m_axi_out_bready_o)begin
        b_get<=b_get+1;
        if(b_get+1<b_put&&axi_cycle>=b_due[(b_get+1)%`TB_MAX_AXI_WRITES])begin
          m_axi_out_bvalid_i<=1;m_axi_out_bid_i<=b_id[(b_get+1)%`TB_MAX_AXI_WRITES];end
        else m_axi_out_bvalid_i<=0;
      end else if(!m_axi_out_bvalid_i&&b_get<b_put&&axi_cycle>=b_due[b_get%`TB_MAX_AXI_WRITES])begin
        m_axi_out_bvalid_i<=1;m_axi_out_bid_i<=b_id[b_get%`TB_MAX_AXI_WRITES];end
    end
  end
  // Structured per-window trace used by the real-workload calibration script.
  // The snapshot registers were updated atomically on the preceding edge when
  // window_done became visible here.
  always@(posedge clk_i)begin
    if(rst_ni&&advisor_trace&&dut.advisor_window_done)
      $display("REAL_ADVISOR_WINDOW index=%0d active=%0d winner=%0d queued_valid=%0d queued_mode=%0d group=%0d sort=%0d projection=%0d raster=%0d block=%0d skip=%0d",
        dut.advisor_window_index,active_mode_o,dut.advisor_window_winner,
        dut.advisor_queue_valid_q,dut.advisor_queue_mode_q,dut.advisor_window_group,
        dut.advisor_window_sort,dut.advisor_window_projection,dut.advisor_window_raster,
        dut.advisor_window_block,dut.advisor_window_skip);
  end
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic apb_write(input[11:0]addr,input[31:0]data);begin
    paddr_i=addr;pwdata_i=data;pstrb_i=4'hf;pwrite_i=1;psel_i=1;penable_i=1;tick();
    psel_i=0;penable_i=0;pwrite_i=0;pstrb_i=0;
  end endtask
  task automatic apb_read(input[11:0]addr,output[31:0]data);begin
    paddr_i=addr;pwrite_i=0;psel_i=1;penable_i=1;#1;
    if(!pready_o||pslverr_o)$fatal(1,"APB read failed %h",addr);
    data=prdata_o;psel_i=0;penable_i=0;#1;
  end endtask
  task automatic report_sort_snapshot;
    logic[383:0]expected;logic[31:0]fields[12];logic[31:0]caps,snapshot_seq,read_word;
    begin
      apb_write(12'h080,32'h1);
      for(integer j=0;j<12;j=j+1)expected[32*j+:32]=dut.sort_work_totals[32*j+:32]-dut.sort_work_base_q[32*j+:32];
      tick();apb_read(12'h084,caps);apb_read(12'h080,snapshot_seq);
      for(integer j=0;j<12;j=j+1)begin
        apb_read(12'(12'h088+4*j),read_word);fields[j]=read_word;
        if(fields[j]!==expected[32*j+:32])$fatal(1,"sort APB snapshot field %0d disagrees with actual work got=%h expected=%h",j,fields[j],expected[32*j+:32]);
      end
      if(snapshot_seq!==1)$fatal(1,"sort snapshot sequence wrong");
      if(caps==0&&expected!==384'd0)$fatal(1,"absent candidate reported work");
      if(caps!=0&&(fields[0]!==dut.shared_pe_group_grant_count_q||fields[9]>fields[1]||fields[11]>fields[10]||fields[10]>fields[4]))
        $fatal(1,"sort counter accounting inconsistent");
      $display("REAL_SORT_WORK caps=%0d sequence=%0d shared=%0d local=%0d swaps=%0d phases=%0d groups=%0d fallback=%0d phase_grants=%0d phase_stalls=%0d shifts=%0d collect=%0d fast=%0d reverse=%0d",
        caps,snapshot_seq,fields[0],fields[1],fields[2],fields[3],fields[4],fields[5],fields[6],fields[7],fields[8],fields[9],fields[10],fields[11]);
    end
  endtask
  task automatic load_camera_config;begin
    // Historical workload files predate descriptor v1.  Upgrade only their
    // reserved high word in the testbench; generated production files carry
    // this tag directly.
    camera_mem[27][63:32]=32'h47534301;
    workload_width=camera_mem[25][15:0];workload_height=camera_mem[26][15:0];workload_count=camera_mem[27][31:0];
    if(workload_count<=0||workload_count>MAX_COUNT)$fatal(1,"workload count %0d exceeds MAX_COUNT %0d",workload_count,MAX_COUNT);
    if(workload_width*workload_height>MAX_PIXELS)$fatal(1,"workload pixels exceed MAX_PIXELS");
    cfg_r00_q20_i=camera_mem[0][21:0];cfg_r01_q20_i=camera_mem[1][21:0];cfg_r02_q20_i=camera_mem[2][21:0];
    cfg_r10_q20_i=camera_mem[3][21:0];cfg_r11_q20_i=camera_mem[4][21:0];cfg_r12_q20_i=camera_mem[5][21:0];
    cfg_r20_q20_i=camera_mem[6][21:0];cfg_r21_q20_i=camera_mem[7][21:0];cfg_r22_q20_i=camera_mem[8][21:0];
    cfg_tx_q16_i=camera_mem[9][26:0];cfg_ty_q16_i=camera_mem[10][26:0];cfg_tz_q16_i=camera_mem[11][26:0];
    cfg_camera_x_q16_i=camera_mem[12][26:0];cfg_camera_y_q16_i=camera_mem[13][26:0];
    cfg_camera_z_q16_i=camera_mem[14][26:0];cfg_fx_q16_i=camera_mem[15][32:0];
    cfg_fy_q16_i=camera_mem[16][32:0];cfg_cx_q16_i=camera_mem[17][32:0];cfg_cy_q16_i=camera_mem[18][32:0];
    cfg_near_q16_i=camera_mem[19][26:0];cfg_far_q16_i=camera_mem[20][26:0];
    cfg_regularizer_q8_i=camera_mem[21][31:0];cfg_depth_pivot0_q16_i=camera_mem[22][26:0];
    cfg_depth_pivot1_q16_i=camera_mem[23][26:0];cfg_depth_pivot2_q16_i=camera_mem[24][26:0];
  end endtask
  task automatic validate_sparse_batch(input integer count);integer j;begin
    if(sparse_global_gid_mode)begin
      for(j=0;j<count;j=j+1)
        if(mean_mem[j][31:0]!==global_gid_mem[j])
          $fatal(1,"mean/global GID mismatch slot=%0d mean=%0d table=%0d",j,mean_mem[j][31:0],global_gid_mem[j]);
    end
  end endtask
  // A disk checkpoint contains architecturally visible pixel state.  The
  // termination memories are an optimization sidecar, so reconstruct their
  // exact current-epoch contents from T<=7 before raster begins.  Without
  // this step a resumed simulation produces the same RGB but repeatedly
  // blends already terminated pixels, drifting Q0.16 T and doing unnecessary
  // work.  This is testbench-only checkpoint plumbing, not a new RTL path.
  task automatic restore_checkpoint_termination(input integer width,height);
    integer bx,by,x,y,block_id,mask_index,row,terminated_pixels,full_blocks;
    logic[63:0]mask;begin
      if(epoch_id_o==0)$fatal(1,"checkpoint restore requires a live epoch");
      terminated_pixels=0;full_blocks=0;
      for(by=0;by<(height+7)/8;by=by+1)begin
        for(bx=0;bx<(width+7)/8;bx=bx+1)begin
          block_id=by*((width+7)/8)+bx;mask='0;
          for(y=by*8;y<height&&y<(by+1)*8;y=y+1)
            for(x=bx*8;x<width&&x<(bx+1)*8;x=x+1)
              if(state_mem[y*width+x][39+:16]<=16'd7)
                begin mask[((y&7)*8)+(x&7)]=1'b1;terminated_pixels=terminated_pixels+1;end
          if(mask!='0)begin
            mask_index=block_id&255;
            dut.u_frame.u_render.u_render.u_raster.u_raster.u_pixel_termination_mask.valid_mem[mask_index]=1'b1;
            dut.u_frame.u_render.u_render.u_raster.u_raster.u_pixel_termination_mask.tag_mem[mask_index]=block_id;
            dut.u_frame.u_render.u_render.u_raster.u_raster.u_pixel_termination_mask.epoch_mem[mask_index]=epoch_id_o;
            dut.u_frame.u_render.u_render.u_raster.u_raster.u_pixel_termination_mask.mask_mem[mask_index]=mask;
          end
          if(&mask)begin
            full_blocks=full_blocks+1;
            row=(block_id>>2)&255;
            case(block_id&3)
              0:begin
                dut.u_frame.u_render.u_render.u_raster.u_raster.u_termination_filter.u_table.g_bank[0].u_bank.valid_mem[row]=1'b1;
                dut.u_frame.u_render.u_render.u_raster.u_raster.u_termination_filter.u_table.g_bank[0].u_bank.tag_mem[row]=block_id;
                dut.u_frame.u_render.u_render.u_raster.u_raster.u_termination_filter.u_table.g_bank[0].u_bank.epoch_mem[row]=epoch_id_o;
              end
              1:begin
                dut.u_frame.u_render.u_render.u_raster.u_raster.u_termination_filter.u_table.g_bank[1].u_bank.valid_mem[row]=1'b1;
                dut.u_frame.u_render.u_render.u_raster.u_raster.u_termination_filter.u_table.g_bank[1].u_bank.tag_mem[row]=block_id;
                dut.u_frame.u_render.u_render.u_raster.u_raster.u_termination_filter.u_table.g_bank[1].u_bank.epoch_mem[row]=epoch_id_o;
              end
              2:begin
                dut.u_frame.u_render.u_render.u_raster.u_raster.u_termination_filter.u_table.g_bank[2].u_bank.valid_mem[row]=1'b1;
                dut.u_frame.u_render.u_render.u_raster.u_raster.u_termination_filter.u_table.g_bank[2].u_bank.tag_mem[row]=block_id;
                dut.u_frame.u_render.u_render.u_raster.u_raster.u_termination_filter.u_table.g_bank[2].u_bank.epoch_mem[row]=epoch_id_o;
              end
              default:begin
                dut.u_frame.u_render.u_render.u_raster.u_raster.u_termination_filter.u_table.g_bank[3].u_bank.valid_mem[row]=1'b1;
                dut.u_frame.u_render.u_render.u_raster.u_raster.u_termination_filter.u_table.g_bank[3].u_bank.tag_mem[row]=block_id;
                dut.u_frame.u_render.u_render.u_raster.u_raster.u_termination_filter.u_table.g_bank[3].u_bank.epoch_mem[row]=epoch_id_o;
              end
            endcase
          end
        end
      end
      $display("REAL_CHECKPOINT_RESTORE epoch=%0d terminated_pixels=%0d full_blocks=%0d",
        epoch_id_o,terminated_pixels,full_blocks);
      if(terminated_pixels>0&&
         !dut.u_frame.u_render.u_render.u_raster.u_raster.u_pixel_termination_mask.valid_mem[0])
        $fatal(1,"checkpoint termination mask writeback was not observable");
    end
  endtask
  initial begin integer timeout,i,frame_file,first_width,first_height;
    if(!$value$plusargs("MEAN=%s",mean_path))begin end
    if(!$value$plusargs("ATTR=%s",attr_path))begin end
    if($value$plusargs("GLOBAL_GIDS=%s",global_gid_path))sparse_global_gid_mode=1;
    if($value$plusargs("MEAN2=%s",mean2_path))two_batch_mode=1;
    if(two_batch_mode)begin
      if(!$value$plusargs("ATTR2=%s",attr2_path))$fatal(1,"MEAN2 requires ATTR2");
      if(!$value$plusargs("GLOBAL_GIDS2=%s",global_gid2_path))$fatal(1,"MEAN2 requires GLOBAL_GIDS2");
      if(!$value$plusargs("CAMERA2=%s",camera2_path))$fatal(1,"MEAN2 requires CAMERA2");
      if(!sparse_global_gid_mode)$fatal(1,"two-batch mode requires GLOBAL_GIDS for batch 0");
    end
    if($value$plusargs("BATCH_ROOT=%s",batch_root_path))begin
      batch_list_mode=1;sparse_global_gid_mode=1;two_batch_mode=0;
      if(!$value$plusargs("BATCH_FIRST=%d",batch_first_index))batch_first_index=0;
      if(!$value$plusargs("BATCH_LAST=%d",batch_last_index))
        $fatal(1,"BATCH_ROOT requires BATCH_LAST");
      if(batch_first_index<0||batch_last_index<batch_first_index)
        $fatal(1,"invalid batch range %0d..%0d",batch_first_index,batch_last_index);
      batch_list_count=batch_last_index-batch_first_index+1;
      mean_path=$sformatf("%s/rtl_batch_%04d/mean.memh",batch_root_path,batch_first_index);
      attr_path=$sformatf("%s/rtl_batch_%04d/attribute_sparse.memh",batch_root_path,batch_first_index);
      global_gid_path=$sformatf("%s/rtl_batch_%04d/global_gid.memh",batch_root_path,batch_first_index);
      camera_path=$sformatf("%s/rtl_batch_%04d/camera.memh",batch_root_path,batch_first_index);
      batch_control=batch_list_count>1?32'h11:32'h1;
    end
    if($value$plusargs("STATE_IN=%s",state_in_path))state_in_mode=1;
    if(!$value$plusargs("CAMERA=%s",camera_path))begin end
    if(!$value$plusargs("FRAME=%s",frame_path))begin end
    if(!$value$plusargs("RGB=%s",rgb_path))begin end
    if($value$plusargs("SORTED_TRACE=%s",sorted_trace_path))begin
      sorted_trace_file=$fopen(sorted_trace_path,"w");if(sorted_trace_file==0)$fatal(1,"cannot open sort trace");end
    if(`TB_FINAL_RGB&&rgb_path=="")$fatal(1,"final RGB test requires +RGB output path");
    if(!$value$plusargs("LABEL=%s",workload_label))begin end
    if(!$value$plusargs("READ_LATENCY=%d",read_latency))begin end
    if(!$value$plusargs("READ_GAP=%d",read_gap))begin end
    if(!$value$plusargs("READY_PERIOD=%d",ready_period))begin end
    if(!$value$plusargs("READY_LOW=%d",ready_low))begin end
    if(!$value$plusargs("WRITE_RESPONSE_LATENCY=%d",write_response_latency))begin end
    if(!$value$plusargs("FRAME_MODE=%d",frame_mode))begin end
    if(!$value$plusargs("MAX_TIMEOUT=%d",max_timeout))begin end
    if(!$value$plusargs("PROJECTION_TRACE_LIMIT=%d",projection_trace_limit))begin end
    if(!$value$plusargs("COVARIANCE_TRACE_LIMIT=%d",covariance_trace_limit))begin end
    auto_mode=$test$plusargs("AUTO_MODE");
    if(!$value$plusargs("AUTO_REPEAT_FRAMES=%d",auto_repeat_frames))begin end
    advisor_trace=auto_mode||$test$plusargs("ADVISOR_TRACE");
    state_trace=$test$plusargs("STATE_TRACE");
    if(ready_period<1||ready_low<0||ready_low>=ready_period)$fatal(1,"invalid ready duty cycle");
    if(read_latency<0||read_gap<0||write_response_latency<0)$fatal(1,"negative AXI delay");
    if(frame_mode<0||frame_mode>3)$fatal(1,"invalid frame mode %0d",frame_mode);
    if(auto_repeat_frames<1||auto_repeat_frames>2)$fatal(1,"AUTO_REPEAT_FRAMES must be 1 or 2");
    if(auto_repeat_frames>1&&!auto_mode)$fatal(1,"repeated frames require AUTO_MODE");
    if(auto_repeat_frames>1&&(batch_list_mode||two_batch_mode||state_in_mode))
      $fatal(1,"automatic repeated-frame probe supports one self-contained batch only");
    $readmemh(camera_path,camera_mem);
    load_camera_config();first_workload_count=workload_count;first_width=workload_width;first_height=workload_height;
    rgb_stride=(workload_width*3+15)&~15;rgb_bytes=rgb_stride*workload_height;
    for(i=0;i<rgb_bytes;i=i+1)rgb_mem[i]=8'ha5;
    $readmemh(mean_path,mean_mem,0,workload_count-1);
    $readmemh(attr_path,attr_mem,0,workload_count*9-1);
    if(sparse_global_gid_mode)$readmemh(global_gid_path,global_gid_mem,0,workload_count-1);
    validate_sparse_batch(workload_count);
    for(i=0;i<MAX_PIXELS;i=i+1)state_mem[i]=0;
    if(state_in_mode&&`TB_PIXEL_TERMINATION_SKIP)$fatal(1,"T07 candidate does not accept TB-injected termination state; use real production frames");
    if(state_in_mode)$readmemh(state_in_path,state_mem,0,workload_width*workload_height-1);
    repeat(3)tick();rst_ni=1;tick();
    apb_write(12'h010,MEAN_BASE[31:0]);apb_write(12'h014,0);
    apb_write(12'h018,CAMERA_BASE[31:0]);apb_write(12'h01c,0);
    if(!$value$plusargs("ATTR_FORMAT=%d",t08_format))t08_format=0;
    apb_write(12'h0f0,t08_format);
    apb_write(12'h03c,ATTR_BASE[31:0]);apb_write(12'h040,0);
    apb_write(12'h020,OUTPUT_BASE[31:0]);apb_write(12'h024,0);apb_write(12'h038,workload_count);
    apb_write(12'h028,{workload_height[15:0],workload_width[15:0]});
    qsu_requested=$test$plusargs("AUTO_QSU");
    if(qsu_requested)begin
      if(batch_list_mode||two_batch_mode)$fatal(1,"autonomous test cannot use host batches");
      apb_write(12'h0c0,1);apb_write(12'h0c4,QSU_BASE[31:0]);apb_write(12'h0c8,0);
      apb_write(12'h0cc,workload_count);
      apb_write(12'h02c,3);
    end
    // In automatic mode, seed the first frame through the normal runtime
    // shadow/commit path before enabling the advisor.  This guarantees that
    // FRAME_MODE is the observation mode even though AUTO_MODE subsequently
    // owns frame selection.
    if(auto_mode)begin
      apb_write(12'h008,32'h100|frame_mode[1:0]);
      apb_write(12'h044,32'h1);
    end else apb_write(12'h008,frame_mode[1:0]);
    apb_write(12'h000,batch_list_mode?batch_control:(two_batch_mode?32'h11:32'h1));
    if($test$plusargs("MUTATE_FORMAT"))apb_write(12'h0f0,2);
    if(state_in_mode)begin
      while(epoch_id_o==0)tick();
      @(negedge clk_i);#1;restore_checkpoint_termination(workload_width,workload_height);
    end
    timeout=0;
    if(batch_list_mode)begin
      total_workload_count=workload_count;
      for(batch_list_index=0;batch_list_index<batch_list_count;batch_list_index=batch_list_index+1)begin
        timeout=0;
        if(batch_control[4])begin
          while(!frame_busy_o&&timeout<max_timeout)begin
            if(frame_done_pulse_o)$fatal(1,"intermediate list batch %0d raised done",batch_list_index);
            tick();timeout=timeout+1;
          end
          while(frame_busy_o&&timeout<max_timeout)begin
            if(frame_done_pulse_o)$fatal(1,"intermediate list batch %0d raised done",batch_list_index);
            tick();timeout=timeout+1;
          end
          if(timeout>=max_timeout)$fatal(1,"list batch %0d timed out",batch_list_index);
          if(frame_done_pulse_o||dut.done_sticky_q)
            $fatal(1,"intermediate list batch %0d exposed completion",batch_list_index);
          if(!dut.logical_frame_open_q)$fatal(1,"logical frame closed after list batch %0d",batch_list_index);
          if(batch_list_index==0)first_batch_epoch=epoch_id_o;
          else if(epoch_id_o!=first_batch_epoch)
            $fatal(1,"list continuation changed epoch from %0d to %0d",first_batch_epoch,epoch_id_o);
          if(batch_list_index+1>=batch_list_count)
            $fatal(1,"last list batch incorrectly advertises more_batches");
          mean_path=$sformatf("%s/rtl_batch_%04d/mean.memh",batch_root_path,
            batch_first_index+batch_list_index+1);
          attr_path=$sformatf("%s/rtl_batch_%04d/attribute_sparse.memh",batch_root_path,
            batch_first_index+batch_list_index+1);
          global_gid_path=$sformatf("%s/rtl_batch_%04d/global_gid.memh",batch_root_path,
            batch_first_index+batch_list_index+1);
          camera_path=$sformatf("%s/rtl_batch_%04d/camera.memh",batch_root_path,
            batch_first_index+batch_list_index+1);
          batch_control=(batch_list_index+2==batch_list_count)?32'h9:32'h19;
          $readmemh(camera_path,camera_mem);load_camera_config();
          if(workload_width!=first_width||workload_height!=first_height)
            $fatal(1,"continuation image dimensions changed from %0dx%0d to %0dx%0d",
              first_width,first_height,workload_width,workload_height);
          $readmemh(mean_path,mean_mem,0,workload_count-1);
          $readmemh(attr_path,attr_mem,0,workload_count*9-1);
          $readmemh(global_gid_path,global_gid_mem,0,workload_count-1);
          validate_sparse_batch(workload_count);
          total_workload_count=total_workload_count+workload_count;
          apb_write(12'h038,workload_count);apb_write(12'h000,batch_control);
        end else begin
          if(batch_list_index+1!=batch_list_count)$fatal(1,"early final list batch %0d",batch_list_index);
          while(!frame_done_pulse_o&&timeout<max_timeout)begin tick();timeout=timeout+1;end
          if(timeout>=max_timeout)$fatal(1,"final list batch %0d timed out",batch_list_index);
          if(first_batch_epoch!=0&&epoch_id_o!=first_batch_epoch)
            $fatal(1,"final list continuation changed epoch from %0d to %0d",first_batch_epoch,epoch_id_o);
          if(dut.logical_frame_open_q)$fatal(1,"final list batch left logical frame open");
        end
      end
    end else if(two_batch_mode)begin
      while(!frame_busy_o&&timeout<max_timeout)begin
        if(frame_done_pulse_o)$fatal(1,"intermediate continuation batch raised done");
        tick();timeout=timeout+1;
      end
      while(frame_busy_o&&timeout<max_timeout)begin
        if(frame_done_pulse_o)$fatal(1,"intermediate continuation batch raised done");
        tick();timeout=timeout+1;
      end
      if(timeout>=max_timeout)$fatal(1,"first continuation batch timed out");
      if(frame_done_pulse_o||dut.done_sticky_q)$fatal(1,"intermediate continuation batch exposed completion");
      if(!dut.logical_frame_open_q)$fatal(1,"logical frame closed after intermediate batch");
      first_batch_epoch=epoch_id_o;
      if(first_batch_epoch==0)$fatal(1,"fresh continuation batch did not create an epoch");
      $readmemh(camera2_path,camera_mem);load_camera_config();
      if(workload_width!=first_width||workload_height!=first_height)
        $fatal(1,"continuation image dimensions changed from %0dx%0d to %0dx%0d",
          first_width,first_height,workload_width,workload_height);
      $readmemh(mean2_path,mean_mem,0,workload_count-1);
      $readmemh(attr2_path,attr_mem,0,workload_count*9-1);
      $readmemh(global_gid2_path,global_gid_mem,0,workload_count-1);
      validate_sparse_batch(workload_count);
      total_workload_count=first_workload_count+workload_count;
      apb_write(12'h038,workload_count);
      apb_write(12'h000,32'h9);
      timeout=0;while(!frame_done_pulse_o&&timeout<max_timeout)begin tick();timeout=timeout+1;end
      if(epoch_id_o!=first_batch_epoch)$fatal(1,"continuation changed epoch from %0d to %0d",first_batch_epoch,epoch_id_o);
      if(dut.logical_frame_open_q)$fatal(1,"final continuation batch left logical frame open");
    end else begin
      total_workload_count=workload_count;
      while(!frame_done_pulse_o&&timeout<max_timeout)begin tick();timeout=timeout+1;end
      if(auto_mode)begin
        auto_observe_cycles=perf_cycle_count_o;auto_observe_mode=active_mode_o;
        apb_read(12'h044,auto_status);
        auto_recommendation_valid=auto_status[1];auto_recommended_mode=auto_status[3:2];
        auto_window_winner=auto_status[5:4];
        auto_observe_windows=dut.advisor_window_index;
        for(i=0;i<workload_width*workload_height;i=i+1)
          auto_observe_render_mem[i]=state_mem[i][54:0];
        if(auto_repeat_frames==2)begin
          first_batch_epoch=epoch_id_o;
          auto_observe_state_reads=state_reads;auto_observe_state_writes=state_writes;
          apb_write(12'h000,32'h4);apb_write(12'h000,32'h1);
          timeout=0;while(epoch_id_o==first_batch_epoch&&timeout<max_timeout)begin tick();timeout=timeout+1;end
          if(timeout>=max_timeout)$fatal(1,"automatic selected frame did not create a new epoch");
          auto_selected_mode=active_mode_o;
          if(auto_recommendation_valid&&auto_selected_mode!=auto_recommended_mode)
            $fatal(1,"automatic recommendation did not commit expected=%0d got=%0d",
              auto_recommended_mode,auto_selected_mode);
          timeout=0;while(!frame_done_pulse_o&&timeout<max_timeout)begin tick();timeout=timeout+1;end
          if(timeout>=max_timeout)$fatal(1,"automatic selected frame timed out");
          auto_selected_cycles=perf_cycle_count_o;auto_image_mismatches=0;
          for(i=0;i<workload_width*workload_height;i=i+1)
            if(state_mem[i][54:0]!==auto_observe_render_mem[i])auto_image_mismatches=auto_image_mismatches+1;
          if(auto_image_mismatches!=0)
            $fatal(1,"automatic mode changed rendered RGB/T pixels=%0d",auto_image_mismatches);
          total_workload_count=workload_count*2;
          $display("REAL_AUTO observe_mode=%0d observe_cycles=%0d recommendation_valid=%0d recommended_mode=%0d window_winner=%0d observe_windows=%0d total_windows=%0d selected_mode=%0d selected_cycles=%0d image_mismatches=%0d",
            auto_observe_mode,auto_observe_cycles,auto_recommendation_valid,auto_recommended_mode,
            auto_window_winner,auto_observe_windows,dut.advisor_window_index,auto_selected_mode,auto_selected_cycles,
            auto_image_mismatches);
        end else
          $display("REAL_AUTO observe_mode=%0d observe_cycles=%0d recommendation_valid=%0d recommended_mode=%0d window_winner=%0d observe_windows=%0d total_windows=%0d selected_mode=%0d selected_cycles=%0d image_mismatches=%0d",
            auto_observe_mode,auto_observe_cycles,auto_recommendation_valid,auto_recommended_mode,
            auto_window_winner,auto_observe_windows,dut.advisor_window_index,auto_observe_mode,auto_observe_cycles,0);
      end
    end
    tick();
    if(auto_mode&&auto_repeat_frames==2)begin
      reported_state_reads=state_reads-auto_observe_state_reads;
      reported_state_writes=state_writes-auto_observe_state_writes;
    end else begin
      reported_state_reads=state_reads;reported_state_writes=state_writes;
    end
    if(timeout>=max_timeout)begin
      $display("TIMEOUT busy=%b core_state=%0d group_state=%0d state_read=%0d write=%0d mean=%0d attr=%0d",
        frame_busy_o,dut.u_frame.state_q,dut.u_frame.u_group.state_q,
        dut.state_read_busy,dut.write_busy,
        dut.g_axi_mean.u_mean_dma.state_q,dut.g_t08_attr.u_attr_dma.state_q);
      $display("TIMEOUT perf cycles=%0d commits=%0d misses=%0d reads=%0d writes=%0d mean_beats=%0d attr_beats=%0d",
        perf_cycle_count_o,perf_commit_count_o,perf_state_miss_count_o,state_reads,state_writes,mean_beats,attr_beats);
      $display("TIMEOUT drain group_busy=%b sort_busy=%b render_idle=%b mode_pending=%b sorted=%b/%b group=%b/%b",
        dut.u_frame.group_busy,dut.u_frame.sort_busy,dut.u_frame.render_idle,dut.u_frame.render_mode_pending,
        dut.u_frame.sorted_valid,dut.u_frame.sorted_ready,dut.u_frame.group_valid,dut.u_frame.group_ready);
      $display("TIMEOUT render issue_idle=%b ordered_idle=%b front_idle=%b raster_idle=%b block_valid=%b inflight=%0d alpha_idle=%b cache_idle=%b",
        dut.u_frame.u_render.issue_idle,dut.u_frame.u_render.render_idle,
        dut.u_frame.u_render.u_render.front_idle,dut.u_frame.u_render.u_render.raster_idle,
        dut.u_frame.u_render.u_render.block_valid,
        dut.u_frame.u_render.u_render.u_raster.u_raster.inflight_count_q,
        dut.u_frame.u_render.u_render.u_raster.u_raster.alpha_array_idle,
        dut.u_frame.u_render.u_render.u_raster.u_raster.state_cache_idle_o);
      $display("TIMEOUT protocol blend_occ=%0d cache_mshr=%0d query=%b/%b response=%b/%b update=%b miss_req=%b/%b miss_rsp=%b/%b commit=%b/%b",
        debug_blend_count,
        debug_cache_mshr_valid,
        dut.u_frame.u_render.u_render.u_raster.u_raster.state_query_valid,
        dut.u_frame.u_render.u_render.u_raster.u_raster.state_query_ready,
        dut.u_frame.u_render.u_render.u_raster.u_raster.state_response_valid,
        dut.u_frame.u_render.u_render.u_raster.u_raster.state_response_ready,
        dut.u_frame.u_render.u_render.u_raster.u_raster.state_update_valid,
        dut.state_miss_req_valid,dut.state_miss_req_ready,dut.state_miss_rsp_valid,dut.state_miss_rsp_ready,
        commit_valid_o,commit_ready_i);
      $display("TIMEOUT state cache_valid=%b issued=%b axi_ar=%b id=%0d axi_r=%b/%b rid=%0d tb_pending=%0d,%0d delay=%0d,%0d",
        debug_cache_mshr_valid,debug_cache_mshr_issued,
        m_axi_state_arvalid_o,m_axi_state_arid_o,m_axi_state_rvalid_i,m_axi_state_rready_o,m_axi_state_rid_i,
        state_pending[0],state_pending[1],state_delay[0],state_delay[1]);
      $display("TIMEOUT alpha seq_in=%0d seq_out=%0d valid=%b/%b ordered_outstanding=%0d retire_count=%0d lane=%b/%b blend_core=%b/%b",
        dut.u_frame.u_render.u_render.u_raster.u_raster.alpha_sequence_q,
        dut.u_frame.u_render.u_render.u_raster.u_raster.alpha_result_sequence,
        dut.u_frame.u_render.u_render.u_raster.u_raster.alpha_valid,
        dut.u_frame.u_render.u_render.u_raster.u_raster.alpha_ready,
        dut.u_frame.u_render.u_render.u_raster.u_raster.u_alpha_array.u_order.outstanding_o,
        dut.u_frame.u_render.u_render.u_raster.u_raster.u_alpha_array.u_order.u_retire.count_q,
        dut.u_frame.u_render.u_render.u_raster.u_raster.u_alpha_array.lane_m_valid,
        dut.u_frame.u_render.u_render.u_raster.u_raster.u_alpha_array.lane_m_ready,
        debug_blend_out_valid,debug_blend_out_ready);
      $display("TIMEOUT frontend source_count=%0d fork_empty=%b fork_occ=%0d proj_idle=%b proj=%b/%b proj_last=%b sh_idle=%b sh=%b/%b sh_occ=%0d join_empty=%b join=%b/%b join_last=%b",
        dut.u_frame.u_render.u_render.u_front.source_count_q,
        dut.u_frame.u_render.u_render.u_front.fork_empty,
        dut.u_frame.u_render.u_render.u_front.fork_occupancy,
        dut.u_frame.u_render.u_render.u_front.projection_idle,
        dut.u_frame.u_render.u_render.u_front.projection_valid,
        dut.u_frame.u_render.u_render.u_front.projection_ready,
        dut.u_frame.u_render.u_render.u_front.projection_last,
        dut.u_frame.u_render.u_render.u_front.sh_array_idle,
        dut.u_frame.u_render.u_render.u_front.sh_result_valid,
        dut.u_frame.u_render.u_render.u_front.sh_result_ready,
        dut.u_frame.u_render.u_render.u_front.sh_occupancy,
        dut.u_frame.u_render.u_render.u_front.join_empty,
        dut.u_frame.u_render.u_render.u_front.join_valid,
        dut.u_frame.u_render.u_render.block_ready,
        dut.u_frame.u_render.u_render.u_front.join_last);
      $display("TIMEOUT projection active=%b lane_idle=%b retire_count=%0d lane_inflight=%0d lane_out=%b/%b/%b culled=%b",
        dut.u_frame.u_render.u_render.u_front.u_projection.u_scheduler.active_mask_o,
        dut.u_frame.u_render.u_render.u_front.u_projection.lane_idle,
        dut.u_frame.u_render.u_render.u_front.u_projection.u_scheduler.u_retire.count_q,
        dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[0].u_lane.inflight_count_q,
        dut.u_frame.u_render.u_render.u_front.u_projection.lane_task_valid[0],
        dut.u_frame.u_render.u_render.u_front.u_projection.lane_task_ready[0],
        dut.u_frame.u_render.u_render.u_front.u_projection.lane_task_last[0],
        dut.u_frame.u_render.u_render.u_front.u_projection.lane_culled[0]);
      $fatal(1,"real workload timed out");
    end
    if(frame_error_o)$fatal(1,"real workload error %h",frame_error_status_o);
    if(!auto_mode&&active_mode_o!==frame_mode[1:0])
      $fatal(1,"requested frame mode %0d but active mode is %0d",frame_mode,active_mode_o);
    if(mean_beats!=total_workload_count||64'(attr_beats)!=t08_expected_beats)
      $fatal(1,"DMA beat mismatch mean=%0d attr=%0d expected_gaussians=%0d",mean_beats,attr_beats,total_workload_count);
    if(perf_commit_count_o==0||reported_state_writes==0)$fatal(1,"real workload produced no pixel state");
    if(perf_state_miss_count_o<reported_state_reads)$fatal(1,"AXI reads exceed cache misses %0d %0d",perf_state_miss_count_o,reported_state_reads);
    if(!`TB_USE_WRITEBACK&&!(`TB_USE_MULTIWRITE&&`TB_MULTIWRITE_FORWARDING)&&
       perf_state_miss_count_o!=reported_state_reads)
      $fatal(1,"write-through state miss/read mismatch %0d %0d",perf_state_miss_count_o,reported_state_reads);
    if(`TB_USE_MULTIWRITE&&`TB_MULTIWRITE_FORWARDING&&perf_state_miss_count_o<reported_state_reads)
      $fatal(1,"forwarding path observed more AXI reads than accepted state misses %0d %0d",
        perf_state_miss_count_o,reported_state_reads);
    if(projection_inactive_issue_count||sh_inactive_issue_count||raster_inactive_issue_count)
      $fatal(1,"disabled lane accepted work p=%0d sh=%0d r=%0d",projection_inactive_issue_count,
        sh_inactive_issue_count,raster_inactive_issue_count);
    if(`TB_USE_SHARED_PE&&`TB_USE_SHARED_PROJECTION_PE&&shared_main_mac_grants!=(`TB_SHARED_P_DOT3?3:9)*projection_issue_count)
      $fatal(1,"shared main projection MAC accounting grants=%0d issued=%0d",shared_main_mac_grants,projection_issue_count);
    frame_file=$fopen(frame_path,"w");if(frame_file==0)$fatal(1,"cannot open frame output %s",frame_path);
    for(i=0;i<workload_width*workload_height;i=i+1)$fdisplay(frame_file,"%032h",state_mem[i]);
    $fclose(frame_file);
    if(`TB_FINAL_RGB)begin
      if(`TB_BITONIC_SORT&&(dut.shared_pe_group_grant_count_q==0||dut.shared_pe_projection_grant_count_q==0||
        (`TB_USE_SHARED_RASTER_PE&&dut.shared_pe_raster_grant_count_q==0)))$fatal(1,"T05 shared path was not exercised");
      if(b_put!=b_get||rgb_beats_left!=0||m_axi_out_bvalid_i)$fatal(1,"DONE before last RGB response");
      if(rgb_write_beats*16!=rgb_bytes*auto_repeat_frames||rgb_read_count!=workload_width*workload_height*auto_repeat_frames)
        $fatal(1,"incomplete RGB scan/output reads=%0d beats=%0d bytes=%0d",rgb_read_count,rgb_write_beats,rgb_bytes);
      frame_file=$fopen(rgb_path,"w");if(frame_file==0)$fatal(1,"cannot open RGB dump");
      for(i=0;i<rgb_bytes;i=i+1)$fdisplay(frame_file,"%02h",rgb_mem[i]);
      $fclose(frame_file);
      $display("REAL_RGB reads=%0d write_beats=%0d bursts=%0d bytes=%0d epoch=%0d error=%h",
        rgb_read_count,rgb_write_beats,rgb_bursts,rgb_bytes,epoch_id_o,frame_error_status_o);
    end
    report_sort_snapshot();
    if(qsu_requested)begin
      if(!irq_o||!dut.done_sticky_q)$fatal(1,"QSU completion/IRQ missing");
      if(!dut.cmd_qsu_enable_q||dut.qsu_stats[31:0]==0||qsu_write_count==0||qsu_read_count==0)$fatal(1,"QSU bypassed");
      if(qsu_b_get!=qsu_aw_put||qsu_b_get!=qsu_w_put||qsu_read_left!=0||dut.qsu_rd_busy||dut.qsu_wr_busy)$fatal(1,"QSU not drained at DONE");
      $display("REAL_QSU enabled=1 input=%0d partitions=%0d leaves=%0d reads=%0d writes=%0d stalls=%0d peak=%0d axi_reads=%0d axi_writes=%0d",
        dut.qsu_stats[0+:32],dut.qsu_stats[32+:32],dut.qsu_stats[64+:32],dut.qsu_stats[96+:32],dut.qsu_stats[128+:32],dut.qsu_stats[160+:32],dut.qsu_stats[192+:32],qsu_read_count,qsu_write_count);
    end
    if(sorted_trace_file!=0)$fclose(sorted_trace_file);
    $display("REAL_WORKLOAD label=%s gaussians=%0d resolution=%0dx%0d read_latency=%0d read_gap=%0d ready=%0d/%0d write_response_latency=%0d",
      workload_label,total_workload_count,workload_width,workload_height,read_latency,read_gap,ready_period-ready_low,ready_period,write_response_latency);
    $display("REAL_CONTINUATION enabled=%0d batches=%0d first_count=%0d second_count=%0d epoch=%0d state_in=%0d",
      two_batch_mode||batch_list_mode,batch_list_mode?batch_list_count:(two_batch_mode?2:1),
      first_workload_count,two_batch_mode?workload_count:0,epoch_id_o,state_in_mode);
    $display("REAL_PERF cycles=%0d commits=%0d state_misses=%0d read_stall=%0d output_stall=%0d state_reads=%0d state_writes=%0d",
      perf_cycle_count_o,perf_commit_count_o,perf_state_miss_count_o,perf_state_read_stall_count_o,
      perf_output_stall_count_o,reported_state_reads,reported_state_writes);
    $display("REAL_ALPHA_SKIP enabled=%0d skipped=%0d",
      `TB_ENABLE_ALPHA_ZERO_SKIP,
      dut.u_frame.u_render.u_render.u_raster.u_raster.alpha_skipped_count_q);
    $display("REAL_SHARED_PE enabled=%0d main_projection=%0d G=%0d P=%0d R=%0d G_stall=%0d P_stall=%0d R_stall=%0d utilization=%0d competing=%0d main_mac=%0d",
      `TB_USE_SHARED_PE,`TB_USE_SHARED_PE&&`TB_USE_SHARED_PROJECTION_PE,
      dut.shared_pe_group_grant_count_q,dut.shared_pe_projection_grant_count_q,dut.shared_pe_raster_grant_count_q,
      dut.shared_pe_group_stall_count_q,dut.shared_pe_projection_stall_count_q,dut.shared_pe_raster_stall_count_q,
      dut.shared_pe_utilization_count_q,shared_competing_cycles,shared_main_mac_grants);
    $display("REAL_WRITEBACK enabled=%0d depth=%0d coalesced=%0d forwarded_reads=%0d",
      `TB_USE_WRITEBACK,`TB_WRITEBACK_DEPTH,dut.write_coalesced_count,
      perf_state_miss_count_o-reported_state_reads);
    $display("REAL_MULTIWRITE enabled=%0d depth=%0d peak_outstanding=%0d",
      `TB_USE_MULTIWRITE,`TB_MULTIWRITE_DEPTH,dut.write_multi_peak);
    $display("REAL_WRITE_LOCALITY consecutive_same_pixel_commits=%0d",consecutive_same_pixel_commits);
    $display("REAL_STAGE mode=%0d lanes=%0d collect=%0d drain=%0d group_busy=%0d sort_busy=%0d attr_wait=%0d projection_busy=%0d sh_busy=%0d raster_busy=%0d overlap=%0d sorted_bp=%0d block_bp=%0d retire_wait=%0d state_cache_busy=%0d window_wait=%0d window_same=%0d window_diff=%0d group_active=%0d group_service_stall=%0d",
      active_mode_o,LANES,collect_cycles,drain_cycles,group_busy_cycles,sort_busy_cycles,
      attr_wait_cycles,projection_busy_cycles,sh_busy_cycles,raster_busy_cycles,
      projection_raster_overlap_cycles,sorted_backpressure_cycles,block_backpressure_cycles,
      retire_wait_cycles,state_cache_busy_cycles,state_window_wait_cycles,
      state_window_same_key_cycles,state_window_different_key_cycles,
      dut.u_frame.group_active_lanes,group_service_stall_cycles);
    $display("REAL_RECONFIG projection_mask=%0h sh_mask=%0h raster_mask=%0h projection_issue=%0d sh_issue=%0d raster_issue=%0d projection_inactive_issue=%0d sh_inactive_issue=%0d raster_inactive_issue=%0d",
      projection_active_mask_o,sh_active_mask_o,raster_active_mask_o,projection_issue_count,
      sh_issue_count,raster_issue_count,projection_inactive_issue_count,sh_inactive_issue_count,
      raster_inactive_issue_count);
    $display("REAL_SHAPE enabled=%0d rejected_blocks=%0d",`TB_ENABLE_SHAPE_BLOCK_REJECT,shape_block_reject_count);
    $display("REAL_BACKEND mshr_count=%0d blend_full=%0d mshr_zero=%0d mshr_one=%0d mshr_two=%0d mshr_full_query_block=%0d cache_rsp_block=%0d miss_issue_block=%0d ar_stall=%0d r_stall=%0d reader_rsp_block=%0d",
      `TB_STATE_MSHR_COUNT,blend_window_full_cycles,mshr_zero_cycles,mshr_one_cycles,mshr_two_cycles,
      mshr_full_query_block_cycles,cache_response_block_cycles,miss_issue_block_cycles,
      state_ar_stall_cycles,state_r_stall_cycles,reader_response_block_cycles);
    $display("REAL_WINDOW_OPP third_candidate=%0d third_mshr_two=%0d third_mshr_one=%0d third_distinct=%0d third_distinct_mshr_two=%0d third_raw=%0d head_need_query=%0d head_wait_rsp=%0d head_need_blend=%0d head_wait_blend=%0d head_done_blocked=%0d",
      third_candidate_cycles,third_with_two_mshr_cycles,third_with_one_mshr_cycles,
      third_distinct_key_cycles,third_distinct_with_two_mshr_cycles,third_raw_hazard_cycles,
      head_need_query_cycles,head_wait_response_cycles,head_need_blend_cycles,
      head_wait_blend_cycles,head_done_blocked_cycles);
    $display("REAL_BLEND_BYPASS enabled=%0d fires=%0d",`TB_RESPONSE_BLEND_BYPASS,
      response_blend_bypass_count);
    $display("REAL_COMMIT_BYPASS enabled=%0d fires=%0d",`TB_BLEND_COMMIT_BYPASS,
      blend_commit_bypass_count);
    // Word-level operand exposure proxy: before isolation every changing
    // packet was broadcast to all physical arithmetic lanes; now only the
    // selected lane receives it.  This is not a library power estimate.
    $display("REAL_OPERAND_ISOLATION enabled=%0d broadcast_exposures=%0d isolated_exposures=%0d avoided_exposures=%0d",
      `TB_OPERAND_ISOLATION,
      LANES*(projection_issue_count+sh_issue_count+raster_issue_count),
      `TB_OPERAND_ISOLATION?(projection_issue_count+sh_issue_count+raster_issue_count):
        LANES*(projection_issue_count+sh_issue_count+raster_issue_count),
      `TB_OPERAND_ISOLATION?((LANES-1)*(projection_issue_count+sh_issue_count+raster_issue_count)):0);
    if(t07_accepted!=t07_issued+t07_skipped)$fatal(1,"T07 task accounting not drained");
    $display("REAL_T07_TERMINATION enabled=%0d accepted=%0d alpha_issued=%0d skipped=%0d updates=%0d full_blocks=%0d",
      `TB_PIXEL_TERMINATION_SKIP,t07_accepted,t07_issued,t07_skipped,t07_updates,t07_full_blocks);
    begin
      longint unsigned observed;observed=0;
      for(integer l=0;l<LANES;l++)observed+=t08_world_pre[l];
      if(observed!=t08_precomputed||(t08_format==1&&observed==0))$fatal(1,"T08 precompute path missing or tag accounting mismatch");
      $display("REAL_T08 format=%0d requests=%0d expected_beats=%0d precomputed=%0d world_precomputed=%0d",t08_format,t08_requests,t08_expected_beats,t08_precomputed,observed);
    end
    $display("PASS: tb_t08_integrated");$finish;
  end
endmodule
