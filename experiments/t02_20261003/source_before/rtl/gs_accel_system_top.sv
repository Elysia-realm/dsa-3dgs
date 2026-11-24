// APB-controlled system integration boundary around the complete frame render
// data path. Attribute preload and mean-stream ports are explicit DMA seams;
// they will be replaced by AXI4 engines without changing command/status RTL.
module gs_accel_system_top #(
    parameter int unsigned APB_ADDR_W=12,parameter int unsigned ATTR_DEPTH=1024,
    parameter int unsigned LANES=4,parameter int unsigned GROUP_CAPACITY=8,
    parameter int unsigned SORT_CAPACITY=8,parameter int unsigned STATE_ENTRIES=4096,
    parameter int unsigned GID_W=32,parameter int unsigned SEQ_W=16,
    parameter int unsigned COORD_W=27,parameter int unsigned QUAT_W=22,
    parameter int unsigned SCALE_W=24,parameter int unsigned ROT_W=22,
    parameter int unsigned COV2_W=35,parameter int unsigned COEFF_W=18,
    parameter bit USE_AXI_MEAN_DMA=1'b1,parameter bit USE_AXI_ATTR_DMA=1'b1,
    parameter bit USE_SHARED_PE=1'b1,
    parameter bit USE_STREAMING_DEPTH_PREPASS=1'b0,
    parameter bit USE_PARALLEL_GROUP_SORT=1'b0,
    parameter bit PARALLEL_SORT_SERIAL_FALLBACK=1'b1,
    parameter bit PARALLEL_SORT_BATCH_FORWARDING=1'b1,
    parameter bit PARALLEL_SORT_PHASE_FORWARDING=1'b1,
    parameter bit PARALLEL_SORT_MONOTONIC_FASTPATH=1'b1,
    parameter bit PARALLEL_SORT_STABLE_RUN_FASTPATH=1'b1,
    parameter bit USE_SHARED_PROJECTION_PE=1'b1,
    parameter bit USE_SHARED_RASTER_PE=1'b0,
    parameter bit ENABLE_ALPHA_ZERO_SKIP=1'b0,
    parameter bit USE_AXI_PIXEL_WRITE=1'b1,parameter bit USE_STATE_CACHE_BACKEND=1'b1,
    parameter int unsigned STATE_WINDOW_ENTRIES=2,parameter int unsigned STATE_MSHR_COUNT=2,
    parameter bit ENABLE_RESPONSE_BLEND_BYPASS=1'b0,
    parameter bit ENABLE_BLEND_COMMIT_BYPASS=1'b0,
    parameter bit ENABLE_OPERAND_ISOLATION=1'b0,
    parameter bit ENABLE_SHAPE_BLOCK_REJECT=1'b0,
    parameter int unsigned PIXEL_WRITE_BUFFER_DEPTH=2,
    parameter bit USE_PIXEL_WRITEBACK_BUFFER=1'b0,parameter int unsigned PIXEL_WRITEBACK_DEPTH=32,
    parameter bit USE_PIXEL_MULTIWRITE_BUFFER=1'b1,parameter int unsigned PIXEL_MULTIWRITE_DEPTH=8,
    parameter bit USE_PIXEL_MULTIWRITE_FORWARDING=1'b0,
    parameter int unsigned MODE_ADVISOR_WINDOW_CYCLES=256,
    parameter int unsigned MODE_ADVISOR_HYSTERESIS_WINDOWS=2,
    parameter int unsigned MODE_ADVISOR_MIN_RESIDENCE_WINDOWS=4,
    parameter int unsigned MODE_ADVISOR_SCORE_MARGIN=8,
    parameter int unsigned AXI_ADDR_W=64,
    parameter int unsigned AXI_ID_W=2,parameter int unsigned COEFFS=16,
    parameter int unsigned COEFF_FLAT_W=3*COEFFS*COEFF_W
) (
    input logic clk_i,input logic rst_ni,
    input logic psel_i,penable_i,pwrite_i,input logic[APB_ADDR_W-1:0]paddr_i,
    input logic[31:0]pwdata_i,input logic[3:0]pstrb_i,
    output logic[31:0]prdata_o,output logic pready_o,pslverr_o,irq_o,

    input logic source_valid_i,output logic source_ready_o,input logic[GID_W-1:0]source_gid_i,
    input logic signed[COORD_W-1:0]source_world_x_q16_i,source_world_y_q16_i,source_world_z_q16_i,
    input logic source_last_i,

    output logic[AXI_ID_W-1:0]m_axi_mean_arid_o,output logic[AXI_ADDR_W-1:0]m_axi_mean_araddr_o,
    output logic[7:0]m_axi_mean_arlen_o,output logic[2:0]m_axi_mean_arsize_o,
    output logic[1:0]m_axi_mean_arburst_o,output logic m_axi_mean_arvalid_o,
    input logic m_axi_mean_arready_i,input logic[AXI_ID_W-1:0]m_axi_mean_rid_i,
    input logic[127:0]m_axi_mean_rdata_i,input logic[1:0]m_axi_mean_rresp_i,
    input logic m_axi_mean_rlast_i,m_axi_mean_rvalid_i,output logic m_axi_mean_rready_o,

    output logic[AXI_ID_W-1:0]m_axi_attr_arid_o,output logic[AXI_ADDR_W-1:0]m_axi_attr_araddr_o,
    output logic[7:0]m_axi_attr_arlen_o,output logic[2:0]m_axi_attr_arsize_o,
    output logic[1:0]m_axi_attr_arburst_o,output logic m_axi_attr_arvalid_o,
    input logic m_axi_attr_arready_i,input logic[AXI_ID_W-1:0]m_axi_attr_rid_i,
    input logic[127:0]m_axi_attr_rdata_i,input logic[1:0]m_axi_attr_rresp_i,
    input logic m_axi_attr_rlast_i,m_axi_attr_rvalid_i,output logic m_axi_attr_rready_o,

    output logic[AXI_ID_W-1:0]m_axi_out_awid_o,output logic[AXI_ADDR_W-1:0]m_axi_out_awaddr_o,
    output logic[7:0]m_axi_out_awlen_o,output logic[2:0]m_axi_out_awsize_o,
    output logic[1:0]m_axi_out_awburst_o,output logic m_axi_out_awvalid_o,input logic m_axi_out_awready_i,
    output logic[127:0]m_axi_out_wdata_o,output logic[15:0]m_axi_out_wstrb_o,
    output logic m_axi_out_wlast_o,m_axi_out_wvalid_o,input logic m_axi_out_wready_i,
    input logic[AXI_ID_W-1:0]m_axi_out_bid_i,input logic[1:0]m_axi_out_bresp_i,
    input logic m_axi_out_bvalid_i,output logic m_axi_out_bready_o,

    output logic[AXI_ID_W-1:0]m_axi_state_arid_o,output logic[AXI_ADDR_W-1:0]m_axi_state_araddr_o,
    output logic[7:0]m_axi_state_arlen_o,output logic[2:0]m_axi_state_arsize_o,
    output logic[1:0]m_axi_state_arburst_o,output logic m_axi_state_arvalid_o,
    input logic m_axi_state_arready_i,input logic[AXI_ID_W-1:0]m_axi_state_rid_i,
    input logic[127:0]m_axi_state_rdata_i,input logic[1:0]m_axi_state_rresp_i,
    input logic m_axi_state_rlast_i,m_axi_state_rvalid_i,output logic m_axi_state_rready_o,

    input logic attr_clear_valid_i,input logic attr_write_en_i,input logic[GID_W-1:0]attr_write_gid_i,
    input logic signed[COORD_W-1:0]attr_write_world_x_q16_i,attr_write_world_y_q16_i,attr_write_world_z_q16_i,
    input logic signed[QUAT_W-1:0]attr_write_qw_q20_i,attr_write_qx_q20_i,attr_write_qy_q20_i,attr_write_qz_q20_i,
    input logic[SCALE_W-1:0]attr_write_scale_x_q20_i,attr_write_scale_y_q20_i,attr_write_scale_z_q20_i,
    input logic[12:0]attr_write_opacity_q12_i,input logic[COEFF_FLAT_W-1:0]attr_write_coeff_q12_flat_i,

    input logic signed[ROT_W-1:0]cfg_r00_q20_i,cfg_r01_q20_i,cfg_r02_q20_i,
    input logic signed[ROT_W-1:0]cfg_r10_q20_i,cfg_r11_q20_i,cfg_r12_q20_i,
    input logic signed[ROT_W-1:0]cfg_r20_q20_i,cfg_r21_q20_i,cfg_r22_q20_i,
    input logic signed[COORD_W-1:0]cfg_tx_q16_i,cfg_ty_q16_i,cfg_tz_q16_i,
    input logic signed[COORD_W-1:0]cfg_camera_x_q16_i,cfg_camera_y_q16_i,cfg_camera_z_q16_i,
    input logic signed[32:0]cfg_fx_q16_i,cfg_fy_q16_i,cfg_cx_q16_i,cfg_cy_q16_i,
    input logic signed[COORD_W-1:0]cfg_near_q16_i,cfg_far_q16_i,
    input logic[COV2_W-1:0]cfg_regularizer_q8_i,
    input logic signed[COORD_W-1:0]cfg_depth_pivot0_q16_i,cfg_depth_pivot1_q16_i,cfg_depth_pivot2_q16_i,

    output logic commit_valid_o,input logic commit_ready_i,
    output logic[31:0]commit_task_id_o,commit_block_id_o,output logic[GID_W-1:0]commit_gid_o,
    output logic[15:0]commit_epoch_id_o,output logic[12:0]commit_alpha_q12_o,
    output logic commit_pass_alpha_o,output logic[31:0]commit_pixel_id_o,
    output logic[12:0]commit_r_q12_o,commit_g_q12_o,commit_b_q12_o,
    output logic[15:0]commit_t_q16_o,output logic commit_newly_terminated_o,
    output logic[LANES-1:0]projection_active_mask_o,sh_active_mask_o,raster_active_mask_o,
    output logic attribute_read_pulse_o,
    output logic frame_busy_o,frame_done_pulse_o,frame_error_o,
    output logic[31:0]frame_error_status_o,output logic[1:0]active_mode_o,
    output logic[15:0]epoch_id_o,
    output logic[63:0]perf_cycle_count_o,perf_commit_count_o,perf_state_miss_count_o,
    output logic[63:0]perf_state_read_stall_count_o,perf_output_stall_count_o
);
    logic start_pulse,continue_pulse,more_batches_pulse;
    logic soft_reset_pulse,status_clear_pulse,mode_shadow_we,mode_commit_pulse;
    localparam int unsigned ATTR_W=3*COORD_W+4*QUAT_W+3*SCALE_W+13+COEFF_FLAT_W;
    logic[1:0]shadow_mode,irq_enable,irq_pending_q;logic[63:0]gaussian_base,camera_base,output_base,attribute_base;
    logic[31:0]gaussian_count;logic[15:0]image_width,image_height;
    logic core_rst_ni,mode_pending,mode_commit_done;
    logic done_sticky_q;logic[31:0]error_sticky_q;logic[9:0]frame_error_status_live;
    logic frame_error_live;
    logic selected_source_valid,selected_source_ready,selected_source_last;
    logic[GID_W-1:0]selected_source_gid;
    logic signed[COORD_W-1:0]selected_source_x,selected_source_y,selected_source_z;
    logic source_end_valid,source_end_ready,dma_busy,dma_done,dma_error;
    logic[1:0]dma_error_status;logic dma_start,frame_capacity_ok;
    logic attr_req_valid,attr_req_ready,attr_rsp_valid,attr_rsp_ready,attr_rsp_error;
    logic[GID_W-1:0]attr_req_gid;logic[ATTR_W-1:0]attr_rsp_data;
    logic attr_dma_busy,attr_dma_error;logic[1:0]attr_dma_error_status;
    logic core_commit_valid,core_commit_ready;logic[31:0]core_commit_task,core_commit_block;
    logic[GID_W-1:0]core_commit_gid;logic[15:0]core_commit_epoch;logic[12:0]core_commit_alpha;
    logic core_commit_pass;logic[31:0]core_commit_pixel;logic[12:0]core_commit_r,core_commit_g,core_commit_b;
    logic[15:0]core_commit_t;logic core_commit_terminated;
    logic write_busy,write_error,write_hazard,write_lookup_hit;logic[1:0]write_error_status;
    logic[127:0]write_lookup_data;logic[63:0]write_coalesced_count;
    logic[$clog2(PIXEL_MULTIWRITE_DEPTH+1)-1:0]write_multi_peak;
    logic state_miss_req_valid,state_miss_req_ready;logic[1:0]state_miss_req_tag;
    logic state_miss_rsp_valid,state_miss_rsp_ready;logic[1:0]state_miss_rsp_tag;
    logic[31:0]state_miss_req_pixel;logic state_miss_rsp_error,state_cache_error,state_cache_idle;
    logic[127:0]state_miss_rsp_data;logic state_read_busy,state_read_error;
    logic state_axi_rsp_valid,state_axi_rsp_ready,state_axi_rsp_error;logic[1:0]state_axi_rsp_tag;
    logic[127:0]state_axi_rsp_data,forward_rsp_data_q;logic forward_rsp_valid_q;logic[1:0]forward_rsp_tag_q;
    logic[1:0]state_read_error_status;
    logic core_frame_busy,core_frame_done,completion_pending_q;logic[9:0]completed_core_error_q;
    logic logical_frame_open_q,active_batch_more_q,batch_sequence_valid,batch_start,batch_failed;
    logic continuation_config_valid;logic[63:0]logical_output_base_q;
    logic[15:0]logical_image_width_q,logical_image_height_q;
    logic auto_mode_enable,auto_mode_enable_q,auto_disable_pulse;
    logic advisor_recommendation_valid,advisor_recommendation_ready;
    logic[1:0]advisor_recommendation_mode,advisor_window_winner;
    logic advisor_window_done,advisor_request_outstanding;
    logic[31:0]advisor_window_index,advisor_window_group,advisor_window_sort;
    logic[31:0]advisor_window_projection,advisor_window_raster;
    logic[31:0]advisor_window_block,advisor_window_skip;
    logic advisor_queue_valid_q;logic[1:0]advisor_queue_mode_q;
    logic event_group_pressure,event_sort_busy,event_projection_busy,event_raster_busy;
    logic event_block_candidate,event_shape_block_reject,event_terminated_skip;
    logic shared_pe_group_grant,shared_pe_projection_grant,shared_pe_raster_grant;
    logic shared_pe_group_stall,shared_pe_projection_stall,shared_pe_raster_stall;
    logic shared_pe_utilization,shared_pe_clock_enable,shared_pe_busy;
    logic[31:0]shared_pe_group_grant_count_q,shared_pe_projection_grant_count_q;
    logic[31:0]shared_pe_raster_grant_count_q,shared_pe_group_stall_count_q;
    logic[31:0]shared_pe_projection_stall_count_q,shared_pe_raster_stall_count_q;
    logic[31:0]shared_pe_utilization_count_q;
    logic[383:0]sort_work_totals,sort_work_base_q,sort_work_snapshot_q;
    logic[31:0]sort_snapshot_sequence_q;
    logic sort_snapshot_pulse,sort_clear_pulse;
    wire[31:0]sort_capabilities=(USE_SHARED_PE&&USE_PARALLEL_GROUP_SORT)?
      (32'd5|(PARALLEL_SORT_MONOTONIC_FASTPATH&&LANES>1?32'd2:32'd0)):32'd0;
    logic selected_runtime_mode_valid;logic[1:0]selected_runtime_mode,selected_frame_mode;

    function automatic logic[63:0]sat_inc(input logic[63:0]value);
      begin sat_inc=&value?value:value+64'd1;end
    endfunction
    function automatic logic[31:0]sat_inc32(input logic[31:0]value);
      begin sat_inc32=&value?value:value+32'd1;end
    endfunction

    assign core_rst_ni=rst_ni&&!soft_reset_pulse;
    assign frame_error_o=|error_sticky_q;
    assign frame_error_status_o=error_sticky_q;
    assign irq_o=|(irq_pending_q&irq_enable);
    assign frame_capacity_ok=USE_STATE_CACHE_BACKEND||
      (({16'b0,image_width}*{16'b0,image_height})<=STATE_ENTRIES);
    assign frame_busy_o=core_frame_busy||write_busy||state_read_busy||completion_pending_q;
    assign continuation_config_valid=output_base==logical_output_base_q&&
      image_width==logical_image_width_q&&image_height==logical_image_height_q;
    assign batch_sequence_valid=continue_pulse?
      (logical_frame_open_q&&continuation_config_valid):!logical_frame_open_q;
    assign batch_start=start_pulse&&!frame_busy_o&&!soft_reset_pulse&&batch_sequence_valid;
    assign dma_start=batch_start&&frame_capacity_ok;
    assign batch_failed=(core_frame_done?|frame_error_status_live:|completed_core_error_q)||
      dma_error||attr_dma_error||write_error||state_read_error;
    assign commit_valid_o=core_commit_valid;assign commit_task_id_o=core_commit_task;
    assign commit_block_id_o=core_commit_block;assign commit_gid_o=core_commit_gid;
    assign commit_epoch_id_o=core_commit_epoch;assign commit_alpha_q12_o=core_commit_alpha;
    assign commit_pass_alpha_o=core_commit_pass;assign commit_pixel_id_o=core_commit_pixel;
    assign commit_r_q12_o=core_commit_r;assign commit_g_q12_o=core_commit_g;
    assign commit_b_q12_o=core_commit_b;assign commit_t_q16_o=core_commit_t;
    assign commit_newly_terminated_o=core_commit_terminated;
    assign auto_disable_pulse=auto_mode_enable_q&&!auto_mode_enable;
    assign advisor_recommendation_ready=auto_mode_enable&&!mode_pending&&!advisor_queue_valid_q;
    assign selected_runtime_mode_valid=auto_disable_pulse||
      (!auto_mode_enable&&mode_commit_pulse)||
      (advisor_recommendation_valid&&advisor_recommendation_ready);
    assign selected_runtime_mode=auto_disable_pulse?shadow_mode:
      (auto_mode_enable?advisor_recommendation_mode:shadow_mode);
    assign selected_frame_mode=auto_mode_enable?active_mode_o:shadow_mode;

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        auto_mode_enable_q<=1'b0;advisor_queue_valid_q<=1'b0;advisor_queue_mode_q<=2'b0;
      end else begin
        auto_mode_enable_q<=auto_mode_enable;
        if(auto_disable_pulse||mode_commit_done)advisor_queue_valid_q<=1'b0;
        if(advisor_recommendation_valid&&advisor_recommendation_ready)begin
          advisor_queue_valid_q<=1'b1;advisor_queue_mode_q<=advisor_recommendation_mode;
        end
      end
    end

    gaussian_mode_advisor #(.WINDOW_CYCLES(MODE_ADVISOR_WINDOW_CYCLES),
      .HYSTERESIS_WINDOWS(MODE_ADVISOR_HYSTERESIS_WINDOWS),
      .MIN_RESIDENCE_WINDOWS(MODE_ADVISOR_MIN_RESIDENCE_WINDOWS),
      .SCORE_MARGIN(MODE_ADVISOR_SCORE_MARGIN))u_mode_advisor(
      .clk_i(clk_i),.rst_ni(core_rst_ni),.enable_i(auto_mode_enable),
      .sample_enable_i(core_frame_busy),.active_mode_i(active_mode_o),
      .mode_commit_pulse_i(mode_commit_done),.group_pressure_i(event_group_pressure),
      .sort_busy_i(event_sort_busy),.projection_busy_i(event_projection_busy),
      .raster_busy_i(event_raster_busy),.block_candidate_i(event_block_candidate),
      .block_terminated_skip_i(event_terminated_skip),
      .recommendation_valid_o(advisor_recommendation_valid),
      .recommendation_ready_i(advisor_recommendation_ready),
      .recommendation_mode_o(advisor_recommendation_mode),
      .window_done_pulse_o(advisor_window_done),.window_winner_o(advisor_window_winner),
      .request_outstanding_o(advisor_request_outstanding),
      .window_index_o(advisor_window_index),.window_group_count_o(advisor_window_group),
      .window_sort_count_o(advisor_window_sort),
      .window_projection_count_o(advisor_window_projection),
      .window_raster_count_o(advisor_window_raster),
      .window_block_count_o(advisor_window_block),.window_skip_count_o(advisor_window_skip));

    apb_regfile #(.ADDR_W(APB_ADDR_W))u_apb(
      .pclk_i(clk_i),.preset_ni(rst_ni),.psel_i(psel_i),.penable_i(penable_i),.pwrite_i(pwrite_i),
      .paddr_i(paddr_i),.pwdata_i(pwdata_i),.pstrb_i(pstrb_i),.prdata_o(prdata_o),
      .pready_o(pready_o),.pslverr_o(pslverr_o),.start_pulse_o(start_pulse),
      .continue_pulse_o(continue_pulse),.more_batches_pulse_o(more_batches_pulse),
      .soft_reset_pulse_o(soft_reset_pulse),.status_clear_pulse_o(status_clear_pulse),
      .shadow_mode_o(shadow_mode),.mode_shadow_we_o(mode_shadow_we),.mode_commit_pulse_o(mode_commit_pulse),
      .gaussian_base_o(gaussian_base),.camera_base_o(camera_base),.output_base_o(output_base),
      .image_width_o(image_width),.image_height_o(image_height),.gaussian_count_o(gaussian_count),
      .attribute_base_o(attribute_base),
      .irq_enable_o(irq_enable),.auto_mode_enable_o(auto_mode_enable),
      .busy_i(frame_busy_o),.done_i(done_sticky_q),.error_i(frame_error_o),
      .error_status_i(error_sticky_q),.irq_pending_i(irq_pending_q),.irq_i(irq_o),
      .active_mode_i(active_mode_o),.epoch_id_i(epoch_id_o),.commit_pending_i(mode_pending),
      .commit_overrun_i(error_sticky_q[7]),.frame_open_i(logical_frame_open_q),
      .advisor_recommendation_valid_i(advisor_recommendation_valid||advisor_queue_valid_q),
      .advisor_recommendation_mode_i(advisor_queue_valid_q?advisor_queue_mode_q:advisor_recommendation_mode),
      .advisor_window_winner_i(advisor_window_winner),
      .advisor_request_outstanding_i(advisor_request_outstanding),
      .advisor_window_index_i(advisor_window_index),.advisor_window_group_i(advisor_window_group),
      .advisor_window_sort_i(advisor_window_sort),
      .advisor_window_projection_i(advisor_window_projection),
      .advisor_window_raster_i(advisor_window_raster),
       .advisor_window_block_i(advisor_window_block),.advisor_window_skip_i(advisor_window_skip),
       .shared_pe_group_grant_count_i(shared_pe_group_grant_count_q),
       .shared_pe_projection_grant_count_i(shared_pe_projection_grant_count_q),
       .shared_pe_raster_grant_count_i(shared_pe_raster_grant_count_q),
       .shared_pe_group_stall_count_i(shared_pe_group_stall_count_q),
       .shared_pe_projection_stall_count_i(shared_pe_projection_stall_count_q),
       .shared_pe_raster_stall_count_i(shared_pe_raster_stall_count_q),
       .shared_pe_utilization_count_i(shared_pe_utilization_count_q),
       .sort_work_snapshot_i(sort_work_snapshot_q),.sort_capabilities_i(sort_capabilities),
       .sort_snapshot_sequence_i(sort_snapshot_sequence_q),.sort_snapshot_pulse_o(sort_snapshot_pulse),
       .sort_clear_pulse_o(sort_clear_pulse));

    generate
      if(USE_AXI_MEAN_DMA)begin:g_axi_mean
        axi4_gaussian_mean_read_dma #(.ADDR_W(AXI_ADDR_W),.ID_W(AXI_ID_W),
          .GID_W(GID_W),.COORD_W(COORD_W))u_mean_dma(
          .clk_i(clk_i),.rst_ni(core_rst_ni),.start_i(dma_start),.clear_error_i(status_clear_pulse),
          .base_addr_i(gaussian_base),
          .gaussian_count_i(gaussian_count),.busy_o(dma_busy),.done_pulse_o(dma_done),
          .error_sticky_o(dma_error),.error_status_o(dma_error_status),
          .m_valid_o(selected_source_valid),.m_ready_i(selected_source_ready),
          .m_gid_o(selected_source_gid),.m_world_x_q16_o(selected_source_x),
          .m_world_y_q16_o(selected_source_y),.m_world_z_q16_o(selected_source_z),
          .m_last_o(selected_source_last),.end_valid_o(source_end_valid),.end_ready_i(source_end_ready),
          .m_axi_arid_o(m_axi_mean_arid_o),.m_axi_araddr_o(m_axi_mean_araddr_o),
          .m_axi_arlen_o(m_axi_mean_arlen_o),.m_axi_arsize_o(m_axi_mean_arsize_o),
          .m_axi_arburst_o(m_axi_mean_arburst_o),.m_axi_arvalid_o(m_axi_mean_arvalid_o),
          .m_axi_arready_i(m_axi_mean_arready_i),.m_axi_rid_i(m_axi_mean_rid_i),
          .m_axi_rdata_i(m_axi_mean_rdata_i),.m_axi_rresp_i(m_axi_mean_rresp_i),
          .m_axi_rlast_i(m_axi_mean_rlast_i),.m_axi_rvalid_i(m_axi_mean_rvalid_i),
          .m_axi_rready_o(m_axi_mean_rready_o));
        assign source_ready_o=1'b0;
      end else begin:g_external_mean
        assign selected_source_valid=source_valid_i;
        assign selected_source_gid=source_gid_i;
        assign selected_source_x=source_world_x_q16_i;
        assign selected_source_y=source_world_y_q16_i;
        assign selected_source_z=source_world_z_q16_i;
        assign selected_source_last=source_last_i;
        assign source_end_valid=1'b0;
        assign source_ready_o=selected_source_ready;
        assign dma_busy=1'b0;assign dma_done=1'b0;assign dma_error=1'b0;assign dma_error_status=2'b0;
        assign m_axi_mean_arid_o='0;assign m_axi_mean_araddr_o='0;assign m_axi_mean_arlen_o='0;
        assign m_axi_mean_arsize_o=3'd4;assign m_axi_mean_arburst_o=2'b01;
        assign m_axi_mean_arvalid_o=1'b0;assign m_axi_mean_rready_o=1'b0;
      end
    endgenerate

    generate
      if(USE_STATE_CACHE_BACKEND)begin:g_axi_state_read
        // Only a same-pixel miss waits for older queued/write-through state.
        // Unrelated pixels may overlap the ordered AXI writer safely.
        logic state_read_req_ready;
        assign state_miss_req_ready=write_lookup_hit?!forward_rsp_valid_q:(!write_hazard&&state_read_req_ready);
        assign state_miss_rsp_valid=forward_rsp_valid_q||state_axi_rsp_valid;
        assign state_miss_rsp_tag=forward_rsp_valid_q?forward_rsp_tag_q:state_axi_rsp_tag;
        assign state_miss_rsp_data=forward_rsp_valid_q?forward_rsp_data_q:state_axi_rsp_data;
        assign state_miss_rsp_error=forward_rsp_valid_q?1'b0:state_axi_rsp_error;
        assign state_axi_rsp_ready=!forward_rsp_valid_q&&state_miss_rsp_ready;
        if(STATE_MSHR_COUNT==4)begin:g_quad_state_read
        axi4_pixel_state_quad_read_engine #(.ADDR_W(AXI_ADDR_W),.ID_W(AXI_ID_W))u_state_read(
          .clk_i(clk_i),.rst_ni(core_rst_ni),.clear_error_i(status_clear_pulse),.base_addr_i(output_base),
          .req_valid_i(state_miss_req_valid&&!write_lookup_hit&&!write_hazard),.req_ready_o(state_read_req_ready),
          .req_tag_i(state_miss_req_tag),.req_pixel_id_i(state_miss_req_pixel),
          .rsp_valid_o(state_axi_rsp_valid),.rsp_ready_i(state_axi_rsp_ready),
          .rsp_tag_o(state_axi_rsp_tag),.rsp_error_o(state_axi_rsp_error),.rsp_data_o(state_axi_rsp_data),
          .busy_o(state_read_busy),.error_sticky_o(state_read_error),.error_status_o(state_read_error_status),
          .m_axi_arid_o(m_axi_state_arid_o),.m_axi_araddr_o(m_axi_state_araddr_o),
          .m_axi_arlen_o(m_axi_state_arlen_o),.m_axi_arsize_o(m_axi_state_arsize_o),
          .m_axi_arburst_o(m_axi_state_arburst_o),.m_axi_arvalid_o(m_axi_state_arvalid_o),
          .m_axi_arready_i(m_axi_state_arready_i),.m_axi_rid_i(m_axi_state_rid_i),
          .m_axi_rdata_i(m_axi_state_rdata_i),.m_axi_rresp_i(m_axi_state_rresp_i),
          .m_axi_rlast_i(m_axi_state_rlast_i),.m_axi_rvalid_i(m_axi_state_rvalid_i),
          .m_axi_rready_o(m_axi_state_rready_o));
        end else if(STATE_MSHR_COUNT==2)begin:g_dual_state_read
        assign state_axi_rsp_tag[1]=1'b0;
        axi4_pixel_state_dual_read_engine #(.ADDR_W(AXI_ADDR_W),.ID_W(AXI_ID_W))u_state_read(
          .clk_i(clk_i),.rst_ni(core_rst_ni),.clear_error_i(status_clear_pulse),.base_addr_i(output_base),
          .req_valid_i(state_miss_req_valid&&!write_lookup_hit&&!write_hazard),.req_ready_o(state_read_req_ready),
          .req_tag_i(state_miss_req_tag[0]),
          .req_pixel_id_i(state_miss_req_pixel),.rsp_valid_o(state_axi_rsp_valid),
          .rsp_ready_i(state_axi_rsp_ready),.rsp_tag_o(state_axi_rsp_tag[0]),.rsp_error_o(state_axi_rsp_error),
          .rsp_data_o(state_axi_rsp_data),.busy_o(state_read_busy),
          .error_sticky_o(state_read_error),.error_status_o(state_read_error_status),
          .m_axi_arid_o(m_axi_state_arid_o),.m_axi_araddr_o(m_axi_state_araddr_o),
          .m_axi_arlen_o(m_axi_state_arlen_o),.m_axi_arsize_o(m_axi_state_arsize_o),
          .m_axi_arburst_o(m_axi_state_arburst_o),.m_axi_arvalid_o(m_axi_state_arvalid_o),
          .m_axi_arready_i(m_axi_state_arready_i),.m_axi_rid_i(m_axi_state_rid_i),
          .m_axi_rdata_i(m_axi_state_rdata_i),.m_axi_rresp_i(m_axi_state_rresp_i),
          .m_axi_rlast_i(m_axi_state_rlast_i),.m_axi_rvalid_i(m_axi_state_rvalid_i),
          .m_axi_rready_o(m_axi_state_rready_o));
        end else begin:g_single_state_read
          logic single_rsp_valid,single_rsp_error,single_rsp_tag_q;logic[127:0]single_rsp_data;
          axi4_pixel_state_read_engine #(.ADDR_W(AXI_ADDR_W),.ID_W(AXI_ID_W))u_state_read(
            .clk_i(clk_i),.rst_ni(core_rst_ni),.clear_error_i(status_clear_pulse),.base_addr_i(output_base),
            .req_valid_i(state_miss_req_valid&&!write_lookup_hit&&!write_hazard),.req_ready_o(state_read_req_ready),
            .req_pixel_id_i(state_miss_req_pixel),.rsp_valid_o(single_rsp_valid),
            .rsp_ready_i(state_axi_rsp_ready),.rsp_error_o(single_rsp_error),.rsp_data_o(single_rsp_data),
            .busy_o(state_read_busy),.error_sticky_o(state_read_error),.error_status_o(state_read_error_status),
            .m_axi_arid_o(m_axi_state_arid_o),.m_axi_araddr_o(m_axi_state_araddr_o),
            .m_axi_arlen_o(m_axi_state_arlen_o),.m_axi_arsize_o(m_axi_state_arsize_o),
            .m_axi_arburst_o(m_axi_state_arburst_o),.m_axi_arvalid_o(m_axi_state_arvalid_o),
            .m_axi_arready_i(m_axi_state_arready_i),.m_axi_rid_i(m_axi_state_rid_i),
            .m_axi_rdata_i(m_axi_state_rdata_i),.m_axi_rresp_i(m_axi_state_rresp_i),
            .m_axi_rlast_i(m_axi_state_rlast_i),.m_axi_rvalid_i(m_axi_state_rvalid_i),
            .m_axi_rready_o(m_axi_state_rready_o));
          always_ff@(posedge clk_i or negedge core_rst_ni)begin
            if(!core_rst_ni)single_rsp_tag_q<=0;
            else if(state_miss_req_valid&&state_read_req_ready&&!write_lookup_hit&&!write_hazard)
              single_rsp_tag_q<=state_miss_req_tag[0];
          end
          assign state_axi_rsp_valid=single_rsp_valid;assign state_axi_rsp_tag={1'b0,single_rsp_tag_q};
          assign state_axi_rsp_error=single_rsp_error;assign state_axi_rsp_data=single_rsp_data;
        end
        always_ff@(posedge clk_i or negedge core_rst_ni)begin
          if(!core_rst_ni)begin forward_rsp_valid_q<=0;forward_rsp_tag_q<=0;forward_rsp_data_q<=0;end
          else begin
            if(state_miss_req_valid&&state_miss_req_ready&&write_lookup_hit)begin
              forward_rsp_valid_q<=1;forward_rsp_tag_q<=state_miss_req_tag;forward_rsp_data_q<=write_lookup_data;end
            if(forward_rsp_valid_q&&state_miss_rsp_ready)forward_rsp_valid_q<=0;
          end
        end
      end else begin:g_no_axi_state_read
        assign state_miss_req_ready=0;assign state_miss_rsp_valid=0;assign state_miss_rsp_error=0;
        assign state_miss_rsp_data='0;assign state_read_busy=0;assign state_read_error=0;
        assign state_read_error_status=0;assign m_axi_state_arid_o='0;assign m_axi_state_araddr_o='0;
        assign m_axi_state_arlen_o=0;assign m_axi_state_arsize_o=3'd4;
        assign m_axi_state_arburst_o=2'b01;assign m_axi_state_arvalid_o=0;assign m_axi_state_rready_o=0;
        assign state_axi_rsp_valid=0;assign state_axi_rsp_tag=0;assign state_axi_rsp_error=0;assign state_axi_rsp_data=0;
        assign state_axi_rsp_ready=0;assign forward_rsp_valid_q=0;assign forward_rsp_tag_q=0;assign forward_rsp_data_q=0;
      end
    endgenerate

    generate
      if(USE_AXI_PIXEL_WRITE)begin:g_axi_output
        if(USE_PIXEL_WRITEBACK_BUFFER)begin:g_writeback
        axi4_pixel_state_writeback_buffer #(.ADDR_W(AXI_ADDR_W),.ID_W(AXI_ID_W),
          .DEPTH(PIXEL_WRITEBACK_DEPTH))u_output_dma(
          .clk_i(clk_i),.rst_ni(core_rst_ni),.clear_error_i(status_clear_pulse),.base_addr_i(output_base),
          .flush_i(core_frame_done),
          .s_valid_i(core_commit_valid),.s_ready_o(core_commit_ready),.s_pixel_id_i(core_commit_pixel),
          .s_gid_i({{(32-GID_W){1'b0}},core_commit_gid}),.s_epoch_id_i(core_commit_epoch),.s_alpha_q12_i(core_commit_alpha),
          .s_pass_alpha_i(core_commit_pass),.s_r_q12_i(core_commit_r),.s_g_q12_i(core_commit_g),
          .s_b_q12_i(core_commit_b),.s_t_q16_i(core_commit_t),
          .s_newly_terminated_i(core_commit_terminated),.lookup_pixel_id_i(state_miss_req_pixel),
          .lookup_hit_o(write_lookup_hit),.lookup_data_o(write_lookup_data),.occupancy_o(),
          .coalesced_count_o(write_coalesced_count),.flush_busy_o(),.busy_o(write_busy),
          .error_sticky_o(write_error),.error_status_o(write_error_status),
          .m_axi_awid_o(m_axi_out_awid_o),.m_axi_awaddr_o(m_axi_out_awaddr_o),
          .m_axi_awlen_o(m_axi_out_awlen_o),.m_axi_awsize_o(m_axi_out_awsize_o),
          .m_axi_awburst_o(m_axi_out_awburst_o),.m_axi_awvalid_o(m_axi_out_awvalid_o),
          .m_axi_awready_i(m_axi_out_awready_i),.m_axi_wdata_o(m_axi_out_wdata_o),
          .m_axi_wstrb_o(m_axi_out_wstrb_o),.m_axi_wlast_o(m_axi_out_wlast_o),
          .m_axi_wvalid_o(m_axi_out_wvalid_o),.m_axi_wready_i(m_axi_out_wready_i),
          .m_axi_bid_i(m_axi_out_bid_i),.m_axi_bresp_i(m_axi_out_bresp_i),
          .m_axi_bvalid_i(m_axi_out_bvalid_i),.m_axi_bready_o(m_axi_out_bready_o));
        assign write_hazard=0;
        assign write_multi_peak=0;
        end else if(USE_PIXEL_MULTIWRITE_BUFFER)begin:g_multiwrite
        axi4_pixel_state_multiwrite_buffer #(.ADDR_W(AXI_ADDR_W),.ID_W(AXI_ID_W),
          .DEPTH(PIXEL_MULTIWRITE_DEPTH),.ENABLE_LOOKUP_FORWARD(USE_PIXEL_MULTIWRITE_FORWARDING))u_output_dma(
          .clk_i(clk_i),.rst_ni(core_rst_ni),.clear_error_i(status_clear_pulse),.base_addr_i(output_base),
          .s_valid_i(core_commit_valid),.s_ready_o(core_commit_ready),.s_pixel_id_i(core_commit_pixel),
          .s_gid_i({{(32-GID_W){1'b0}},core_commit_gid}),.s_epoch_id_i(core_commit_epoch),.s_alpha_q12_i(core_commit_alpha),
          .s_pass_alpha_i(core_commit_pass),.s_r_q12_i(core_commit_r),.s_g_q12_i(core_commit_g),
          .s_b_q12_i(core_commit_b),.s_t_q16_i(core_commit_t),.s_newly_terminated_i(core_commit_terminated),
          .hazard_pixel_id_i(state_miss_req_pixel),.hazard_o(write_hazard),.occupancy_o(),
          .lookup_pixel_id_i(state_miss_req_pixel),.lookup_hit_o(write_lookup_hit),
          .lookup_data_o(write_lookup_data),
          .outstanding_o(),.peak_outstanding_o(write_multi_peak),.busy_o(write_busy),
          .error_sticky_o(write_error),.error_status_o(write_error_status),
          .m_axi_awid_o(m_axi_out_awid_o),.m_axi_awaddr_o(m_axi_out_awaddr_o),.m_axi_awlen_o(m_axi_out_awlen_o),
          .m_axi_awsize_o(m_axi_out_awsize_o),.m_axi_awburst_o(m_axi_out_awburst_o),.m_axi_awvalid_o(m_axi_out_awvalid_o),
          .m_axi_awready_i(m_axi_out_awready_i),.m_axi_wdata_o(m_axi_out_wdata_o),.m_axi_wstrb_o(m_axi_out_wstrb_o),
          .m_axi_wlast_o(m_axi_out_wlast_o),.m_axi_wvalid_o(m_axi_out_wvalid_o),.m_axi_wready_i(m_axi_out_wready_i),
          .m_axi_bid_i(m_axi_out_bid_i),.m_axi_bresp_i(m_axi_out_bresp_i),.m_axi_bvalid_i(m_axi_out_bvalid_i),
          .m_axi_bready_o(m_axi_out_bready_o));
        assign write_coalesced_count=0;
        end else begin:g_writethrough
        axi4_pixel_state_write_buffer #(.ADDR_W(AXI_ADDR_W),.ID_W(AXI_ID_W),
          .DEPTH(PIXEL_WRITE_BUFFER_DEPTH))u_output_dma(
          .clk_i(clk_i),.rst_ni(core_rst_ni),.clear_error_i(status_clear_pulse),.base_addr_i(output_base),
          .s_valid_i(core_commit_valid),.s_ready_o(core_commit_ready),.s_pixel_id_i(core_commit_pixel),
          .s_gid_i({{(32-GID_W){1'b0}},core_commit_gid}),.s_epoch_id_i(core_commit_epoch),.s_alpha_q12_i(core_commit_alpha),
          .s_pass_alpha_i(core_commit_pass),.s_r_q12_i(core_commit_r),.s_g_q12_i(core_commit_g),
          .s_b_q12_i(core_commit_b),.s_t_q16_i(core_commit_t),.s_newly_terminated_i(core_commit_terminated),
          .hazard_pixel_id_i(state_miss_req_pixel),.hazard_o(write_hazard),.occupancy_o(),.busy_o(write_busy),
          .error_sticky_o(write_error),.error_status_o(write_error_status),
          .m_axi_awid_o(m_axi_out_awid_o),.m_axi_awaddr_o(m_axi_out_awaddr_o),.m_axi_awlen_o(m_axi_out_awlen_o),
          .m_axi_awsize_o(m_axi_out_awsize_o),.m_axi_awburst_o(m_axi_out_awburst_o),.m_axi_awvalid_o(m_axi_out_awvalid_o),
          .m_axi_awready_i(m_axi_out_awready_i),.m_axi_wdata_o(m_axi_out_wdata_o),.m_axi_wstrb_o(m_axi_out_wstrb_o),
          .m_axi_wlast_o(m_axi_out_wlast_o),.m_axi_wvalid_o(m_axi_out_wvalid_o),.m_axi_wready_i(m_axi_out_wready_i),
          .m_axi_bid_i(m_axi_out_bid_i),.m_axi_bresp_i(m_axi_out_bresp_i),.m_axi_bvalid_i(m_axi_out_bvalid_i),
          .m_axi_bready_o(m_axi_out_bready_o));
        assign write_lookup_hit=0;assign write_lookup_data=0;assign write_coalesced_count=0;
        assign write_multi_peak=0;
        end
      end else begin:g_external_output
        assign core_commit_ready=commit_ready_i;assign write_busy=0;assign write_hazard=0;
        assign write_lookup_hit=0;assign write_lookup_data=0;assign write_coalesced_count=0;
        assign write_multi_peak=0;
        assign write_error=0;assign write_error_status=0;
        assign m_axi_out_awid_o='0;assign m_axi_out_awaddr_o='0;assign m_axi_out_awlen_o=0;
        assign m_axi_out_awsize_o=3'd4;assign m_axi_out_awburst_o=2'b01;assign m_axi_out_awvalid_o=0;
        assign m_axi_out_wdata_o='0;assign m_axi_out_wstrb_o='0;assign m_axi_out_wlast_o=1;
        assign m_axi_out_wvalid_o=0;assign m_axi_out_bready_o=0;
      end
    endgenerate

    generate
      if(USE_AXI_ATTR_DMA)begin:g_axi_attr
        axi4_gaussian_attribute_read_engine #(.ADDR_W(AXI_ADDR_W),.ID_W(AXI_ID_W),
          .GID_W(GID_W),.ATTR_W(ATTR_W))u_attr_dma(
          .clk_i(clk_i),.rst_ni(core_rst_ni),.clear_error_i(status_clear_pulse),
          .base_addr_i(attribute_base),.req_valid_i(attr_req_valid),.req_ready_o(attr_req_ready),
          .req_gid_i(attr_req_gid),.rsp_valid_o(attr_rsp_valid),.rsp_ready_i(attr_rsp_ready),
          .rsp_error_o(attr_rsp_error),.rsp_data_o(attr_rsp_data),.busy_o(attr_dma_busy),
          .error_sticky_o(attr_dma_error),.error_status_o(attr_dma_error_status),
          .m_axi_arid_o(m_axi_attr_arid_o),.m_axi_araddr_o(m_axi_attr_araddr_o),
          .m_axi_arlen_o(m_axi_attr_arlen_o),.m_axi_arsize_o(m_axi_attr_arsize_o),
          .m_axi_arburst_o(m_axi_attr_arburst_o),.m_axi_arvalid_o(m_axi_attr_arvalid_o),
          .m_axi_arready_i(m_axi_attr_arready_i),.m_axi_rid_i(m_axi_attr_rid_i),
          .m_axi_rdata_i(m_axi_attr_rdata_i),.m_axi_rresp_i(m_axi_attr_rresp_i),
          .m_axi_rlast_i(m_axi_attr_rlast_i),.m_axi_rvalid_i(m_axi_attr_rvalid_i),
          .m_axi_rready_o(m_axi_attr_rready_o));
      end else begin:g_local_attr
        assign attr_req_ready=1'b0;assign attr_rsp_valid=1'b0;assign attr_rsp_error=1'b0;assign attr_rsp_data='0;
        assign attr_dma_busy=1'b0;assign attr_dma_error=1'b0;assign attr_dma_error_status=0;
        assign m_axi_attr_arid_o='0;assign m_axi_attr_araddr_o='0;assign m_axi_attr_arlen_o='0;
        assign m_axi_attr_arsize_o=3'd4;assign m_axi_attr_arburst_o=2'b01;
        assign m_axi_attr_arvalid_o=0;assign m_axi_attr_rready_o=0;
      end
    endgenerate

    gaussian_frame_render_pipeline #(.ATTR_DEPTH(ATTR_DEPTH),.LANES(LANES),
      .GROUP_CAPACITY(GROUP_CAPACITY),.SORT_CAPACITY(SORT_CAPACITY),.STATE_ENTRIES(STATE_ENTRIES),
      .STATE_WINDOW_ENTRIES(STATE_WINDOW_ENTRIES),.STATE_MSHR_COUNT(STATE_MSHR_COUNT),
      .ENABLE_RESPONSE_BLEND_BYPASS(ENABLE_RESPONSE_BLEND_BYPASS),
      .ENABLE_BLEND_COMMIT_BYPASS(ENABLE_BLEND_COMMIT_BYPASS),
      .ENABLE_OPERAND_ISOLATION(ENABLE_OPERAND_ISOLATION),
      .ENABLE_SHAPE_BLOCK_REJECT(ENABLE_SHAPE_BLOCK_REJECT),
      .USE_SHARED_PE(USE_SHARED_PE),
      .USE_STREAMING_DEPTH_PREPASS(USE_STREAMING_DEPTH_PREPASS),
      .USE_PARALLEL_GROUP_SORT(USE_PARALLEL_GROUP_SORT),
      .PARALLEL_SORT_SERIAL_FALLBACK(PARALLEL_SORT_SERIAL_FALLBACK),
      .PARALLEL_SORT_BATCH_FORWARDING(PARALLEL_SORT_BATCH_FORWARDING),
      .PARALLEL_SORT_PHASE_FORWARDING(PARALLEL_SORT_PHASE_FORWARDING),
      .PARALLEL_SORT_MONOTONIC_FASTPATH(PARALLEL_SORT_MONOTONIC_FASTPATH),
      .PARALLEL_SORT_STABLE_RUN_FASTPATH(PARALLEL_SORT_STABLE_RUN_FASTPATH),
      .USE_SHARED_PROJECTION_PE(USE_SHARED_PROJECTION_PE),
      .USE_SHARED_RASTER_PE(USE_SHARED_RASTER_PE),
      .ENABLE_ALPHA_ZERO_SKIP(ENABLE_ALPHA_ZERO_SKIP),
      .USE_EXTERNAL_ATTR_BACKEND(USE_AXI_ATTR_DMA),.USE_STATE_CACHE_BACKEND(USE_STATE_CACHE_BACKEND),
      .GID_W(GID_W),.SEQ_W(SEQ_W),.COORD_W(COORD_W),.QUAT_W(QUAT_W),.SCALE_W(SCALE_W),
      .ROT_W(ROT_W),.COV2_W(COV2_W),.COEFF_W(COEFF_W),.COEFFS(COEFFS))u_frame(
      .clk_i(clk_i),.rst_ni(core_rst_ni),.frame_start_i(batch_start),
      .frame_continue_i(continue_pulse),
      .frame_mode_i(selected_frame_mode),.frame_ready_o(),.frame_busy_o(core_frame_busy),
      .frame_done_pulse_o(core_frame_done),.frame_error_o(frame_error_live),
      .frame_error_status_o(frame_error_status_live),.source_valid_i(selected_source_valid),
      .source_ready_o(selected_source_ready),.source_gid_i(selected_source_gid),
      .source_world_x_q16_i(selected_source_x),.source_world_y_q16_i(selected_source_y),
      .source_world_z_q16_i(selected_source_z),.source_last_i(selected_source_last),
      .source_end_valid_i(source_end_valid),.source_end_ready_o(source_end_ready),
      .runtime_mode_valid_i(selected_runtime_mode_valid),.runtime_mode_i(selected_runtime_mode),
      .active_mode_o(active_mode_o),.epoch_id_o(epoch_id_o),.mode_pending_o(mode_pending),
      .mode_commit_pulse_o(mode_commit_done),.attr_clear_valid_i(attr_clear_valid_i),
      .attr_req_valid_o(attr_req_valid),.attr_req_ready_i(attr_req_ready),.attr_req_gid_o(attr_req_gid),
      .attr_rsp_valid_i(attr_rsp_valid),.attr_rsp_ready_o(attr_rsp_ready),
      .attr_rsp_error_i(attr_rsp_error),.attr_rsp_data_i(attr_rsp_data),
      .attr_write_en_i(attr_write_en_i),.attr_write_gid_i(attr_write_gid_i),
      .attr_write_world_x_q16_i(attr_write_world_x_q16_i),.attr_write_world_y_q16_i(attr_write_world_y_q16_i),
      .attr_write_world_z_q16_i(attr_write_world_z_q16_i),.attr_write_qw_q20_i(attr_write_qw_q20_i),
      .attr_write_qx_q20_i(attr_write_qx_q20_i),.attr_write_qy_q20_i(attr_write_qy_q20_i),
      .attr_write_qz_q20_i(attr_write_qz_q20_i),.attr_write_scale_x_q20_i(attr_write_scale_x_q20_i),
      .attr_write_scale_y_q20_i(attr_write_scale_y_q20_i),.attr_write_scale_z_q20_i(attr_write_scale_z_q20_i),
      .attr_write_opacity_q12_i(attr_write_opacity_q12_i),.attr_write_coeff_q12_flat_i(attr_write_coeff_q12_flat_i),
      .cfg_r00_q20_i(cfg_r00_q20_i),.cfg_r01_q20_i(cfg_r01_q20_i),.cfg_r02_q20_i(cfg_r02_q20_i),
      .cfg_r10_q20_i(cfg_r10_q20_i),.cfg_r11_q20_i(cfg_r11_q20_i),.cfg_r12_q20_i(cfg_r12_q20_i),
      .cfg_r20_q20_i(cfg_r20_q20_i),.cfg_r21_q20_i(cfg_r21_q20_i),.cfg_r22_q20_i(cfg_r22_q20_i),
      .cfg_tx_q16_i(cfg_tx_q16_i),.cfg_ty_q16_i(cfg_ty_q16_i),.cfg_tz_q16_i(cfg_tz_q16_i),
      .cfg_camera_x_q16_i(cfg_camera_x_q16_i),.cfg_camera_y_q16_i(cfg_camera_y_q16_i),
      .cfg_camera_z_q16_i(cfg_camera_z_q16_i),.cfg_fx_q16_i(cfg_fx_q16_i),.cfg_fy_q16_i(cfg_fy_q16_i),
      .cfg_cx_q16_i(cfg_cx_q16_i),.cfg_cy_q16_i(cfg_cy_q16_i),.cfg_near_q16_i(cfg_near_q16_i),
      .cfg_far_q16_i(cfg_far_q16_i),.cfg_regularizer_q8_i(cfg_regularizer_q8_i),
      .cfg_depth_pivot0_q16_i(cfg_depth_pivot0_q16_i),.cfg_depth_pivot1_q16_i(cfg_depth_pivot1_q16_i),
      .cfg_depth_pivot2_q16_i(cfg_depth_pivot2_q16_i),.cfg_image_width_i(image_width),
      .cfg_image_height_i(image_height),.commit_valid_o(core_commit_valid),.commit_ready_i(core_commit_ready),
      .commit_task_id_o(core_commit_task),.commit_block_id_o(core_commit_block),.commit_gid_o(core_commit_gid),
      .commit_epoch_id_o(core_commit_epoch),.commit_alpha_q12_o(core_commit_alpha),
      .commit_pass_alpha_o(core_commit_pass),.commit_pixel_id_o(core_commit_pixel),
      .commit_r_q12_o(core_commit_r),.commit_g_q12_o(core_commit_g),.commit_b_q12_o(core_commit_b),
      .commit_t_q16_o(core_commit_t),.commit_newly_terminated_o(core_commit_terminated),
      .projection_active_mask_o(projection_active_mask_o),.sh_active_mask_o(sh_active_mask_o),
      .raster_active_mask_o(raster_active_mask_o),.attribute_read_pulse_o(attribute_read_pulse_o),
      .event_group_pressure_o(event_group_pressure),.event_sort_busy_o(event_sort_busy),
      .event_projection_busy_o(event_projection_busy),.event_raster_busy_o(event_raster_busy),
      .event_block_candidate_o(event_block_candidate),.event_shape_block_reject_o(event_shape_block_reject),
      .event_terminated_skip_o(event_terminated_skip),
      .shared_pe_group_grant_o(shared_pe_group_grant),
      .shared_pe_projection_grant_o(shared_pe_projection_grant),
      .shared_pe_raster_grant_o(shared_pe_raster_grant),.shared_pe_group_stall_o(shared_pe_group_stall),
      .shared_pe_projection_stall_o(shared_pe_projection_stall),.shared_pe_raster_stall_o(shared_pe_raster_stall),
      .shared_pe_utilization_o(shared_pe_utilization),.shared_pe_clock_enable_o(shared_pe_clock_enable),
      .shared_pe_busy_o(shared_pe_busy),
      .sort_work_totals_o(sort_work_totals),
      .state_miss_req_valid_o(state_miss_req_valid),.state_miss_req_ready_i(state_miss_req_ready),
      .state_miss_req_tag_o(state_miss_req_tag),.state_miss_req_pixel_id_o(state_miss_req_pixel),.state_miss_rsp_valid_i(state_miss_rsp_valid),
      .state_miss_rsp_tag_i(state_miss_rsp_tag),
      .state_miss_rsp_ready_o(state_miss_rsp_ready),.state_miss_rsp_error_i(state_miss_rsp_error),
      .state_miss_rsp_data_i(state_miss_rsp_data),.state_cache_error_o(state_cache_error),
      .state_cache_idle_o(state_cache_idle));

    // Atomic software-triggered snapshots of lifetime wrapping sorter counters.
    // Fresh logical frame rebases; continuations preserve the measuring interval.
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin sort_work_base_q<=0;sort_work_snapshot_q<=0;sort_snapshot_sequence_q<=0;end
      else if(soft_reset_pulse)begin sort_work_base_q<=0;sort_work_snapshot_q<=0;sort_snapshot_sequence_q<=0;end
      else if(batch_start&&!continue_pulse)begin
        sort_work_base_q<=sort_work_totals;sort_work_snapshot_q<=0;sort_snapshot_sequence_q<=0;
      end else begin
        if(sort_clear_pulse)sort_work_base_q<=sort_work_totals;
        if(sort_snapshot_pulse)begin
          for(integer i=0;i<12;i=i+1)
            sort_work_snapshot_q[32*i+:32]<=sort_work_totals[32*i+:32]-sort_work_base_q[32*i+:32];
          sort_snapshot_sequence_q<=sort_snapshot_sequence_q+1'b1;
        end
      end
    end

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        done_sticky_q<=0;error_sticky_q<='0;irq_pending_q<='0;frame_done_pulse_o<=0;
        completion_pending_q<=0;completed_core_error_q<=0;
        logical_frame_open_q<=0;active_batch_more_q<=0;
        logical_output_base_q<=0;logical_image_width_q<=0;logical_image_height_q<=0;
        perf_cycle_count_o<=0;perf_commit_count_o<=0;perf_state_miss_count_o<=0;
        perf_state_read_stall_count_o<=0;perf_output_stall_count_o<=0;
        shared_pe_group_grant_count_q<=0;shared_pe_projection_grant_count_q<=0;
        shared_pe_raster_grant_count_q<=0;shared_pe_group_stall_count_q<=0;
        shared_pe_projection_stall_count_q<=0;shared_pe_raster_stall_count_q<=0;
        shared_pe_utilization_count_q<=0;
      end
      else begin
        frame_done_pulse_o<=0;
        if(status_clear_pulse||soft_reset_pulse)begin
          done_sticky_q<=0;error_sticky_q<='0;irq_pending_q<='0;
          if(soft_reset_pulse)logical_frame_open_q<=0;
        end
        if(batch_start)begin
          active_batch_more_q<=more_batches_pulse;
          completed_core_error_q<=0;
          if(!continue_pulse)begin
            logical_output_base_q<=output_base;logical_image_width_q<=image_width;
            logical_image_height_q<=image_height;
            if(more_batches_pulse)logical_frame_open_q<=1;
          end
          if(!continue_pulse)begin
             perf_cycle_count_o<=0;perf_commit_count_o<=0;perf_state_miss_count_o<=0;
             perf_state_read_stall_count_o<=0;perf_output_stall_count_o<=0;
             shared_pe_group_grant_count_q<=0;shared_pe_projection_grant_count_q<=0;
             shared_pe_raster_grant_count_q<=0;shared_pe_group_stall_count_q<=0;
             shared_pe_projection_stall_count_q<=0;shared_pe_raster_stall_count_q<=0;
             shared_pe_utilization_count_q<=0;
          end
        end
        if(!(batch_start&&!continue_pulse))begin
          if(frame_busy_o)perf_cycle_count_o<=sat_inc(perf_cycle_count_o);
          if(core_commit_valid&&core_commit_ready)perf_commit_count_o<=sat_inc(perf_commit_count_o);
          if(state_miss_req_valid&&state_miss_req_ready)perf_state_miss_count_o<=sat_inc(perf_state_miss_count_o);
          if(state_miss_req_valid&&!state_miss_req_ready)
            perf_state_read_stall_count_o<=sat_inc(perf_state_read_stall_count_o);
          if(core_commit_valid&&!core_commit_ready)perf_output_stall_count_o<=sat_inc(perf_output_stall_count_o);
          if(shared_pe_group_grant)shared_pe_group_grant_count_q<=sat_inc32(shared_pe_group_grant_count_q);
          if(shared_pe_projection_grant)shared_pe_projection_grant_count_q<=sat_inc32(shared_pe_projection_grant_count_q);
          if(shared_pe_raster_grant)shared_pe_raster_grant_count_q<=sat_inc32(shared_pe_raster_grant_count_q);
          if(shared_pe_group_stall)shared_pe_group_stall_count_q<=sat_inc32(shared_pe_group_stall_count_q);
          if(shared_pe_projection_stall)shared_pe_projection_stall_count_q<=sat_inc32(shared_pe_projection_stall_count_q);
          if(shared_pe_raster_stall)shared_pe_raster_stall_count_q<=sat_inc32(shared_pe_raster_stall_count_q);
          if(shared_pe_utilization)shared_pe_utilization_count_q<=sat_inc32(shared_pe_utilization_count_q);
        end
        if(core_frame_done)begin completion_pending_q<=1;completed_core_error_q<=frame_error_status_live;end
        if((completion_pending_q||core_frame_done)&&!write_busy&&!state_read_busy&&state_cache_idle)begin
          completion_pending_q<=0;
          if(active_batch_more_q&&!batch_failed)logical_frame_open_q<=1;
          else begin frame_done_pulse_o<=1;logical_frame_open_q<=0;end
        end
        if(start_pulse&&!frame_busy_o&&!soft_reset_pulse&&!batch_sequence_valid)begin
          frame_done_pulse_o<=1;done_sticky_q<=1;error_sticky_q[18]<=1;
          irq_pending_q<=2'b11;logical_frame_open_q<=0;
        end
        if(frame_done_pulse_o)begin
          done_sticky_q<=1;irq_pending_q[0]<=1;
          if(|completed_core_error_q||dma_error||attr_dma_error||write_error||state_read_error)begin
            error_sticky_q<=error_sticky_q|{14'b0,state_read_error_status,write_error_status,
              attr_dma_error_status,dma_error_status,completed_core_error_q};
            irq_pending_q[1]<=1;
          end
        end
      end
    end
`ifndef SYNTHESIS
    initial begin
      assert((STATE_WINDOW_ENTRIES==2&&(STATE_MSHR_COUNT==1||STATE_MSHR_COUNT==2))||
             (STATE_WINDOW_ENTRIES==4&&STATE_MSHR_COUNT==4));
      assert(AXI_ID_W>=2||STATE_MSHR_COUNT<4);
    end
    assert property(@(posedge clk_i)disable iff(!rst_ni)irq_o|->|(irq_pending_q&irq_enable));
    // Automatic recommendations may alter the active resource mode only through
    // the frame pipeline's existing safe epoch-boundary commit pulse.
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      $changed(active_mode_o)|->mode_commit_done);
`endif
endmodule
