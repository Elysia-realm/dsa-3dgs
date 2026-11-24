// Testbench-only observation. No alternate datapath and no software scheduling.
longint unsigned measure_tick=0,measure_accept=0,measure_core=0;
longint unsigned measure_start_count=0,measure_camera_beats=0,measure_mean_beats=0;
longint unsigned measure_attr_beats=0,measure_qsu_reads=0,measure_qsu_writes=0;
longint unsigned measure_camera_bursts=0,measure_mean_bursts=0,measure_attr_bursts=0;
longint unsigned measure_qsu_read_bursts=0,measure_qsu_write_bursts=0;
longint unsigned measure_state_read_bursts=0,measure_out_write_bursts=0;
logic measure_reported=0;
always @(posedge clk_i) begin
  measure_tick<=measure_tick+1;
  if(rst_ni)begin
    if(dut.command_accept)begin measure_accept<=measure_tick+1;measure_start_count<=measure_start_count+1;end
    if(dut.batch_start)measure_core<=measure_tick+1;
    if(m_axi_camera_rvalid_i&&m_axi_camera_rready_o)measure_camera_beats<=measure_camera_beats+1;
    if(m_axi_mean_rvalid_i&&m_axi_mean_rready_o)measure_mean_beats<=measure_mean_beats+1;
    if(m_axi_attr_rvalid_i&&m_axi_attr_rready_o)measure_attr_beats<=measure_attr_beats+1;
    if(m_axi_qsu_rvalid_i&&m_axi_qsu_rready_o)measure_qsu_reads<=measure_qsu_reads+1;
    if(m_axi_qsu_wvalid_o&&m_axi_qsu_wready_i)measure_qsu_writes<=measure_qsu_writes+1;
    if(m_axi_camera_arvalid_o&&m_axi_camera_arready_i)measure_camera_bursts<=measure_camera_bursts+1;
    if(m_axi_mean_arvalid_o&&m_axi_mean_arready_i)measure_mean_bursts<=measure_mean_bursts+1;
    if(m_axi_attr_arvalid_o&&m_axi_attr_arready_i)measure_attr_bursts<=measure_attr_bursts+1;
    if(m_axi_qsu_arvalid_o&&m_axi_qsu_arready_i)measure_qsu_read_bursts<=measure_qsu_read_bursts+1;
    if(m_axi_qsu_awvalid_o&&m_axi_qsu_awready_i)measure_qsu_write_bursts<=measure_qsu_write_bursts+1;
    if(m_axi_state_arvalid_o&&m_axi_state_arready_i)measure_state_read_bursts<=measure_state_read_bursts+1;
    if(m_axi_out_awvalid_o&&m_axi_out_awready_i)measure_out_write_bursts<=measure_out_write_bursts+1;
  end
end
// Sample DONE after its generating edge and all nonblocking counter updates.
always @(negedge clk_i)if(1'b0&&rst_ni&&!frame_error_o&&frame_done_pulse_o&&!measure_reported)begin
  if(measure_start_count!=1||measure_core<=measure_accept)$fatal(1,"invalid single-command timing observation");
  if(frame_error_o||m_axi_out_bvalid_i||dut.final_rgb_busy)$fatal(1,"timing ended before successful final drain");
  $display("REAL_END_TO_END command_cycles=%0d camera_setup_cycles=%0d post_batch_cycles=%0d command_count=%0d window=%0d mshr=%0d response_bypass=%0d commit_bypass=%0d",measure_tick-measure_accept,measure_core-measure_accept,measure_tick-measure_core,measure_start_count,`TB_STATE_WINDOW_ENTRIES,`TB_STATE_MSHR_COUNT,`TB_RESPONSE_BLEND_BYPASS,`TB_BLEND_COMMIT_BYPASS);
  $display("REAL_DMA_COUNTS camera_beats=%0d mean_beats=%0d attribute_beats=%0d qsu_read_beats=%0d qsu_write_beats=%0d camera_bursts=%0d mean_bursts=%0d attribute_bursts=%0d qsu_read_bursts=%0d qsu_write_bursts=%0d state_read_bursts=%0d output_write_bursts=%0d",measure_camera_beats,measure_mean_beats,measure_attr_beats,measure_qsu_reads,measure_qsu_writes,measure_camera_bursts,measure_mean_bursts,measure_attr_bursts,measure_qsu_read_bursts,measure_qsu_write_bursts,measure_state_read_bursts,measure_out_write_bursts);
  measure_reported=1;
  $display("REAL_LOCAL_QSU records=%0d",dut.AUTO_QSU_LOCAL_RECORDS);
end
