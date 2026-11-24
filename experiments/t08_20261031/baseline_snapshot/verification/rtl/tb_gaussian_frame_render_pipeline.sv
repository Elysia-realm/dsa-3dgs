`timescale 1ns/1ps
module tb_gaussian_frame_render_pipeline;
`include "verification/rtl/t06_frame_signals.svh"
  logic[383:0]sort_work_totals_o;
`ifndef TB_FRAME_PARALLEL_SORT
`define TB_FRAME_PARALLEL_SORT 0
`endif
  logic source_end_valid_i=0,source_end_ready_o;
  logic attr_req_valid_o,attr_req_ready_i=0;logic[7:0]attr_req_gid_o;
  logic attr_rsp_valid_i=0,attr_rsp_ready_o,attr_rsp_error_i=0;logic[1117:0]attr_rsp_data_i=0;
  localparam LANES=2,GID_W=8,SEQ_W=8,COEFF_W=18,FLAT_W=3*16*COEFF_W;
  logic clk_i=0,rst_ni=0;logic frame_start_i=0,frame_continue_i=0;logic[1:0]frame_mode_i=2;logic frame_ready_o,frame_busy_o,frame_done_pulse_o,frame_error_o;logic[9:0]frame_error_status_o;
  logic source_valid_i=0,source_ready_o;logic[GID_W-1:0]source_gid_i=0;logic signed[26:0]source_world_x_q16_i=0,source_world_y_q16_i=0,source_world_z_q16_i=131072;logic source_last_i=0;
  logic runtime_mode_valid_i=0;logic[1:0]runtime_mode_i=0,active_mode_o;logic[15:0]epoch_id_o;logic mode_pending_o,mode_commit_pulse_o;
  logic attr_clear_valid_i=0,attr_write_en_i=0;logic[GID_W-1:0]attr_write_gid_i=0;
  logic signed[26:0]attr_write_world_x_q16_i=0,attr_write_world_y_q16_i=0,attr_write_world_z_q16_i=131072;
  logic signed[21:0]attr_write_qw_q20_i=1048576,attr_write_qx_q20_i=0,attr_write_qy_q20_i=0,attr_write_qz_q20_i=0;
  logic[23:0]attr_write_scale_x_q20_i=1048576,attr_write_scale_y_q20_i=1048576,attr_write_scale_z_q20_i=1048576;
  logic[12:0]attr_write_opacity_q12_i=4096;logic[FLAT_W-1:0]attr_write_coeff_q12_flat_i='0;
  logic signed[21:0]cfg_r00_q20_i=1048576,cfg_r01_q20_i=0,cfg_r02_q20_i=0,cfg_r10_q20_i=0,cfg_r11_q20_i=1048576,cfg_r12_q20_i=0;
  logic signed[21:0]cfg_r20_q20_i=0,cfg_r21_q20_i=0,cfg_r22_q20_i=1048576;
  logic signed[26:0]cfg_tx_q16_i=0,cfg_ty_q16_i=0,cfg_tz_q16_i=0,cfg_camera_x_q16_i=0,cfg_camera_y_q16_i=0,cfg_camera_z_q16_i=0;
  logic signed[32:0]cfg_fx_q16_i=131072,cfg_fy_q16_i=131072,cfg_cx_q16_i=1048576,cfg_cy_q16_i=1048576;
  logic signed[26:0]cfg_near_q16_i=13107,cfg_far_q16_i=65536000;logic[31:0]cfg_regularizer_q8_i=77;
  logic signed[26:0]cfg_depth_pivot0_q16_i=196608,cfg_depth_pivot1_q16_i=262144,cfg_depth_pivot2_q16_i=327680;
  logic[15:0]cfg_image_width_i=64,cfg_image_height_i=48;
  logic commit_valid_o,commit_ready_i=1;logic[31:0]commit_task_id_o,commit_block_id_o;logic[GID_W-1:0]commit_gid_o;logic[15:0]commit_epoch_id_o;
  logic[12:0]commit_alpha_q12_o;logic commit_pass_alpha_o;logic[31:0]commit_pixel_id_o;logic[12:0]commit_r_q12_o,commit_g_q12_o,commit_b_q12_o;logic[15:0]commit_t_q16_o;logic commit_newly_terminated_o;
  logic[LANES-1:0]projection_active_mask_o,sh_active_mask_o,raster_active_mask_o;logic attribute_read_pulse_o;
  logic event_group_pressure_o,event_sort_busy_o,event_projection_busy_o,event_raster_busy_o,event_block_candidate_o,event_shape_block_reject_o,event_terminated_skip_o;
  logic shared_pe_group_grant_o,shared_pe_projection_grant_o,shared_pe_raster_grant_o;
  logic shared_pe_group_stall_o,shared_pe_projection_stall_o,shared_pe_raster_stall_o;
  logic shared_pe_utilization_o,shared_pe_clock_enable_o,shared_pe_busy_o;
  logic state_miss_req_valid_o,state_miss_req_ready_i=0,state_miss_req_tag_o;
  logic state_miss_rsp_valid_i=0,state_miss_rsp_ready_o,state_miss_rsp_tag_i=0;
  logic[31:0]state_miss_req_pixel_id_o;logic state_miss_rsp_error_i=0;
  logic[127:0]state_miss_rsp_data_i=0;logic state_cache_error_o,state_cache_idle_o;
  logic[12:0]frame1_r[0:4095];logic frame1_pixel_valid[0:4095];
  integer shared_g_grants=0,shared_p_grants=0,shared_r_grants=0,shared_util=0;
  always#5 clk_i=~clk_i;
  always@(posedge clk_i)if(rst_ni)begin
    if(shared_pe_group_grant_o)shared_g_grants<=shared_g_grants+1;
    if(shared_pe_projection_grant_o)shared_p_grants<=shared_p_grants+1;
    if(shared_pe_raster_grant_o)shared_r_grants<=shared_r_grants+1;
    if(shared_pe_utilization_o)shared_util<=shared_util+1;
  end
  gaussian_frame_render_pipeline #(.ATTR_DEPTH(8),.LANES(LANES),.GROUP_CAPACITY(4),.SORT_CAPACITY(4),
    .USE_PARALLEL_GROUP_SORT(`TB_FRAME_PARALLEL_SORT),.GID_W(GID_W),.SEQ_W(SEQ_W))dut(.*);
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic write_attr(input integer gid,input integer x);begin
    attr_write_gid_i=gid;attr_write_world_x_q16_i=x;attr_write_en_i=1;tick();attr_write_en_i=0;
  end endtask
  task automatic send_mean(input integer gid,input integer x,input logic last);begin
    while(!source_ready_o)tick();source_gid_i=gid;source_world_x_q16_i=x;source_world_z_q16_i=131072;source_last_i=last;source_valid_i=1;tick();source_valid_i=0;source_last_i=0;
  end endtask
  initial begin integer commits,reads,timeout,current_gid,gid1_commits,gid2_commits,continuation_commits,continuation_increases,second_commits,index,abort_wait,abort_reads,p_before;
    for(index=0;index<4096;index=index+1)begin frame1_r[index]='0;frame1_pixel_valid[index]=0;end
    repeat(2)tick();rst_ni=1;tick();attr_write_coeff_q12_flat_i[0+:COEFF_W]=18'sd4096;
    // Same depth but reverse arrival order. Stable key (depth,GID,sequence)
    // must render GID 1 before GID 2. X positions make their bboxes disjoint.
    write_attr(1,-262144);write_attr(2,262144);
    if(!frame_ready_o)$fatal(1,"frame not ready after reset");frame_start_i=1;tick();frame_start_i=0;
    timeout=0;while(!source_ready_o&&timeout<30)begin tick();timeout=timeout+1;end
    if(!source_ready_o||epoch_id_o!==1||active_mode_o!==2)$fatal(1,"frame epoch/mode preparation failed");
    if(raster_active_mask_o!==2'b11)$fatal(1,"R mode did not enable both raster alpha lanes");
    send_mean(2,262144,0);send_mean(1,-262144,1);
    runtime_mode_i=3;runtime_mode_valid_i=1;tick();runtime_mode_valid_i=0;
    if(active_mode_o!==2||!mode_pending_o)$fatal(1,"runtime mode was not safely deferred");
    commits=0;reads=0;timeout=0;current_gid=1;gid1_commits=0;gid2_commits=0;
    while(!frame_done_pulse_o&&timeout<12000)begin
      commit_ready_i=(timeout%9!=4);
      if(attribute_read_pulse_o)reads=reads+1;
      if(commit_valid_o&&commit_ready_i)begin
        if(commit_gid_o<current_gid)$fatal(1,"Gaussian order regressed gid=%0d current=%0d",commit_gid_o,current_gid);
        if(commit_gid_o!==1&&commit_gid_o!==2)$fatal(1,"unexpected rendered GID");
        current_gid=commit_gid_o;if(commit_gid_o==1)begin gid1_commits=gid1_commits+1;
          frame1_r[commit_pixel_id_o[11:0]]=commit_r_q12_o;frame1_pixel_valid[commit_pixel_id_o[11:0]]=1;end
        else gid2_commits=gid2_commits+1;
        if(commit_epoch_id_o!==1)$fatal(1,"frame epoch tag mismatch");commits=commits+1;
      end
      tick();timeout=timeout+1;
    end
    if(timeout>=12000||frame_busy_o||!frame_ready_o)$fatal(1,"frame did not complete/drain");
    if(frame_error_o||frame_error_status_o!='0)$fatal(1,"unexpected frame error %b",frame_error_status_o);
    if(reads!=2||gid1_commits==0||gid2_commits==0||commits!=gid1_commits+gid2_commits)
      $fatal(1,"frame accounting failure reads=%0d commits=%0d g1=%0d g2=%0d",reads,commits,gid1_commits,gid2_commits);
    // Backpressure generation above is phase-dependent. Do not leak the last
    // frame's ready value into the next independent frame.
    commit_ready_i=1;
    // A continuation batch must preserve epoch 1 and blend on top of the
    // architected pixel state left by the first batch. It must not apply the
    // deferred E mode, because doing so would increment the render epoch.
    frame_continue_i=1;frame_start_i=1;tick();frame_start_i=0;frame_continue_i=0;
    timeout=0;while(!source_ready_o&&timeout<30)begin tick();timeout=timeout+1;end
    if(!source_ready_o||epoch_id_o!==1||active_mode_o!==2)
      $fatal(1,"continuation changed epoch/mode epoch=%0d mode=%0d",epoch_id_o,active_mode_o);
    send_mean(1,-262144,1);continuation_commits=0;continuation_increases=0;timeout=0;
    while(!frame_done_pulse_o&&timeout<7000)begin
      if(commit_valid_o&&commit_ready_i)begin
        if(commit_gid_o!==1||commit_epoch_id_o!==1)$fatal(1,"continuation tag/epoch mismatch");
        if(commit_pass_alpha_o&&frame1_pixel_valid[commit_pixel_id_o[11:0]]&&
           frame1_r[commit_pixel_id_o[11:0]]>0&&frame1_r[commit_pixel_id_o[11:0]]<4096)begin
          if(commit_r_q12_o<=frame1_r[commit_pixel_id_o[11:0]])
            $fatal(1,"continuation did not preserve/blend prior state pixel=%0d old=%0d new=%0d",
              commit_pixel_id_o,frame1_r[commit_pixel_id_o[11:0]],commit_r_q12_o);
          continuation_increases=continuation_increases+1;
        end
        continuation_commits=continuation_commits+1;
      end
      tick();timeout=timeout+1;
    end
    if(timeout>=7000||continuation_commits==0||continuation_increases==0||frame_error_o)
      $fatal(1,"continuation batch failed commits=%0d increases=%0d err=%b",
        continuation_commits,continuation_increases,frame_error_status_o);
    // Start another frame without an explicit resource change. The deferred E
    // mode is applied together with epoch 2, which also logically clears all
    // image and termination state from frame 1.
    frame_mode_i=2;frame_start_i=1;tick();frame_start_i=0;timeout=0;
    while(!source_ready_o&&timeout<30)begin tick();timeout=timeout+1;end
    if(epoch_id_o!==2||active_mode_o!==3||mode_pending_o||raster_active_mask_o!==2'b01)
      $fatal(1,"second-frame epoch/deferred mode failure epoch=%0d mode=%0d pending=%b mask=%b",epoch_id_o,active_mode_o,mode_pending_o,raster_active_mask_o);
    send_mean(1,-262144,1);second_commits=0;timeout=0;
    while(!frame_done_pulse_o&&timeout<7000)begin
      if(commit_valid_o&&commit_ready_i)begin
        if(commit_gid_o!==1||commit_epoch_id_o!==2)$fatal(1,"second-frame tag/epoch mismatch");
        // Every pixel must reproduce its frame-1 first-Gaussian value. Any
        // stale image state from epoch 1 changes this result.
        if(!frame1_pixel_valid[commit_pixel_id_o[11:0]]||commit_r_q12_o!==frame1_r[commit_pixel_id_o[11:0]])
          $fatal(1,"second-frame state was not logically cleared pixel=%0d got=%0d expected=%0d",commit_pixel_id_o,commit_r_q12_o,frame1_r[commit_pixel_id_o[11:0]]);
        second_commits=second_commits+1;
      end
      tick();timeout=timeout+1;
    end
    if(timeout>=7000||second_commits==0||frame_error_o)$fatal(1,"second frame failed commits=%0d err=%b",second_commits,frame_error_status_o);
    if(shared_g_grants==0||shared_p_grants!=48||shared_r_grants!=0||
       shared_util!=shared_g_grants+shared_p_grants)
      $fatal(1,"shared PE production use mismatch G/P/R/util=%0d/%0d/%0d/%0d",
        shared_g_grants,shared_p_grants,shared_r_grants,shared_util);
    // Error/explicit end after two accepted non-last means. Both contexts
    // remain in flight: do not move the P mux to main projection prematurely.
    frame_start_i=1;tick();frame_start_i=0;
    while(!source_ready_o)tick();p_before=shared_p_grants;
    send_mean(2,262144,0);send_mean(1,-262144,0);
    if(dut.pre_inflight_q!=2)$fatal(1,"abort test did not queue two means");
    source_end_valid_i=1;abort_wait=0;
    while(!source_end_ready_o&&abort_wait<100)begin
      if(!dut.select_pre_pe)$fatal(1,"P ownership changed before prepass drained");
      tick();abort_wait=abort_wait+1;
    end
    if(abort_wait==0||abort_wait>=100||dut.pre_inflight_q!=0)$fatal(1,"abort drain handshake failed");
    tick();source_end_valid_i=0;abort_reads=0;commits=0;timeout=0;current_gid=1;
    while(!frame_done_pulse_o&&timeout<12000)begin
      if(attribute_read_pulse_o)abort_reads=abort_reads+1;
      if(commit_valid_o&&commit_ready_i)begin
        if(commit_gid_o<current_gid||commit_epoch_id_o!=3)$fatal(1,"abort changed Gaussian order/epoch");
        current_gid=commit_gid_o;commits=commits+1;
      end
      tick();timeout=timeout+1;
    end
    if(timeout>=12000||abort_reads!=2||commits==0||frame_error_o||shared_pe_busy_o||shared_p_grants-p_before!=24)
      $fatal(1,"abort frame failed reads=%0d commits=%0d P=%0d",abort_reads,commits,shared_p_grants-p_before);
    // An empty end and then a new nonempty frame must not retain old contexts.
    frame_start_i=1;tick();frame_start_i=0;while(!source_end_ready_o)tick();
    source_end_valid_i=1;tick();source_end_valid_i=0;timeout=0;
    while(!frame_done_pulse_o&&timeout<100)begin
      if(commit_valid_o||attribute_read_pulse_o)$fatal(1,"empty frame issued stale work");
      tick();timeout=timeout+1;
    end
    if(timeout>=100||shared_pe_busy_o||frame_error_o)$fatal(1,"empty recovery failed");
    frame_start_i=1;tick();frame_start_i=0;while(!source_ready_o)tick();p_before=shared_p_grants;
    send_mean(1,-262144,1);commits=0;timeout=0;
    while(!frame_done_pulse_o&&timeout<7000)begin
      if(commit_valid_o&&commit_ready_i)begin
        if(commit_gid_o!=1||commit_epoch_id_o!=5)$fatal(1,"post-abort frame tag failed");
        commits=commits+1;
      end
      tick();timeout=timeout+1;
    end
    if(timeout>=7000||commits==0||frame_error_o||shared_p_grants-p_before!=12)$fatal(1,"post-abort recovery failed");
    $display("PREPASS_ABORT queued=2 wait_cycles=%0d rendered=2 empty_recovery=1 next_frame_recovery=1",abort_wait);
    $display("PASS: tb_gaussian_frame_render_pipeline");$finish;
  end
endmodule
