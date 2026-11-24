`timescale 1ns/1ps
`ifndef TB_SYSTEM_PARALLEL_SORT
`define TB_SYSTEM_PARALLEL_SORT 0
`endif
`ifndef TB_SYSTEM_LANES
`define TB_SYSTEM_LANES 1
`endif
`ifndef TB_SYSTEM_FASTPATH_TEST
`define TB_SYSTEM_FASTPATH_TEST 0
`endif
module tb_gs_accel_system_top;
`include "verification/rtl/t06_scratch_signals.svh"
  localparam GID_W=8,COEFF_W=18,FLAT_W=3*16*COEFF_W;
  logic clk_i=0,rst_ni=0,psel_i=0,penable_i=0,pwrite_i=0;logic[11:0]paddr_i=0;logic[31:0]pwdata_i=0;logic[3:0]pstrb_i=0;logic[31:0]prdata_o;logic pready_o,pslverr_o,irq_o;
  logic source_valid_i=0,source_ready_o;logic[GID_W-1:0]source_gid_i=1;logic signed[26:0]source_world_x_q16_i=0,source_world_y_q16_i=0,source_world_z_q16_i=131072;logic source_last_i=1;
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
  logic[1:0]m_axi_out_awid_o,m_axi_out_bid_i=0;logic[63:0]m_axi_out_awaddr_o;logic[7:0]m_axi_out_awlen_o;logic[2:0]m_axi_out_awsize_o;logic[1:0]m_axi_out_awburst_o;logic m_axi_out_awvalid_o,m_axi_out_awready_i=0;logic[127:0]m_axi_out_wdata_o;logic[15:0]m_axi_out_wstrb_o;logic m_axi_out_wlast_o,m_axi_out_wvalid_o,m_axi_out_wready_i=0;logic[1:0]m_axi_out_bresp_i=0;logic m_axi_out_bvalid_i=0,m_axi_out_bready_o;
  logic[1:0]m_axi_state_arid_o,m_axi_state_rid_i=0;logic[63:0]m_axi_state_araddr_o;
  logic[7:0]m_axi_state_arlen_o;logic[2:0]m_axi_state_arsize_o;logic[1:0]m_axi_state_arburst_o;
  logic m_axi_state_arvalid_o,m_axi_state_arready_i=1;logic[127:0]m_axi_state_rdata_i=0;
  logic[1:0]m_axi_state_rresp_i=0;logic m_axi_state_rlast_i=0,m_axi_state_rvalid_i=0,m_axi_state_rready_o;
  logic state_error_next=0,state_error_pending=0;logic[1:0]state_rid_pending=0;integer state_r_delay=-1;
  logic[127:0]fast_state_mem[4096];integer fast_read_pixel=0;
  always#5 clk_i=~clk_i;
  gs_accel_system_top #(.ATTR_DEPTH(8),.LANES(`TB_SYSTEM_LANES),.GROUP_CAPACITY(4),.SORT_CAPACITY(4),.STATE_ENTRIES(4096),.GID_W(GID_W),.SEQ_W(8),.USE_AXI_MEAN_DMA(0),.USE_AXI_CAMERA_DMA(0),.USE_AXI_ATTR_DMA(0),.USE_AXI_PIXEL_WRITE(0),.USE_STATE_CACHE_BACKEND(1),
    .USE_PARALLEL_GROUP_SORT(`TB_SYSTEM_PARALLEL_SORT),
    .USE_BITONIC_SORT(0),.USE_SHARED_RASTER_PE(0),
    .MODE_ADVISOR_WINDOW_CYCLES(16),.MODE_ADVISOR_HYSTERESIS_WINDOWS(1),
    .MODE_ADVISOR_MIN_RESIDENCE_WINDOWS(1),.MODE_ADVISOR_SCORE_MARGIN(1))dut(.*);
  always@(posedge clk_i)begin
    if(!rst_ni)begin m_axi_state_arready_i<=1;m_axi_state_rvalid_i<=0;m_axi_state_rlast_i<=0;m_axi_state_rresp_i<=0;state_r_delay<=-1;end
    else begin
      if(`TB_SYSTEM_FASTPATH_TEST&&commit_valid_o&&commit_ready_i)
        fast_state_mem[commit_pixel_id_o]<= {10'd0,24'd0,commit_gid_o,commit_newly_terminated_o,commit_pass_alpha_o,
          commit_alpha_q12_o,commit_epoch_id_o,commit_t_q16_o,commit_b_q12_o,commit_g_q12_o,commit_r_q12_o};
      if(m_axi_state_arvalid_o&&m_axi_state_arready_i)begin
        fast_read_pixel=int'(m_axi_state_araddr_o>>4);
        m_axi_state_arready_i<=0;
        state_r_delay<=1;state_rid_pending<=m_axi_state_arid_o;
        state_error_pending<=state_error_next;state_error_next<=0;
      end else if(state_r_delay>0)state_r_delay<=state_r_delay-1;
      else if(state_r_delay==0)begin
        m_axi_state_rvalid_i<=1;m_axi_state_rid_i<=state_rid_pending;m_axi_state_rlast_i<=1;
        m_axi_state_rresp_i<=state_error_pending?2'b10:2'b00;state_r_delay<=-1;
        if(`TB_SYSTEM_FASTPATH_TEST)m_axi_state_rdata_i<=fast_state_mem[fast_read_pixel];
      end
      if(m_axi_state_rvalid_i&&m_axi_state_rready_o)begin
        m_axi_state_arready_i<=1;m_axi_state_rvalid_i<=0;m_axi_state_rlast_i<=0;m_axi_state_rresp_i<=0;
      end
    end
  end
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic apb_write(input[11:0]addr,input[31:0]data);begin paddr_i=addr;pwdata_i=data;pstrb_i=4'hf;pwrite_i=1;psel_i=1;penable_i=1;tick();psel_i=0;penable_i=0;pwrite_i=0;pstrb_i=0;end endtask
  task automatic apb_read(input[11:0]addr,output[31:0]data);begin paddr_i=addr;pwrite_i=0;psel_i=1;penable_i=1;#1;if(!pready_o||pslverr_o)$fatal(1,"APB read failed %h",addr);data=prdata_o;psel_i=0;penable_i=0;#1;end endtask
  task automatic sort_snapshot(input integer expected_groups);
    logic[383:0]expected;logic[31:0]rd;
    begin
      apb_write(12'h080,32'h1);
      for(integer j=0;j<12;j=j+1)expected[32*j+:32]=dut.sort_work_totals[32*j+:32]-dut.sort_work_base_q[32*j+:32];
      tick();
      for(integer j=0;j<12;j=j+1)begin
        apb_read(12'(12'h088+4*j),rd);
        if(rd!==expected[32*j+:32])$fatal(1,"atomic sorter snapshot field %0d mismatch",j);
      end
      apb_read(12'h098,rd);
      if(rd!==32'(`TB_SYSTEM_PARALLEL_SORT?expected_groups:0))$fatal(1,"sort logical-frame group tally mismatch %0d",rd);
    end
  endtask
  task automatic fastpath_frames;
    logic[54:0]pixels[4096],second_pixels[4096];logic seen[4096],second_seen[4096];logic[31:0]rd;
    integer count,first_count,timeout,id,pass;
    begin
      for(integer j=0;j<4096;j=j+1)begin seen[j]=0;pixels[j]=0;second_seen[j]=0;second_pixels[j]=0;fast_state_mem[j]=0;end
      for(id=1;id<=3;id=id+1)begin
        attr_write_gid_i=id;attr_write_world_x_q16_i=(id-2)*262144;attr_write_en_i=1;tick();attr_write_en_i=0;
      end
      apb_write(12'h028,{16'd48,16'd64});apb_write(12'h008,32'h0);
      for(pass=0;pass<4;pass=pass+1)begin
        for(integer j=0;j<4096;j=j+1)begin second_seen[j]=0;second_pixels[j]=0;end
        apb_write(12'h000,32'h1);timeout=0;
        while(!source_ready_o&&timeout<100)begin tick();timeout=timeout+1;end
        for(integer j=0;j<3;j=j+1)begin
          case(pass)
            0:id=j+1;
            1:id=3-j;
            2:id=j==0?2:(j==1?1:3);
            default:id=j==0?3:(j==1?1:2);
          endcase
          while(!source_ready_o)tick();
          source_gid_i=id;source_world_x_q16_i=(id-2)*262144;source_last_i=j==2;source_valid_i=1;
          tick();source_valid_i=0;
        end
        count=0;timeout=0;
        while(!frame_done_pulse_o&&timeout<16000)begin
          if(commit_valid_o&&commit_ready_i)begin
            id=int'(commit_pixel_id_o);count=count+1;
            if(pass==0)begin seen[id]=1;pixels[id]={commit_r_q12_o,commit_g_q12_o,commit_b_q12_o,commit_t_q16_o};end
            else begin second_seen[id]=1;second_pixels[id]={commit_r_q12_o,commit_g_q12_o,commit_b_q12_o,commit_t_q16_o};end
          end
          tick();timeout=timeout+1;
        end
        tick();if(timeout>=16000||frame_error_o||count==0)$fatal(1,"fastpath frame failed");
        if(pass==0)first_count=count;else if(count!=first_count)$fatal(1,"fastpath commit coverage differs");
        sort_snapshot(1);apb_read(12'h084,rd);if(rd!=7)$fatal(1,"four-lane fastpath capability absent");
        apb_read(12'h0b0,rd);if(rd!=1)$fatal(1,"render did not use fastpath");
        apb_read(12'h0b4,rd);if(rd!=32'(pass!=0))$fatal(1,"reverse fastpath selection wrong");
        apb_read(12'h0ac,rd);if(rd!=2)$fatal(1,"monotonic compare count wrong");
        apb_read(12'h088,rd);if(rd!=32'(pass<2?0:pass==2?1:2))$fatal(1,"tail search shared compare count wrong");
        if(pass!=0)for(integer j=0;j<4096;j=j+1)if(seen[j]!==second_seen[j]||(seen[j]&&pixels[j]!==second_pixels[j]))
          $fatal(1,"fastpath final framebuffer differs pass=%0d pixel=%0d",pass,j);
      end
      for(integer j=0;j<4096;j=j+1)if(seen[j]!==second_seen[j]||(seen[j]&&pixels[j]!==second_pixels[j]))
        $fatal(1,"reverse fastpath final framebuffer differs pixel %0d",j);
      $display("SORT_FASTPATH_FRAME_TEST lanes=%0d frames=4 ascending=1 reverse=1 tail_max=1 tail_middle=1 commits=%0d framebuffer_equal=1",`TB_SYSTEM_LANES,first_count);
    end
  endtask
  initial begin integer timeout,commits,snapshot_activity;logic[31:0]rd;logic[1:0]auto_recommended;
    repeat(2)tick();rst_ni=1;tick();attr_write_coeff_q12_flat_i[0+:COEFF_W]=18'sd4096;attr_write_en_i=1;tick();attr_write_en_i=0;
    if(`TB_SYSTEM_FASTPATH_TEST)begin fastpath_frames();$display("PASS: tb_gs_accel_system_top fastpath frames");$finish;end
    apb_write(12'h028,{16'd48,16'd64});apb_write(12'h02c,32'h3);apb_write(12'h008,32'h3);apb_write(12'h000,32'h1);
    timeout=0;while(!source_ready_o&&timeout<30)begin tick();timeout=timeout+1;end
    if(!source_ready_o||epoch_id_o!==1||active_mode_o!==3)$fatal(1,"APB start did not prepare E frame");
    source_valid_i=1;tick();source_valid_i=0;commits=0;timeout=0;
    while(!frame_done_pulse_o&&timeout<5000)begin if(commit_valid_o&&commit_ready_i)commits=commits+1;tick();timeout=timeout+1;end
    tick();if(timeout>=5000||commits==0||frame_busy_o||frame_error_o)$fatal(1,"normal system frame failed");
    if(!irq_o)$fatal(1,"done IRQ not asserted");apb_read(12'h004,rd);
    if(!rd[1]||rd[0]||rd[4]||!rd[5]||rd[31:16]!==1)$fatal(1,"normal STATUS mismatch %h",rd);
    apb_read(12'h034,rd);if(rd[1:0]!==2'b01)$fatal(1,"done pending mismatch");
    apb_read(12'h084,rd);if(rd!==32'(`TB_SYSTEM_PARALLEL_SORT?5:0))$fatal(1,"sort capabilities mismatch");
    sort_snapshot(1);apb_read(12'h080,rd);if(rd!==1)$fatal(1,"snapshot sequence missing");
    apb_write(12'h000,32'h4);tick();if(irq_o)$fatal(1,"status clear did not deassert IRQ");apb_read(12'h004,rd);if(rd[5:1]!=0)$fatal(1,"sticky status not cleared %h",rd);
    // Two physical batches form one logical frame. CONTROL[4] marks that a
    // next batch follows; CONTROL[3] marks a continuation. The first batch
    // must not expose done/IRQ, and the final batch must retain epoch 2.
    apb_write(12'h000,32'h11);
    while(!source_ready_o)tick();source_valid_i=1;tick();source_valid_i=0;
    timeout=0;while(frame_busy_o&&timeout<5000)begin
      if(frame_done_pulse_o)$fatal(1,"intermediate batch exposed frame done");
      tick();timeout=timeout+1;
    end
    if(timeout>=5000||epoch_id_o!==2||irq_o)$fatal(1,"intermediate batch did not close cleanly");
    apb_read(12'h004,rd);if(!rd[6]||rd[1]||rd[0])$fatal(1,"logical frame-open status mismatch %h",rd);
    sort_snapshot(1);apb_read(12'h080,rd);if(rd!==1)$fatal(1,"fresh frame did not reset snapshot sequence");
    apb_write(12'h000,32'h9);
    while(!source_ready_o)tick();source_valid_i=1;tick();source_valid_i=0;
    timeout=0;while(!frame_done_pulse_o&&timeout<5000)begin tick();timeout=timeout+1;end
    tick();if(timeout>=5000||epoch_id_o!==2||frame_error_o||!irq_o)
      $fatal(1,"final continuation batch failed epoch=%0d error=%h",epoch_id_o,frame_error_status_o);
    apb_read(12'h004,rd);if(rd[6]||!rd[1])$fatal(1,"logical frame did not close %h",rd);
    // Snapshot stays frozen across continuation until explicitly captured.
    apb_read(12'h098,rd);if(rd!==32'(`TB_SYSTEM_PARALLEL_SORT?1:0))$fatal(1,"frozen snapshot changed on continuation");
    sort_snapshot(2);apb_read(12'h080,rd);if(rd!==2)$fatal(1,"continuation reset snapshot sequence");
    apb_write(12'h080,32'h3);tick();apb_read(12'h098,rd);
    if(rd!==32'(`TB_SYSTEM_PARALLEL_SORT?2:0))$fatal(1,"capture+clear failed to capture old interval");
    sort_snapshot(0);
    apb_write(12'h000,32'h4);tick();
    // A continuation is illegal once the logical frame has closed.
    apb_write(12'h000,32'h9);tick();
    if(!frame_done_pulse_o||!frame_error_o||!frame_error_status_o[18])
      $fatal(1,"orphan continuation protocol error missing %h",frame_error_status_o);
    apb_write(12'h000,32'h4);tick();if(frame_error_o||irq_o)$fatal(1,"continuation error clear failed");
    // Continuations cannot silently redirect pixel state to another image.
    apb_write(12'h000,32'h11);
    while(!source_ready_o)tick();source_valid_i=1;tick();source_valid_i=0;
    timeout=0;while(frame_busy_o&&timeout<5000)begin tick();timeout=timeout+1;end
    apb_write(12'h020,32'h00200000);apb_write(12'h000,32'h9);tick();
    if(!frame_done_pulse_o||!frame_error_status_o[18])
      $fatal(1,"continuation output-base mismatch was accepted");
    apb_write(12'h000,32'h4);tick();apb_write(12'h020,32'h00000000);
    if(frame_error_o||irq_o)$fatal(1,"continuation config error clear failed");
    // A backing-store RRESP failure has its own system error bit 16.
    state_error_next=1;apb_write(12'h000,32'h1);
    while(!source_ready_o)tick();source_valid_i=1;tick();source_valid_i=0;
    timeout=0;while(!frame_done_pulse_o&&timeout<5000)begin tick();timeout=timeout+1;end
    tick();if(timeout>=5000||!frame_error_o||!frame_error_status_o[16])$fatal(1,"state read error missing");
    apb_read(12'h030,rd);if(!rd[16])$fatal(1,"state read APB bit missing");
    apb_write(12'h000,32'h4);tick();if(irq_o||frame_error_o)$fatal(1,"state error clear failed");
    // With external backing enabled, cache capacity is independent of full
    // image size. An image larger than 4096 pixels must be accepted.
    apb_write(12'h028,{16'd64,16'd65});apb_write(12'h000,32'h1);
    while(!source_ready_o)tick();source_world_z_q16_i=27'sd66000000;source_valid_i=1;tick();source_valid_i=0;
    timeout=0;while(!frame_done_pulse_o&&timeout<500)begin tick();timeout=timeout+1;end
    tick();if(timeout>=500||frame_error_o||frame_error_status_o[9])$fatal(1,"backed large image rejected");

    // Automatic control observes real pipeline events.  Starting from E, a
    // non-terminated Gaussian should queue the first statistically dominant
    // non-E stage during this frame, but active_mode/epoch must not change
    // until the next new frame starts.  A short window may see projection
    // before raster; the single-outstanding rule deliberately preserves it.
    apb_write(12'h028,{16'd48,16'd64});source_world_z_q16_i=27'sd131072;
    apb_write(12'h044,32'h1);apb_read(12'h044,rd);
    if(!rd[0])$fatal(1,"automatic mode did not enable");
    apb_write(12'h000,32'h1);while(!source_ready_o)tick();
    if(active_mode_o!==3)$fatal(1,"automatic mode changed before observation frame");
    source_valid_i=1;tick();source_valid_i=0;timeout=0;
    while(!frame_done_pulse_o&&timeout<5000)begin tick();timeout=timeout+1;end
    tick();if(timeout>=5000||frame_error_o)$fatal(1,"automatic observation frame failed");
    apb_read(12'h044,rd);
    auto_recommended=rd[3:2];
    if(!rd[0]||!rd[1]||auto_recommended===3||!rd[7])
      $fatal(1,"automatic recommendation was not queued safely status=%h",rd);
    if(active_mode_o!==3)$fatal(1,"recommendation changed active mode inside completed frame");
    apb_read(12'h048,rd);if(rd==0)$fatal(1,"advisor did not expose a completed window");
    snapshot_activity=0;
    apb_read(12'h04c,rd);snapshot_activity=snapshot_activity+rd;
    apb_read(12'h050,rd);snapshot_activity=snapshot_activity+rd;
    apb_read(12'h054,rd);snapshot_activity=snapshot_activity+rd;
    apb_read(12'h058,rd);snapshot_activity=snapshot_activity+rd;
    apb_read(12'h05c,rd);snapshot_activity=snapshot_activity+rd;
    apb_read(12'h060,rd);snapshot_activity=snapshot_activity+rd;
    if(snapshot_activity==0)$fatal(1,"real advisor window snapshot contained no activity");

    apb_write(12'h000,32'h1);while(!source_ready_o)tick();
    if(active_mode_o!==auto_recommended)
      $fatal(1,"queued mode did not commit at next epoch boundary expected=%0d got=%0d",auto_recommended,active_mode_o);
    source_valid_i=1;tick();source_valid_i=0;timeout=0;
    while(!frame_done_pulse_o&&timeout<5000)begin tick();timeout=timeout+1;end
    tick();if(timeout>=5000||frame_error_o)$fatal(1,"post-reconfiguration frame failed");
    apb_read(12'h068,rd);if(rd!=12)$fatal(1,"shared P MAC grant counter wrong %0d",rd);
    apb_read(12'h06c,rd);if(rd!=0)$fatal(1,"inactive shared R client granted %0d",rd);
    apb_read(12'h07c,rd);if(rd!=12)$fatal(1,"shared PE utilization counter wrong %0d",rd);
    apb_write(12'h044,32'h0);tick();apb_read(12'h044,rd);
    if(rd[0])$fatal(1,"automatic mode did not disable");
    if(`TB_SYSTEM_PARALLEL_SORT)begin
      force dut.sort_work_totals[0+:32]=32'h00000004;
      force dut.sort_work_base_q[0+:32]=32'hfffffffc;
      apb_write(12'h080,32'h1);tick();apb_read(12'h088,rd);
      if(rd!==8)$fatal(1,"modular sorter snapshot delta failed %h",rd);
      release dut.sort_work_totals[0+:32];release dut.sort_work_base_q[0+:32];
    end
    apb_write(12'h000,32'h2);tick();apb_read(12'h080,rd);
    if(rd!==0||dut.sort_work_base_q!==384'd0||dut.sort_work_totals!==384'd0)
      $fatal(1,"soft reset did not clear sorter snapshot measuring state");
    $display("SORT_SNAPSHOT_TEST candidate=%0d fields=12 continuation=1 frozen=1 capture_clear=1 modular_delta=%0d soft_reset=1",`TB_SYSTEM_PARALLEL_SORT,`TB_SYSTEM_PARALLEL_SORT);
    $display("PASS: tb_gs_accel_system_top");$finish;
  end
endmodule
