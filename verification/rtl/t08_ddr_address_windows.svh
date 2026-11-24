// Passive address-channel capture. Windows describe offered bursts on the
// separate, already verified ports. No change to DUT grants or response timing.
integer ddr_window=0,ddr_fd=0,ddr_cycles=0,ddr_rows=0;
longint unsigned ddr_start,ddr_initial_bursts;
string ddr_trace;
wire [63:0] ddr_observed_bursts=measure_camera_bursts+measure_mean_bursts+measure_attr_bursts+
    measure_qsu_read_bursts+measure_qsu_write_bursts+measure_state_read_bursts+measure_out_write_bursts;
initial begin
    if(!$value$plusargs("DDR_TRACE=%s",ddr_trace))$fatal(1,"missing trace path");
    ddr_fd=$fopen(ddr_trace,"w");
    if(!ddr_fd)$fatal(1,"cannot open DDR address trace");
end
task automatic ddr_address(input integer port_id,input logic [63:0] addr,input logic [7:0] len,
                            input logic [2:0] size,input logic [1:0] burst);
    integer beats;
    beats=int'(len)+1;
    if(size!=4 || burst!=1 || addr[3:0]!=0 || int'(addr[11:0])+16*beats>4096)
        $fatal(1,"bad AXI burst in DDR capture");
    $fdisplay(ddr_fd,"%0d %0d %0d %h %0d",ddr_window,measure_tick,port_id,addr,beats);
    ddr_rows++;
endtask
always @(posedge clk_i) if(rst_ni)begin
    if(ddr_cycles==8192)begin
        if(ddr_rows==0 || ddr_observed_bursts-ddr_initial_bursts!=ddr_rows)$fatal(1,"window handshake mismatch");
        $display("DDR_WINDOW window=%0d start=%0d stop=%0d bursts=%0d",ddr_window,ddr_start,measure_tick,ddr_rows);
        ddr_window++;
        ddr_cycles=0;
        if(ddr_window==4)begin
            $fclose(ddr_fd);
            $display("PASS T08 DDR address windows");$finish;
        end
    end
    if(ddr_cycles>0 || (ddr_window==0 && dut.command_accept) ||
       (ddr_window==1 && measure_qsu_reads>0) ||
       (ddr_window==2 && perf_commit_count_o>=32768) ||
       (ddr_window==3 && perf_commit_count_o>=262144))begin
        if(ddr_cycles==0)begin
            ddr_start=measure_tick;ddr_initial_bursts=ddr_observed_bursts;ddr_rows=0;
        end
        if(m_axi_camera_arvalid_o&&m_axi_camera_arready_i)
            ddr_address(0,m_axi_camera_araddr_o,m_axi_camera_arlen_o,m_axi_camera_arsize_o,m_axi_camera_arburst_o);
        if(m_axi_mean_arvalid_o&&m_axi_mean_arready_i)
            ddr_address(1,m_axi_mean_araddr_o,m_axi_mean_arlen_o,m_axi_mean_arsize_o,m_axi_mean_arburst_o);
        if(m_axi_attr_arvalid_o&&m_axi_attr_arready_i)
            ddr_address(2,m_axi_attr_araddr_o,m_axi_attr_arlen_o,m_axi_attr_arsize_o,m_axi_attr_arburst_o);
        if(m_axi_qsu_arvalid_o&&m_axi_qsu_arready_i)
            ddr_address(3,m_axi_qsu_araddr_o,m_axi_qsu_arlen_o,m_axi_qsu_arsize_o,m_axi_qsu_arburst_o);
        if(m_axi_qsu_awvalid_o&&m_axi_qsu_awready_i)
            ddr_address(4,m_axi_qsu_awaddr_o,m_axi_qsu_awlen_o,m_axi_qsu_awsize_o,m_axi_qsu_awburst_o);
        if(m_axi_state_arvalid_o&&m_axi_state_arready_i)
            ddr_address(5,m_axi_state_araddr_o,m_axi_state_arlen_o,m_axi_state_arsize_o,m_axi_state_arburst_o);
        if(m_axi_out_awvalid_o&&m_axi_out_awready_i)
            ddr_address(6,m_axi_out_awaddr_o,m_axi_out_awlen_o,m_axi_out_awsize_o,m_axi_out_awburst_o);
        ddr_cycles++;
    end
end
