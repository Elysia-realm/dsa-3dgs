// Fully-associative dirty-pixel buffer in front of the unique AXI writer.
// Each entry stores a complete pixel tag and the exact 128-bit backing record.
// Repeated queued updates keep only the newest record. A full buffer evicts
// its oldest entry; flush drains all entries before system frame completion.
module axi4_pixel_state_writeback_buffer #(
    parameter int unsigned ADDR_W=64,parameter int unsigned DATA_W=128,
    parameter int unsigned ID_W=2,parameter int unsigned DEPTH=32,
    parameter int unsigned PTR_W=(DEPTH<=2)?1:$clog2(DEPTH),
    parameter int unsigned COUNT_W=$clog2(DEPTH+1)
) (
    input logic clk_i,input logic rst_ni,input logic clear_error_i,input logic flush_i,
    input logic[ADDR_W-1:0]base_addr_i,
    input logic s_valid_i,output logic s_ready_o,input logic[31:0]s_pixel_id_i,
    input logic[31:0]s_gid_i,input logic[15:0]s_epoch_id_i,input logic[12:0]s_alpha_q12_i,
    input logic s_pass_alpha_i,input logic[12:0]s_r_q12_i,s_g_q12_i,s_b_q12_i,
    input logic[15:0]s_t_q16_i,input logic s_newly_terminated_i,
    input logic[31:0]lookup_pixel_id_i,output logic lookup_hit_o,output logic[127:0]lookup_data_o,
    output logic busy_o,flush_busy_o,output logic error_sticky_o,output logic[1:0]error_status_o,
    output logic[COUNT_W-1:0]occupancy_o,output logic[63:0]coalesced_count_o,
    output logic[ID_W-1:0]m_axi_awid_o,output logic[ADDR_W-1:0]m_axi_awaddr_o,
    output logic[7:0]m_axi_awlen_o,output logic[2:0]m_axi_awsize_o,
    output logic[1:0]m_axi_awburst_o,output logic m_axi_awvalid_o,input logic m_axi_awready_i,
    output logic[DATA_W-1:0]m_axi_wdata_o,output logic[DATA_W/8-1:0]m_axi_wstrb_o,
    output logic m_axi_wlast_o,m_axi_wvalid_o,input logic m_axi_wready_i,
    input logic[ID_W-1:0]m_axi_bid_i,input logic[1:0]m_axi_bresp_i,
    input logic m_axi_bvalid_i,output logic m_axi_bready_o
);
    logic[31:0]pixel_mem[0:DEPTH-1];logic[127:0]data_mem[0:DEPTH-1];logic[DEPTH-1:0]valid_q;
    logic[PTR_W-1:0]read_q,write_q,input_hit_index;logic input_hit,input_hits_head;
    logic[127:0]input_data,head_data,active_data_q;logic[31:0]head_pixel,active_pixel_q;
    logic writer_ready,writer_busy,writer_request,allocate,coalesce,pop,flush_q,active_valid_q;
    integer index;

    always_comb begin
      input_data='0;input_data[12:0]=s_r_q12_i;input_data[25:13]=s_g_q12_i;
      input_data[38:26]=s_b_q12_i;input_data[54:39]=s_t_q16_i;input_data[70:55]=s_epoch_id_i;
      input_data[83:71]=s_alpha_q12_i;input_data[84]=s_pass_alpha_i;
      input_data[85]=s_newly_terminated_i;input_data[117:86]=s_gid_i;
    end
    assign head_pixel=pixel_mem[read_q];assign head_data=data_mem[read_q];

    always_comb begin
      input_hit=0;input_hit_index='0;
      for(index=0;index<DEPTH;index=index+1)
        if(!input_hit&&valid_q[index]&&pixel_mem[index]==s_pixel_id_i)begin
          input_hit=1;input_hit_index=index[PTR_W-1:0];end
    end
    assign input_hits_head=s_valid_i&&input_hit&&input_hit_index==read_q;
    assign s_ready_o=!flush_q&&(input_hit||occupancy_o<DEPTH);
    assign coalesce=s_valid_i&&s_ready_o&&input_hit;
    assign allocate=s_valid_i&&s_ready_o&&!input_hit;
    assign writer_request=occupancy_o!=0&&(flush_q||(occupancy_o==DEPTH&&!input_hits_head));
    assign pop=writer_request&&writer_ready;
    assign busy_o=occupancy_o!=0||writer_busy||active_valid_q||flush_q;
    assign flush_busy_o=flush_q;

    // A queued record is newer than an active writer record of the same pixel,
    // so queued lookup has priority over the active AXI transaction.
    always_comb begin
      lookup_hit_o=0;lookup_data_o='0;
      for(index=0;index<DEPTH;index=index+1)
        if(valid_q[index]&&pixel_mem[index]==lookup_pixel_id_i)begin
          lookup_hit_o=1;lookup_data_o=data_mem[index];end
      if(!lookup_hit_o&&active_valid_q&&active_pixel_q==lookup_pixel_id_i)begin
        lookup_hit_o=1;lookup_data_o=active_data_q;end
    end

    axi4_pixel_state_write_engine #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W))u_writer(
      .clk_i(clk_i),.rst_ni(rst_ni),.clear_error_i(clear_error_i),.base_addr_i(base_addr_i),
      .s_valid_i(writer_request),.s_ready_o(writer_ready),.s_pixel_id_i(head_pixel),
      .s_gid_i(head_data[117:86]),.s_epoch_id_i(head_data[70:55]),
      .s_alpha_q12_i(head_data[83:71]),.s_pass_alpha_i(head_data[84]),
      .s_r_q12_i(head_data[12:0]),.s_g_q12_i(head_data[25:13]),.s_b_q12_i(head_data[38:26]),
      .s_t_q16_i(head_data[54:39]),.s_newly_terminated_i(head_data[85]),
      .busy_o(writer_busy),.error_sticky_o(error_sticky_o),.error_status_o(error_status_o),
      .m_axi_awid_o(m_axi_awid_o),.m_axi_awaddr_o(m_axi_awaddr_o),.m_axi_awlen_o(m_axi_awlen_o),
      .m_axi_awsize_o(m_axi_awsize_o),.m_axi_awburst_o(m_axi_awburst_o),.m_axi_awvalid_o(m_axi_awvalid_o),
      .m_axi_awready_i(m_axi_awready_i),.m_axi_wdata_o(m_axi_wdata_o),.m_axi_wstrb_o(m_axi_wstrb_o),
      .m_axi_wlast_o(m_axi_wlast_o),.m_axi_wvalid_o(m_axi_wvalid_o),.m_axi_wready_i(m_axi_wready_i),
      .m_axi_bid_i(m_axi_bid_i),.m_axi_bresp_i(m_axi_bresp_i),.m_axi_bvalid_i(m_axi_bvalid_i),
      .m_axi_bready_o(m_axi_bready_o));

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        read_q<='0;write_q<='0;occupancy_o<='0;valid_q<='0;flush_q<=0;
        active_valid_q<=0;active_pixel_q<=0;active_data_q<=0;coalesced_count_o<=0;
      end else begin
        if(flush_i)flush_q<=1;
        if(flush_q&&occupancy_o==0&&!writer_busy&&!active_valid_q)flush_q<=0;
        if(clear_error_i)coalesced_count_o<=0;
        if(coalesce)begin data_mem[input_hit_index]<=input_data;pixel_mem[input_hit_index]<=s_pixel_id_i;
          if(!(&coalesced_count_o))coalesced_count_o<=coalesced_count_o+1'b1;end
        if(allocate)begin data_mem[write_q]<=input_data;pixel_mem[write_q]<=s_pixel_id_i;
          valid_q[write_q]<=1;write_q<=write_q==DEPTH-1?'0:write_q+1'b1;end
        if(pop)begin valid_q[read_q]<=0;read_q<=read_q==DEPTH-1?'0:read_q+1'b1;
          active_valid_q<=1;active_pixel_q<=head_pixel;active_data_q<=head_data;end
        else if(active_valid_q&&!writer_busy)active_valid_q<=0;
        case({allocate,pop})2'b10:occupancy_o<=occupancy_o+1'b1;
          2'b01:occupancy_o<=occupancy_o-1'b1;default:occupancy_o<=occupancy_o;endcase
      end
    end
`ifndef SYNTHESIS
    initial begin assert(DEPTH>=2);assert(DATA_W==128);end
`endif
endmodule
