// Testbench observation on the frozen T08 candidate. Stop after two windows.
`define T08_CACHE dut.u_frame.u_render.u_render.u_raster.u_raster.g_state_cache_quad.u_state_cache
integer obs_window=0, obs_count=0, obs_fd=0, obs_queries=0, obs_hits=0;
bit obs_active=0;
string obs_path;
initial begin
  if(!$value$plusargs("LOCALITY_TRACE=%s",obs_path))$fatal(1,"missing trace path");
  obs_fd=$fopen(obs_path,"w");
  if(!obs_fd)$fatal(1,"cannot write trace");
end
always @(posedge clk_i) if(rst_ni)begin
  if(frame_error_o)$fatal(1,"frame error in locality diagnostic");
  if(frame_done_pulse_o)$fatal(1,"frame ended before both windows");
  if(!obs_active&&t08_requests >= (obs_window==0?4096:65536))begin
    obs_active=1;
    $fdisplay(obs_fd,"W %0d %0d %0d",obs_window,t08_requests,measure_tick);
  end
  if(obs_active)begin
    if(`T08_CACHE.query_fire)begin
      obs_queries++;
      if(`T08_CACHE.query_hit)obs_hits++;
    end
    if(`T08_CACHE.miss_rsp_fire)begin
      if(`T08_CACHE.miss_rsp_error_i)$fatal(1,"bad state fill");
      $fdisplay(obs_fd,"F %0d %0d",measure_tick,`T08_CACHE.mshr_pixel_q[`T08_CACHE.miss_rsp_tag_i]);
    end
    if(`T08_CACHE.update_valid_i)begin
      $fdisplay(obs_fd,"U %0d %0d",measure_tick,`T08_CACHE.update_pixel_id_i);
      obs_count++;
      if(obs_count==65536)begin
        $fdisplay(obs_fd,"E %0d %0d %0d %0d %0d",obs_window,obs_queries,obs_hits,t08_requests,measure_tick);
        $fflush(obs_fd);
        obs_count=0;obs_queries=0;obs_hits=0;obs_active=0;obs_window++;
        if(obs_window==2)begin
          if(dut.cmd_attribute_format_q!=1||!dut.cmd_qsu_enable_q||!dut.ATTR_DMA_EARLY_ADVANCE||
             t08_precomputed==0||epoch_id_o!=1)$fatal(1,"invalid candidate or generation");
          $fclose(obs_fd);
          $display("T08_LOCALITY_CAPTURE_COMPLETE width=%0d height=%0d n=%0d requests=%0d precomputed=%0d",
                   workload_width,workload_height,workload_count,t08_requests,t08_precomputed);
          $finish;
        end
      end
    end
  end
end
`undef T08_CACHE
