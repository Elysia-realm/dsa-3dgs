`timescale 1ns/1ps
module tb_gs_accel_system_axi_mean;
`include "verification/rtl/t06_scratch_signals.svh"
  localparam GID_W=8,COEFF_W=18,FLAT_W=3*16*COEFF_W;
  logic clk_i=0,rst_ni=0,psel_i=0,penable_i=0,pwrite_i=0;logic[11:0]paddr_i=0;logic[31:0]pwdata_i=0;logic[3:0]pstrb_i=0;logic[31:0]prdata_o;logic pready_o,pslverr_o,irq_o;
  logic source_valid_i=0,source_ready_o;logic[GID_W-1:0]source_gid_i=0;logic signed[26:0]source_world_x_q16_i=0,source_world_y_q16_i=0,source_world_z_q16_i=0;logic source_last_i=0;
  logic attr_clear_valid_i=0,attr_write_en_i=0;logic[GID_W-1:0]attr_write_gid_i=1;logic signed[26:0]attr_write_world_x_q16_i=0,attr_write_world_y_q16_i=0,attr_write_world_z_q16_i=131072;
  logic signed[21:0]attr_write_qw_q20_i=1048576,attr_write_qx_q20_i=0,attr_write_qy_q20_i=0,attr_write_qz_q20_i=0;logic[23:0]attr_write_scale_x_q20_i=1048576,attr_write_scale_y_q20_i=1048576,attr_write_scale_z_q20_i=1048576;logic[12:0]attr_write_opacity_q12_i=4096;logic[FLAT_W-1:0]attr_write_coeff_q12_flat_i=0;
  logic signed[21:0]cfg_r00_q20_i=1048576,cfg_r01_q20_i=0,cfg_r02_q20_i=0,cfg_r10_q20_i=0,cfg_r11_q20_i=1048576,cfg_r12_q20_i=0,cfg_r20_q20_i=0,cfg_r21_q20_i=0,cfg_r22_q20_i=1048576;
  logic signed[26:0]cfg_tx_q16_i=0,cfg_ty_q16_i=0,cfg_tz_q16_i=0,cfg_camera_x_q16_i=0,cfg_camera_y_q16_i=0,cfg_camera_z_q16_i=0;logic signed[32:0]cfg_fx_q16_i=262144,cfg_fy_q16_i=262144,cfg_cx_q16_i=1048576,cfg_cy_q16_i=1048576;
  logic signed[26:0]cfg_near_q16_i=13107,cfg_far_q16_i=65536000;logic[31:0]cfg_regularizer_q8_i=77;logic signed[26:0]cfg_depth_pivot0_q16_i=196608,cfg_depth_pivot1_q16_i=262144,cfg_depth_pivot2_q16_i=327680;
  logic commit_valid_o,commit_ready_i=1;logic[31:0]commit_task_id_o,commit_block_id_o;logic[GID_W-1:0]commit_gid_o;logic[15:0]commit_epoch_id_o;logic[12:0]commit_alpha_q12_o;logic commit_pass_alpha_o;logic[31:0]commit_pixel_id_o;logic[12:0]commit_r_q12_o,commit_g_q12_o,commit_b_q12_o;logic[15:0]commit_t_q16_o;logic commit_newly_terminated_o;logic[0:0]projection_active_mask_o,sh_active_mask_o,raster_active_mask_o;logic attribute_read_pulse_o,frame_busy_o,frame_done_pulse_o,frame_error_o;logic[31:0]frame_error_status_o;logic[1:0]active_mode_o;logic[15:0]epoch_id_o;
  logic[63:0]perf_cycle_count_o,perf_commit_count_o,perf_state_miss_count_o,perf_state_read_stall_count_o,perf_output_stall_count_o;
  logic[1:0]m_axi_mean_arid_o,m_axi_mean_rid_i=0;logic[63:0]m_axi_mean_araddr_o;logic[7:0]m_axi_mean_arlen_o;logic[2:0]m_axi_mean_arsize_o;logic[1:0]m_axi_mean_arburst_o;logic m_axi_mean_arvalid_o,m_axi_mean_arready_i=0;logic[127:0]m_axi_mean_rdata_i=0;logic[1:0]m_axi_mean_rresp_i=0;logic m_axi_mean_rlast_i=0,m_axi_mean_rvalid_i=0,m_axi_mean_rready_o;
  logic[1:0]m_axi_camera_arid_o,m_axi_camera_rid_i=0;logic[63:0]m_axi_camera_araddr_o;logic[7:0]m_axi_camera_arlen_o;logic[2:0]m_axi_camera_arsize_o;logic[1:0]m_axi_camera_arburst_o;logic m_axi_camera_arvalid_o,m_axi_camera_arready_i=0;logic[127:0]m_axi_camera_rdata_i=0;logic[1:0]m_axi_camera_rresp_i=0;logic m_axi_camera_rlast_i=0,m_axi_camera_rvalid_i=0,m_axi_camera_rready_o;
  logic[1:0]m_axi_attr_arid_o,m_axi_attr_rid_i=0;logic[63:0]m_axi_attr_araddr_o;logic[7:0]m_axi_attr_arlen_o;logic[2:0]m_axi_attr_arsize_o;logic[1:0]m_axi_attr_arburst_o;logic m_axi_attr_arvalid_o,m_axi_attr_arready_i=0;logic[127:0]m_axi_attr_rdata_i=0;logic[1:0]m_axi_attr_rresp_i=0;logic m_axi_attr_rlast_i=0,m_axi_attr_rvalid_i=0,m_axi_attr_rready_o;
  logic[1:0]m_axi_out_awid_o,m_axi_out_bid_i=0;logic[63:0]m_axi_out_awaddr_o;logic[7:0]m_axi_out_awlen_o;logic[2:0]m_axi_out_awsize_o;logic[1:0]m_axi_out_awburst_o;logic m_axi_out_awvalid_o,m_axi_out_awready_i=1;logic[127:0]m_axi_out_wdata_o;logic[15:0]m_axi_out_wstrb_o;logic m_axi_out_wlast_o,m_axi_out_wvalid_o,m_axi_out_wready_i=1;logic[1:0]m_axi_out_bresp_i=0;logic m_axi_out_bvalid_i=0,m_axi_out_bready_o;logic out_aw_seen=0,out_w_seen=0;integer output_writes=0,out_b_delay=-1;
  logic[1:0]m_axi_state_arid_o,m_axi_state_rid_i=0;logic[63:0]m_axi_state_araddr_o;
  logic[7:0]m_axi_state_arlen_o;logic[2:0]m_axi_state_arsize_o;logic[1:0]m_axi_state_arburst_o;
  logic m_axi_state_arvalid_o,m_axi_state_arready_i=1;logic[127:0]m_axi_state_rdata_i=0;
  logic[1:0]m_axi_state_rresp_i=0;logic m_axi_state_rlast_i=1,m_axi_state_rvalid_i=0,m_axi_state_rready_o;
  always#5 clk_i=~clk_i;
  integer dma_abort_wait=0;
  always@(posedge clk_i)if(rst_ni&&dut.source_end_valid&&!dut.source_end_ready)dma_abort_wait<=dma_abort_wait+1;
  gs_accel_system_top #(.ATTR_DEPTH(8),.LANES(1),.GROUP_CAPACITY(4),.SORT_CAPACITY(4),.USE_FINAL_RGB_DMA(0),
    .USE_BITONIC_SORT(0),.USE_SHARED_RASTER_PE(0),
    .STATE_ENTRIES(4096),.GID_W(GID_W),.SEQ_W(8),.USE_AXI_MEAN_DMA(1),.USE_AXI_CAMERA_DMA(0),.USE_AXI_ATTR_DMA(1),
    .USE_AXI_PIXEL_WRITE(1),.USE_STATE_CACHE_BACKEND(0),.USE_PIXEL_MULTIWRITE_BUFFER(0))dut(.*);
  always@(posedge clk_i)begin
    if(!rst_ni)begin out_aw_seen<=0;out_w_seen<=0;m_axi_out_bvalid_i<=0;output_writes<=0;out_b_delay<=-1;end
    else begin
      if(m_axi_out_awvalid_o&&m_axi_out_awready_i)out_aw_seen<=1;
      if(m_axi_out_wvalid_o&&m_axi_out_wready_i)out_w_seen<=1;
      if(out_b_delay<0&&(out_aw_seen||m_axi_out_awvalid_o)&&(out_w_seen||m_axi_out_wvalid_o))begin
        out_aw_seen<=0;out_w_seen<=0;out_b_delay<=3;output_writes<=output_writes+1;
      end else if(out_b_delay>0)out_b_delay<=out_b_delay-1;
      else if(out_b_delay==0)begin m_axi_out_bvalid_i<=1;out_b_delay<=-1;end
      if(m_axi_out_bvalid_i&&m_axi_out_bready_o)m_axi_out_bvalid_i<=0;
      if(frame_done_pulse_o&&(m_axi_out_bvalid_i||out_b_delay>=0))$fatal(1,"system done preceded final B response");
    end
  end
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic apb_write(input[11:0]addr,input[31:0]data);begin paddr_i=addr;pwdata_i=data;pstrb_i=4'hf;pwrite_i=1;psel_i=1;penable_i=1;tick();psel_i=0;penable_i=0;pwrite_i=0;pstrb_i=0;end endtask
  task automatic apb_read(input[11:0]addr,output[31:0]data);begin paddr_i=addr;pwrite_i=0;psel_i=1;penable_i=1;#1;data=prdata_o;psel_i=0;penable_i=0;#1;end endtask
  task automatic accept_ar;begin while(!m_axi_mean_arvalid_o)tick();m_axi_mean_arready_i=1;tick();m_axi_mean_arready_i=0;end endtask
  task automatic send_beat(input[31:0]gid,input last,input[1:0]resp);begin
    @(negedge clk_i);m_axi_mean_rdata_i=0;m_axi_mean_rdata_i[31:0]=gid;m_axi_mean_rdata_i[112:86]=27'd131072;
    m_axi_mean_rlast_i=last;m_axi_mean_rresp_i=resp;m_axi_mean_rvalid_i=1;
    do @(posedge clk_i);while(!m_axi_mean_rready_o);#1;m_axi_mean_rvalid_i=0;m_axi_mean_rresp_i=0;
  end endtask
  task automatic send_attr_beat(input[127:0]data,input last,input[1:0]resp);begin
    @(negedge clk_i);m_axi_attr_rdata_i=data;m_axi_attr_rlast_i=last;m_axi_attr_rresp_i=resp;m_axi_attr_rvalid_i=1;
    do @(posedge clk_i);while(!m_axi_attr_rready_o);#1;m_axi_attr_rvalid_i=0;m_axi_attr_rresp_i=0;
  end endtask
  initial begin integer timeout,commits,i;logic[31:0]rd;logic[1151:0]attribute_record;
    repeat(2)tick();rst_ni=1;tick();attr_write_coeff_q12_flat_i[0+:COEFF_W]=18'sd4096;
    attr_write_en_i=1;tick();attr_write_en_i=0;
    apb_write(12'h010,32'h00000ff0);apb_write(12'h014,0);apb_write(12'h038,1);
    apb_write(12'h03c,32'h00004000);apb_write(12'h040,0);
    apb_write(12'h028,{16'd48,16'd64});apb_write(12'h02c,3);apb_write(12'h008,3);apb_write(12'h000,1);
    while(!m_axi_mean_arvalid_o)tick();
    if(m_axi_mean_araddr_o!==64'hff0||m_axi_mean_arlen_o!==0)$fatal(1,"system DMA AR mismatch addr=%h len=%0d",m_axi_mean_araddr_o,m_axi_mean_arlen_o);
    m_axi_mean_arready_i=1;tick();m_axi_mean_arready_i=0;
    send_beat(1,1,0);
    while(!m_axi_attr_arvalid_o)tick();
    if(m_axi_attr_araddr_o!==64'h4090||m_axi_attr_arlen_o!==8)$fatal(1,"attribute AR mismatch");
    m_axi_attr_arready_i=1;tick();m_axi_attr_arready_i=0;
    attribute_record='0;
    attribute_record[1117:0]={attr_write_world_x_q16_i,attr_write_world_y_q16_i,attr_write_world_z_q16_i,
      attr_write_qw_q20_i,attr_write_qx_q20_i,attr_write_qy_q20_i,attr_write_qz_q20_i,
      attr_write_scale_x_q20_i,attr_write_scale_y_q20_i,attr_write_scale_z_q20_i,
      attr_write_opacity_q12_i,attr_write_coeff_q12_flat_i};
    for(i=0;i<9;i=i+1)send_attr_beat(attribute_record[i*128+:128],i==8,0);
    commits=0;timeout=0;
    while(!frame_done_pulse_o&&timeout<5000)begin if(commit_valid_o)commits=commits+1;tick();timeout=timeout+1;end
    tick();if(timeout>=5000||commits==0||output_writes==0||frame_error_o||!irq_o)
      $fatal(1,"AXI-fed normal frame/writeback failed");
    apb_write(12'h000,4);apb_write(12'h038,2);apb_write(12'h000,1);accept_ar();send_beat(1,0,2'b10);
    timeout=0;while(!frame_done_pulse_o&&timeout<200)begin tick();timeout=timeout+1;end
    tick();if(timeout>=200||!frame_error_o||frame_busy_o||!frame_error_status_o[10])$fatal(1,"AXI error did not terminate frame");
    apb_read(12'h030,rd);if(!rd[10])$fatal(1,"AXI status not visible through APB");
    // A complete-attribute read failure uses a distinct system error bit.
    apb_write(12'h000,4);apb_write(12'h038,1);apb_write(12'h000,1);accept_ar();send_beat(1,1,0);
    while(!m_axi_attr_arvalid_o)tick();m_axi_attr_arready_i=1;tick();m_axi_attr_arready_i=0;
    send_attr_beat(0,1,2'b10);timeout=0;
    while(!frame_done_pulse_o&&timeout<200)begin tick();timeout=timeout+1;end
    tick();if(timeout>=200||!frame_error_status_o[12])$fatal(1,"attribute AXI error did not terminate frame");
    apb_read(12'h030,rd);if(!rd[12])$fatal(1,"attribute AXI status missing");
    apb_write(12'h000,4);apb_write(12'h038,0);apb_write(12'h000,1);
    timeout=0;while(!frame_done_pulse_o&&timeout<100)begin tick();timeout=timeout+1;end
    tick();if(timeout>=100||frame_busy_o||frame_error_o)$fatal(1,"empty AXI frame failed");
    // A late mean RRESP error must drain two already accepted depth contexts
    // before switching the shared P port, then retire the valid prefix.
    dma_abort_wait=0;apb_write(12'h000,4);apb_write(12'h010,32'h2000);
    apb_write(12'h038,4);apb_write(12'h000,1);accept_ar();
    send_beat(1,0,0);send_beat(1,0,0);send_beat(0,0,2'b10);send_beat(0,1,0);
    for(i=0;i<2;i=i+1)begin
      timeout=0;while(!m_axi_attr_arvalid_o&&timeout<500)begin tick();timeout=timeout+1;end
      if(timeout>=500)$fatal(1,"valid DMA prefix was lost after late error");
      m_axi_attr_arready_i=1;tick();m_axi_attr_arready_i=0;
      for(integer j=0;j<9;j=j+1)send_attr_beat(attribute_record[j*128+:128],j==8,0);
    end
    commits=0;timeout=0;while(!frame_done_pulse_o&&timeout<7000)begin
      if(commit_valid_o)commits=commits+1;tick();timeout=timeout+1;
    end
    tick();apb_read(12'h068,rd);
    if(timeout>=7000||dma_abort_wait==0||commits==0||frame_busy_o||!frame_error_status_o[10]||rd!=24||dut.u_frame.pre_inflight_q!=0)
      $fatal(1,"late DMA error recovery failed wait=%0d commits=%0d P=%0d error=%h",dma_abort_wait,commits,rd,frame_error_status_o);
    // Empty next frame is a production-level check for stale queued work.
    apb_write(12'h000,4);apb_write(12'h038,0);apb_write(12'h000,1);timeout=0;
    while(!frame_done_pulse_o&&timeout<100)begin
      if(m_axi_attr_arvalid_o||commit_valid_o)$fatal(1,"late error leaked work into next frame");
      tick();timeout=timeout+1;
    end
    tick();if(timeout>=100||frame_busy_o||frame_error_o)$fatal(1,"post-error empty frame failed");
    $display("PREPASS_DMA_ABORT prefix=2 end_wait_cycles=%0d P=24 next_empty_recovery=1",dma_abort_wait);
    $display("PASS: tb_gs_accel_system_axi_mean");$finish;
  end
endmodule
