// AXI slave model, not a sorting surrogate. Stores ONLY bytes written by RTL.
// AW and W queues are independent; a B is released only after both arrived.
logic [127:0] qsu_memory[0:2*MAX_COUNT-1];
logic [63:0] qsu_aw_queue[0:63];logic [127:0] qsu_w_queue[0:63];
integer qsu_b_time[0:63];
integer qsu_aw_put=0,qsu_w_put=0,qsu_committed=0,qsu_b_get=0;
integer qsu_read_index=0,qsu_read_left=0,qsu_read_delay=0,qsu_tick=0;
integer qsu_read_count=0,qsu_write_count=0;
logic qsu_requested=0;
always @(negedge clk_i)begin
  if(rst_ni)begin
    m_axi_qsu_arready_i=(qsu_read_left==0)&&(qsu_tick%ready_period>=ready_low);
    m_axi_qsu_awready_i=qsu_aw_put-qsu_b_get<32&&(qsu_tick%ready_period>=ready_low);
    m_axi_qsu_wready_i=qsu_w_put-qsu_b_get<32&&((qsu_tick+1)%ready_period>=ready_low);
    m_axi_qsu_rvalid_i=qsu_read_left!=0&&qsu_read_delay==0;
    m_axi_qsu_rlast_i=qsu_read_left==1;
    if(qsu_read_left!=0)m_axi_qsu_rdata_i=qsu_memory[qsu_read_index];
    m_axi_qsu_bvalid_i=qsu_b_get<qsu_committed&&qsu_tick>=qsu_b_time[qsu_b_get%64];
  end
end
always @(posedge clk_i)if(rst_ni)begin
  qsu_tick<=qsu_tick+1;
  if(qsu_read_delay>0)qsu_read_delay<=qsu_read_delay-1;
  if(m_axi_qsu_arvalid_o&&m_axi_qsu_arready_i)begin
    if(m_axi_qsu_araddr_o<64'h10000000||m_axi_qsu_araddr_o[3:0]!=0||m_axi_qsu_arsize_o!=4||m_axi_qsu_arburst_o!=1||
       (m_axi_qsu_araddr_o-64'h10000000)/16+m_axi_qsu_arlen_o>=2*workload_count||
       m_axi_qsu_araddr_o[11:0]+(m_axi_qsu_arlen_o+1)*16>4096)$fatal(1,"QSU read range/burst error");
    qsu_read_index<=(m_axi_qsu_araddr_o-64'h10000000)/16;
    qsu_read_left<=m_axi_qsu_arlen_o+1;qsu_read_delay<=read_latency;
  end
  if(m_axi_qsu_rvalid_i&&m_axi_qsu_rready_o)begin
    qsu_read_index<=qsu_read_index+1;qsu_read_left<=qsu_read_left-1;
    qsu_read_delay<=read_gap;qsu_read_count<=qsu_read_count+1;
  end
  if(m_axi_qsu_awvalid_o&&m_axi_qsu_awready_i)begin
    if(m_axi_qsu_awaddr_o<64'h10000000||m_axi_qsu_awaddr_o[3:0]!=0||m_axi_qsu_awlen_o!=0||m_axi_qsu_awsize_o!=4||m_axi_qsu_awburst_o!=1||
       (m_axi_qsu_awaddr_o-64'h10000000)/16>=2*workload_count)$fatal(1,"QSU write range/burst error");
    qsu_aw_queue[qsu_aw_put%64]<=m_axi_qsu_awaddr_o;qsu_aw_put<=qsu_aw_put+1;
  end
  if(m_axi_qsu_wvalid_o&&m_axi_qsu_wready_i)begin
    if(!m_axi_qsu_wlast_o||m_axi_qsu_wstrb_o!=16'hffff)$fatal(1,"QSU invalid write beat");
    qsu_w_queue[qsu_w_put%64]<=m_axi_qsu_wdata_o;qsu_w_put<=qsu_w_put+1;
  end
  if(qsu_committed<qsu_aw_put&&qsu_committed<qsu_w_put)begin
    qsu_memory[(qsu_aw_queue[qsu_committed%64]-64'h10000000)/16]<=qsu_w_queue[qsu_committed%64];
    qsu_b_time[qsu_committed%64]<=qsu_tick+write_response_latency;
    qsu_committed<=qsu_committed+1;qsu_write_count<=qsu_write_count+1;
  end
  if(m_axi_qsu_bvalid_i&&m_axi_qsu_bready_o)qsu_b_get<=qsu_b_get+1;
end
