// Passive count of accepted data beats on the seven separate AXI channels.
// An ideal shared port can serve one of these 128-bit beats in each cycle.
wire [6:0] t08_bus_fire={
    m_axi_camera_rvalid_i && m_axi_camera_rready_o,
    m_axi_mean_rvalid_i && m_axi_mean_rready_o,
    m_axi_attr_rvalid_i && m_axi_attr_rready_o,
    m_axi_qsu_rvalid_i && m_axi_qsu_rready_o,
    m_axi_qsu_wvalid_o && m_axi_qsu_wready_i,
    m_axi_state_rvalid_i && m_axi_state_rready_o,
    m_axi_out_wvalid_o && m_axi_out_wready_i
};
longint unsigned t08_beats=0,t08_shared_queue=0,t08_peak_queue=0,t08_overlap=0,t08_excess=0;
logic t08_measuring=0;
always @(posedge clk_i) if(rst_ni)begin
    if(dut.command_accept)t08_measuring<=1;
    if(t08_measuring || dut.command_accept)begin : t08_count_bus
        longint unsigned arrivals,queued;
        arrivals=64'($countones(t08_bus_fire));
        queued=t08_shared_queue+arrivals;
        if(queued!=0)queued=queued-1;
        t08_shared_queue<=queued;
        if(queued>t08_peak_queue)t08_peak_queue<=queued;
        t08_beats<=t08_beats+arrivals;
        if(arrivals>1)begin
            t08_overlap<=t08_overlap+1;
            t08_excess<=t08_excess+arrivals-1;
        end
        if(measure_tick[24:0]==0)begin
            $display("T08_NATIVE_PROGRESS tick=%0d qsu_reads=%0d records=%0d commits=%0d bus_beats=%0d",
                measure_tick,measure_qsu_reads,t08_requests,perf_commit_count_o,t08_beats);
            $fflush();
        end
        if(frame_done_pulse_o)t08_measuring<=0;
    end
end
