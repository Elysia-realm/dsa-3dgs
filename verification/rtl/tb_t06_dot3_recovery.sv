`timescale 1ns/1ps
module tb_t06_dot3_recovery;
`include "verification/rtl/t06_scratch_signals.svh"
  localparam GID_W=32,COEFF_W=18,FLAT_W=3*16*COEFF_W;
  logic clk_i=0,rst_ni=0,psel_i=0,penable_i=0,pwrite_i=0;logic[11:0]paddr_i=0;
  logic[31:0]pwdata_i=0;logic[3:0]pstrb_i=0;logic[31:0]prdata_o;logic pready_o,pslverr_o,irq_o;
  logic source_valid_i=0,source_ready_o;logic[GID_W-1:0]source_gid_i=0;
  logic signed[26:0]source_world_x_q16_i=0,source_world_y_q16_i=0,source_world_z_q16_i=0;logic source_last_i=0;
  logic attr_clear_valid_i=0,attr_write_en_i=0;logic[GID_W-1:0]attr_write_gid_i=0;
  logic signed[26:0]attr_write_world_x_q16_i=0,attr_write_world_y_q16_i=0,attr_write_world_z_q16_i=0;
  logic signed[21:0]attr_write_qw_q20_i=0,attr_write_qx_q20_i=0,attr_write_qy_q20_i=0,attr_write_qz_q20_i=0;
  logic[23:0]attr_write_scale_x_q20_i=0,attr_write_scale_y_q20_i=0,attr_write_scale_z_q20_i=0;
  logic[12:0]attr_write_opacity_q12_i=0;logic[FLAT_W-1:0]attr_write_coeff_q12_flat_i=0;
  // Deliberately different from the descriptor; production must consume DMA data.
  logic signed[21:0]cfg_r00_q20_i=1,cfg_r01_q20_i=2,cfg_r02_q20_i=3,cfg_r10_q20_i=4,cfg_r11_q20_i=5,cfg_r12_q20_i=6;
  logic signed[21:0]cfg_r20_q20_i=7,cfg_r21_q20_i=8,cfg_r22_q20_i=9;
  logic signed[26:0]cfg_tx_q16_i=10,cfg_ty_q16_i=11,cfg_tz_q16_i=12,cfg_camera_x_q16_i=13,cfg_camera_y_q16_i=14,cfg_camera_z_q16_i=15;
  logic signed[32:0]cfg_fx_q16_i=16,cfg_fy_q16_i=17,cfg_cx_q16_i=18,cfg_cy_q16_i=19;
  logic signed[26:0]cfg_near_q16_i=20,cfg_far_q16_i=21;logic[34:0]cfg_regularizer_q8_i=22;
  logic signed[26:0]cfg_depth_pivot0_q16_i=23,cfg_depth_pivot1_q16_i=24,cfg_depth_pivot2_q16_i=25;
  logic commit_valid_o,commit_ready_i=1;logic[31:0]commit_task_id_o,commit_block_id_o;logic[GID_W-1:0]commit_gid_o;
  logic[15:0]commit_epoch_id_o;logic[12:0]commit_alpha_q12_o;logic commit_pass_alpha_o;logic[31:0]commit_pixel_id_o;
  logic[12:0]commit_r_q12_o,commit_g_q12_o,commit_b_q12_o;logic[15:0]commit_t_q16_o;logic commit_newly_terminated_o;
  logic[3:0]projection_active_mask_o,sh_active_mask_o,raster_active_mask_o;logic attribute_read_pulse_o;
  logic frame_busy_o,frame_done_pulse_o,frame_error_o;logic[31:0]frame_error_status_o;logic[1:0]active_mode_o;logic[15:0]epoch_id_o;
  logic[63:0]perf_cycle_count_o,perf_commit_count_o,perf_state_miss_count_o,perf_state_read_stall_count_o,perf_output_stall_count_o;

  logic[1:0]m_axi_mean_arid_o,m_axi_mean_rid_i=0;logic[63:0]m_axi_mean_araddr_o;logic[7:0]m_axi_mean_arlen_o;
  logic[2:0]m_axi_mean_arsize_o;logic[1:0]m_axi_mean_arburst_o;logic m_axi_mean_arvalid_o,m_axi_mean_arready_i=1;
  logic[127:0]m_axi_mean_rdata_i=0;logic[1:0]m_axi_mean_rresp_i=0;logic m_axi_mean_rlast_i=0,m_axi_mean_rvalid_i=0,m_axi_mean_rready_o;
  logic[1:0]m_axi_camera_arid_o,m_axi_camera_rid_i=3;logic[63:0]m_axi_camera_araddr_o;logic[7:0]m_axi_camera_arlen_o;
  logic[2:0]m_axi_camera_arsize_o;logic[1:0]m_axi_camera_arburst_o;logic m_axi_camera_arvalid_o,m_axi_camera_arready_i=1;
  logic[127:0]m_axi_camera_rdata_i=0;logic[1:0]m_axi_camera_rresp_i=0;logic m_axi_camera_rlast_i=0,m_axi_camera_rvalid_i=0,m_axi_camera_rready_o;
  logic[1:0]m_axi_attr_arid_o,m_axi_attr_rid_i=0;logic[63:0]m_axi_attr_araddr_o;logic[7:0]m_axi_attr_arlen_o;
  logic[2:0]m_axi_attr_arsize_o;logic[1:0]m_axi_attr_arburst_o;logic m_axi_attr_arvalid_o,m_axi_attr_arready_i=0;
  logic[127:0]m_axi_attr_rdata_i=0;logic[1:0]m_axi_attr_rresp_i=0;logic m_axi_attr_rlast_i=0,m_axi_attr_rvalid_i=0,m_axi_attr_rready_o;
  logic[1:0]m_axi_out_awid_o,m_axi_out_bid_i=0;logic[63:0]m_axi_out_awaddr_o;logic[7:0]m_axi_out_awlen_o;
  logic[2:0]m_axi_out_awsize_o;logic[1:0]m_axi_out_awburst_o;logic m_axi_out_awvalid_o,m_axi_out_awready_i=0;
  logic[127:0]m_axi_out_wdata_o;logic[15:0]m_axi_out_wstrb_o;logic m_axi_out_wlast_o,m_axi_out_wvalid_o,m_axi_out_wready_i=0;
  logic[1:0]m_axi_out_bresp_i=0;logic m_axi_out_bvalid_i=0,m_axi_out_bready_o;
  logic[1:0]m_axi_state_arid_o,m_axi_state_rid_i=0;logic[63:0]m_axi_state_araddr_o;logic[7:0]m_axi_state_arlen_o;
  logic[2:0]m_axi_state_arsize_o;logic[1:0]m_axi_state_arburst_o;logic m_axi_state_arvalid_o,m_axi_state_arready_i=0;
  logic[127:0]m_axi_state_rdata_i=0;logic[1:0]m_axi_state_rresp_i=0;logic m_axi_state_rlast_i=0,m_axi_state_rvalid_i=0,m_axi_state_rready_o;

  logic[63:0]camera_words[0:27];integer camera_cursor=0,camera_left=0,camera_ar_count=0;
  logic[7:0]rgb_mem[0:15];integer rgb_aw_count=0,rgb_w_count=0;logic[1:0]out_id_q=0;
  localparam MAX_COUNT=32;integer workload_count=32;
  integer read_latency=2,read_gap=1,ready_period=4,ready_low=1,write_response_latency=6;
`include "verification/rtl/t06_scratch_memory.svh"
  integer mean_cursor=0,mean_left=0,sorted_count=0;
  integer fault=0;logic armed=0,injected=0,reverse_camera=0;
  always @(negedge clk_i)begin
    m_axi_qsu_rresp_i=0;m_axi_qsu_bresp_i=0;
    if(armed&&!injected)begin
      if(fault==1)m_axi_qsu_bresp_i=2;
      if(fault==2&&dut.u_frame.g_auto_qsu.u_qsu.state_q==5)m_axi_qsu_rresp_i=2;
      if(fault==3&&dut.u_frame.g_auto_qsu.u_qsu.state_q==13&&dut.u_frame.g_auto_qsu.u_qsu.leaf_pos_q==1)m_axi_qsu_rresp_i=2;
      if(fault==7&&dut.u_frame.g_auto_qsu.u_qsu.state_q==8)m_axi_qsu_rresp_i=2;
      if(fault==8&&dut.u_frame.g_auto_qsu.u_qsu.state_q==8)m_axi_qsu_bresp_i=2;
      if(fault==9&&dut.u_frame.g_auto_qsu.u_qsu.state_q==13&&dut.qsu_stats[64+:32]>=2&&dut.u_frame.g_auto_qsu.u_qsu.leaf_pos_q==1)m_axi_qsu_rresp_i=2;
    end
  end
  always @(posedge clk_i)if(rst_ni)begin
    if((m_axi_qsu_bvalid_i&&m_axi_qsu_bready_o&&m_axi_qsu_bresp_i==2)||
       (m_axi_qsu_rvalid_i&&m_axi_qsu_rready_o&&m_axi_qsu_rresp_i==2))injected<=1;
    if(m_axi_mean_arvalid_o&&m_axi_mean_arready_i)begin
      mean_cursor<=(m_axi_mean_araddr_o-64'h1000)>>4;mean_left<=m_axi_mean_arlen_o+1;
    end
    if(!m_axi_mean_rvalid_i&&mean_left>0)begin
      m_axi_mean_rdata_i<={15'd0,27'(131072+(31-mean_cursor)*1024),27'd0,27'd0,32'(mean_cursor)};
      m_axi_mean_rlast_i<=mean_left==1;m_axi_mean_rvalid_i<=1;
    end else if(m_axi_mean_rvalid_i&&m_axi_mean_rready_o)begin
      m_axi_mean_rvalid_i<=0;mean_cursor<=mean_cursor+1;mean_left<=mean_left-1;
    end
    if(dut.u_frame.sorted_valid&&dut.u_frame.sorted_ready)begin
      if(!armed&&dut.u_frame.sorted_gid!=(reverse_camera?sorted_count:31-sorted_count))$fatal(1,"camera/order mismatch %0d gid=%0d",sorted_count,dut.u_frame.sorted_gid);
      sorted_count<=sorted_count+1;
    end
  end
  always#5 clk_i=~clk_i;
  gs_accel_system_top #(.ATTR_DEPTH(32),.LANES(4),.GROUP_CAPACITY(16),.SORT_CAPACITY(16),.USE_FINAL_RGB_DMA(1),
    .USE_BITONIC_SORT(1),.USE_SHARED_RASTER_PE(1),
    .SHARED_P_DOT3(1),.ENABLE_ALPHA_ZERO_SKIP(1),.STATE_WINDOW_ENTRIES(4),.STATE_MSHR_COUNT(4),.ENABLE_RESPONSE_BLEND_BYPASS(1),.ENABLE_BLEND_COMMIT_BYPASS(1),
    .STATE_ENTRIES(4),.GID_W(GID_W),.SEQ_W(32),.USE_AXI_MEAN_DMA(1),.USE_AXI_CAMERA_DMA(1),
    .USE_AXI_ATTR_DMA(0),.USE_AXI_PIXEL_WRITE(1),.USE_STATE_CACHE_BACKEND(1))dut(.*);

  always_ff@(posedge clk_i)begin
    if(!rst_ni)begin camera_cursor<=0;camera_left<=0;camera_ar_count<=0;m_axi_camera_rvalid_i<=0;end
    else begin
      if(m_axi_camera_arvalid_o&&m_axi_camera_arready_i)begin
        camera_left<=m_axi_camera_arlen_o+1;camera_cursor<=0;camera_ar_count<=camera_ar_count+1;
      end
      if(!m_axi_camera_rvalid_i&&camera_left>0)begin
        m_axi_camera_rdata_i<={camera_words[2*camera_cursor+1],camera_words[2*camera_cursor]};
        m_axi_camera_rlast_i<=camera_left==1;m_axi_camera_rvalid_i<=1;
      end else if(m_axi_camera_rvalid_i&&m_axi_camera_rready_o)begin
        m_axi_camera_rvalid_i<=0;camera_cursor<=camera_cursor+1;camera_left<=camera_left-1;
      end
    end
  end

  // Shared backing memory model: the empty frame reads an untouched/stale
  // state record and must emit black RGB only after the final continuation.
  always_ff@(posedge clk_i)begin
    if(!rst_ni)begin
      m_axi_state_arready_i<=1;m_axi_state_rvalid_i<=0;m_axi_state_rlast_i<=0;
      m_axi_out_awready_i<=1;m_axi_out_wready_i<=1;m_axi_out_bvalid_i<=0;
      rgb_aw_count<=0;rgb_w_count<=0;out_id_q<=0;
      for(integer j=0;j<16;j=j+1)rgb_mem[j]<=8'haa;
    end else begin
      if(m_axi_state_arvalid_o&&m_axi_state_arready_i)begin
        if(m_axi_state_araddr_o!=64'h0010_0010)$fatal(1,"state scratch address mismatch %h",m_axi_state_araddr_o);
        m_axi_state_rid_i<=m_axi_state_arid_o;m_axi_state_rdata_i<=0;
        m_axi_state_rresp_i<=0;m_axi_state_rlast_i<=1;m_axi_state_rvalid_i<=1;
      end
      if(m_axi_state_rvalid_i&&m_axi_state_rready_o)begin m_axi_state_rvalid_i<=0;m_axi_state_rlast_i<=0;end
      if(m_axi_out_awvalid_o&&m_axi_out_awready_i)begin
        if(m_axi_out_awaddr_o!=64'h0010_0000||m_axi_out_awlen_o!=0)$fatal(1,"RGB AW mismatch");
        out_id_q<=m_axi_out_awid_o;rgb_aw_count<=rgb_aw_count+1;
      end
      if(m_axi_out_wvalid_o&&m_axi_out_wready_i)begin
        for(integer j=0;j<16;j=j+1)if(m_axi_out_wstrb_o[j])rgb_mem[j]<=m_axi_out_wdata_o[j*8+:8];
        if(!m_axi_out_wlast_o)$fatal(1,"single-beat RGB output missing WLAST");
        rgb_w_count<=rgb_w_count+1;m_axi_out_bvalid_i<=1;m_axi_out_bid_i<=out_id_q;
      end
      if(m_axi_out_bvalid_i&&m_axi_out_bready_o)m_axi_out_bvalid_i<=0;
    end
  end

  task automatic init_descriptor;begin
    for(integer i=0;i<28;i=i+1)camera_words[i]=0;
    camera_words[0]=1048576;camera_words[4]=1048576;camera_words[8]=1048576;
    camera_words[12]=101;camera_words[13]=102;camera_words[14]=103;
    camera_words[15]=262144;camera_words[16]=262145;camera_words[17]=65536;camera_words[18]=65537;
    camera_words[19]=13107;camera_words[20]=65536000;camera_words[21]=77;
    camera_words[22]=196608;camera_words[23]=262144;camera_words[24]=327680;
    camera_words[25]=1;camera_words[26]=1;camera_words[27]={32'h47534301,32'd32};
  end endtask
  task automatic apb_write(input[11:0]addr,input[31:0]data);begin
    @(negedge clk_i);psel_i=1;penable_i=0;pwrite_i=1;paddr_i=addr;pwdata_i=data;pstrb_i=4'hf;
    @(negedge clk_i);penable_i=1;@(negedge clk_i);psel_i=0;penable_i=0;pwrite_i=0;pstrb_i=0;
  end endtask
  task automatic wait_idle;integer timeout,idle_cycles;logic seen;begin
    timeout=0;seen=0;idle_cycles=0;
    while((!seen||idle_cycles<3)&&timeout<1000)begin
      @(posedge clk_i);#1;if(frame_busy_o)begin seen=1;idle_cycles=0;end else if(seen)idle_cycles=idle_cycles+1;
      timeout=timeout+1;
    end
    if(!seen||frame_busy_o)$fatal(1,"command did not complete busy=%b core=%b completion=%b final_busy=%b final_started=%b final_start=%b state=%0d",
      frame_busy_o,dut.core_frame_busy,dut.completion_pending_q,dut.final_rgb_busy,
      dut.final_rgb_started_q,dut.final_rgb_start_q,dut.g_final_rgb.u_final_rgb_dma.state_q,
      " active_more=",dut.active_batch_more_q," cmd_more=",dut.cmd_more_q," failed=",dut.batch_failed);
  end endtask

  task automatic wait_complete;
    integer t;begin
      t=0;while(!dut.done_sticky_q&&t<20000)begin @(posedge clk_i);#1;t=t+1;end
      repeat(3)@(negedge clk_i);
      if(t>=20000||frame_busy_o||!irq_o||dut.qsu_rd_busy||dut.qsu_wr_busy||qsu_aw_put!=qsu_b_get||qsu_w_put!=qsu_b_get)
        $fatal(1,"completion/IRQ/drain failed t=%0d error=%h state=%0d sortbusy=%b",t,frame_error_status_o,dut.u_frame.g_auto_qsu.u_qsu.state_q,dut.u_frame.sort_busy);
    end
  endtask
  initial begin
    if(!$value$plusargs("FAULT=%d",fault))fault=0;
    init_descriptor();repeat(3)@(negedge clk_i);rst_ni=1;
    // Nonempty, depth-visible descriptors; opacity zero isolates control tests.
    for(integer j=0;j<32;j=j+1)begin
      @(negedge clk_i);attr_write_gid_i=j;attr_write_world_z_q16_i=131072+(31-j)*1024;
      attr_write_qw_q20_i=1048576;attr_write_scale_x_q20_i=104858;
      attr_write_scale_y_q20_i=104858;attr_write_scale_z_q20_i=104858;attr_write_en_i=1;
    end
    @(negedge clk_i);attr_write_en_i=0;
    apb_write(12'h010,32'h1000);apb_write(12'h018,32'h2000);apb_write(12'h020,32'h00100000);
    apb_write(12'h028,32'h00010001);apb_write(12'h038,32);apb_write(12'h02c,3);
    apb_write(12'h0c0,1);apb_write(12'h0c4,32'h10000000);apb_write(12'h0cc,32);
    apb_write(12'h008,3);
    armed=(fault>=1&&fault<=3)||fault>=7;
    if(fault==4)apb_write(12'h0cc,31);
    if(fault==5)apb_write(12'h0c4,32'h10000001);
    apb_write(12'h000,fault==6?32'h11:32'h1);
    wait_complete();
    if(fault==0)begin
      if(frame_error_o||sorted_count!=32||rgb_aw_count!=1)$fatal(1,"normal frame failed");
    end else begin
      if(!frame_error_o||rgb_aw_count!=0)$fatal(1,"fault was committed as successful RGB %h",frame_error_status_o);
      if((fault<=3||fault>=7)&&(!injected||!frame_error_status_o[1]))$fatal(1,"QSU fault missing");
      if(fault>=4&&fault<=6&&!frame_error_status_o[18])$fatal(1,"invalid autonomous command accepted");
    end
    // A fresh camera changes the complete depth order and advances safe epoch.
    armed=0;reverse_camera=1;sorted_count=0;
    camera_words[8]=64'hfffffffffff00000;camera_words[11]=393216;
    apb_write(12'h000,4);apb_write(12'h0cc,32);apb_write(12'h0c4,32'h10000000);
    apb_write(12'h008,0);apb_write(12'h000,1);
    // Writes while BUSY must not alter the snapshotted scratch allocation.
    apb_write(12'h0c4,32'h20000000);
    wait_complete();
    if(frame_error_o||sorted_count!=32||active_mode_o!=0||dut.cmd_qsu_base_q!=64'h10000000)
      $fatal(1,"recovery/camera/snapshot failed %h sorted=%0d",frame_error_status_o,sorted_count);
    if(epoch_id_o!=((fault>=4&&fault<=6)?1:2))$fatal(1,"epoch mismatch %0d",epoch_id_o);
    // Zero-count autonomous frame must finish without touching scratch/BSU.
    apb_write(12'h000,4);apb_write(12'h0c4,32'h10000000);apb_write(12'h0cc,0);
    camera_words[27]={32'h47534301,32'd0};apb_write(12'h038,0);apb_write(12'h000,1);
    wait_complete();
    if(frame_error_o||dut.qsu_stats[31:0]!=0||dut.qsu_stats[159:96]!=0||sorted_count!=32)
      $fatal(1,"empty autonomous frame failed");
    $display("PASS T06 system recovery fault=%0d sorted=%0d epoch=%0d IRQ=%0d",fault,sorted_count,epoch_id_o,irq_o);$finish;
  end
endmodule
