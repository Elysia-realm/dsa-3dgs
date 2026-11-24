// Control tests share the integrated APB/AXI memory models and clocks.
task automatic check_format_drain;
  if(frame_busy_o || b_get!=b_put || m_axi_out_bvalid_i || rgb_beats_left!=0 ||
     dut.attr_dma_busy || dut.final_rgb_busy || dut.qsu_rd_busy || dut.qsu_wr_busy ||
     qsu_b_get!=qsu_aw_put || qsu_b_get!=qsu_w_put || qsu_read_left!=0)
    $fatal(1,"format sequence still owns transactions");
endtask

task automatic clear_format_status;
  apb_write(12'h000,4);
  repeat(3)tick();
  if(frame_error_o || irq_o || dut.done_sticky_q)$fatal(1,"status clear failed");
endtask

task automatic finish_format_frame(input integer control,input integer expected_epoch,input string path);
  integer deadline,fd;
  longint unsigned prior_reads,prior_writes,prior_requests,prior_beats,prior_expected,prior_precomputed;
  prior_reads=rgb_read_count;prior_writes=rgb_write_beats;prior_requests=t08_requests;
  prior_beats=attr_beats;prior_expected=t08_expected_beats;prior_precomputed=t08_precomputed;
  apb_write(12'h000,control);
  apb_write(12'h0f0,t08_format^2);
  deadline=0;
  while(!dut.done_sticky_q && deadline<max_timeout)begin tick();deadline++;end
  tick();
  if(deadline>=max_timeout || !irq_o || frame_error_o || frame_error_status_o!=0 ||
     dut.logical_frame_open_q || int'(epoch_id_o)!=expected_epoch ||
     int'(dut.cmd_attribute_format_q)!=t08_format)$fatal(1,"frame status/epoch/format");
  check_format_drain();
  if(rgb_read_count-prior_reads!=workload_width*workload_height ||
     (rgb_write_beats-prior_writes)*16!=rgb_bytes || t08_requests<=prior_requests ||
     attr_beats-prior_beats!=t08_expected_beats-prior_expected)$fatal(1,"frame traffic incomplete");
  if((t08_format==1||t08_format==2)!=(t08_precomputed>prior_precomputed))
    $fatal(1,"compressed path use incorrect");
  if(qsu_requested && (!dut.cmd_qsu_enable_q || dut.qsu_stats[31:0]==0))$fatal(1,"QSU bypass");
  fd=$fopen(path,"wb");if(fd==0)$fatal(1,"cannot save DMA bytes");
  for(integer n=0;n<rgb_bytes;n++)$fwrite(fd,"%c",rgb_mem[n]);
  $fclose(fd);
  $display("SEQUENCE_FRAME fmt=%0d epoch=%0d requests=%0d precomputed=%0d beats=%0d reads=%0d rgb_bytes=%0d",
    t08_format,epoch_id_o,t08_requests-prior_requests,t08_precomputed-prior_precomputed,
    attr_beats-prior_beats,rgb_read_count-prior_reads,rgb_bytes);
endtask

task automatic run_format_sequence;
  integer second_format,kind,deadline;
  longint unsigned means,attrs,starts,cameras,writes,requests;
  string next_attr;
  if(!$value$plusargs("NEXT_FORMAT=%d",second_format) || !$value$plusargs("NEXT_ATTR=%s",next_attr) ||
     !$value$plusargs("SEQ_KIND=%d",kind))$fatal(1,"missing format sequence args");
  apb_write(12'h02c,3);
  if(kind==0)begin
    finish_format_frame(1,1,{rgb_path,".first"});
    clear_format_status();
  end else begin
    if(qsu_requested || workload_count!=1)$fatal(1,"continuation fixture");
    apb_write(12'h000,32'h11);
    deadline=0;
    while(!frame_busy_o && deadline<max_timeout)begin tick();deadline++;end
    while(frame_busy_o && deadline<max_timeout)begin tick();deadline++;end
    if(deadline>=max_timeout || frame_error_o || !dut.logical_frame_open_q || irq_o ||
       dut.done_sticky_q || epoch_id_o!=1 || mean_beats!=1 || t08_requests!=1 || rgb_write_beats!=0)
      $fatal(1,"intermediate batch");
    check_format_drain();
  end
  $readmemh(next_attr,attr_mem,0,workload_count*9-1);
  t08_format=second_format;apb_write(12'h0f0,t08_format);
  if(kind==2)begin
    means=mean_beats;attrs=attr_beats;starts=measure_start_count;cameras=measure_camera_beats;
    writes=rgb_write_beats;requests=t08_requests;
    apb_write(12'h000,32'h9);
    deadline=0;
    while(!dut.done_sticky_q && deadline<max_timeout)begin tick();deadline++;end
    tick();
    if(deadline>=max_timeout || !irq_o || !frame_error_o || !frame_error_status_o[18] ||
       dut.logical_frame_open_q || epoch_id_o!=1 || mean_beats!=means || attr_beats!=attrs ||
       measure_start_count!=starts || measure_camera_beats!=cameras || rgb_write_beats!=writes ||
       t08_requests!=requests)$fatal(1,"mismatched continuation accepted or incorrect error");
    check_format_drain();
    clear_format_status();
  end
  finish_format_frame(kind==1?9:1,kind==1?1:2,rgb_path);
  if(measure_start_count!=2)$fatal(1,"wrong accepted command count");
  if(sorted_trace_file!=0)$fclose(sorted_trace_file);
  $display("PASS T08 format sequence kind=%0d final_format=%0d",kind,t08_format);
endtask
