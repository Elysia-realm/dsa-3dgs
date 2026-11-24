// Ordered commit FIFO in front of the single-outstanding AXI state writer.
// It decouples the blend pipeline from B-response latency.  A full-pixel tag
// CAM reports hazards so state reads for unrelated pixels may overlap writes,
// while a conflicting read waits until the newest queued write reaches DRAM.
module axi4_pixel_state_write_buffer #(
    parameter int unsigned ADDR_W=64,parameter int unsigned DATA_W=128,
    parameter int unsigned ID_W=2,parameter int unsigned DEPTH=8,
    parameter int unsigned PTR_W=(DEPTH<=2)?1:$clog2(DEPTH),
    parameter int unsigned COUNT_W=$clog2(DEPTH+1)
) (
    input logic clk_i,input logic rst_ni,input logic clear_error_i,
    input logic[ADDR_W-1:0]base_addr_i,
    input logic s_valid_i,output logic s_ready_o,input logic[31:0]s_pixel_id_i,
    input logic[31:0]s_gid_i,input logic[15:0]s_epoch_id_i,
    input logic[12:0]s_alpha_q12_i,input logic s_pass_alpha_i,
    input logic[12:0]s_r_q12_i,s_g_q12_i,s_b_q12_i,input logic[15:0]s_t_q16_i,
    input logic s_newly_terminated_i,
    input logic[31:0]hazard_pixel_id_i,output logic hazard_o,
    output logic busy_o,output logic error_sticky_o,output logic[1:0]error_status_o,
    output logic[COUNT_W-1:0]occupancy_o,
    output logic[ID_W-1:0]m_axi_awid_o,output logic[ADDR_W-1:0]m_axi_awaddr_o,
    output logic[7:0]m_axi_awlen_o,output logic[2:0]m_axi_awsize_o,
    output logic[1:0]m_axi_awburst_o,output logic m_axi_awvalid_o,input logic m_axi_awready_i,
    output logic[DATA_W-1:0]m_axi_wdata_o,output logic[DATA_W/8-1:0]m_axi_wstrb_o,
    output logic m_axi_wlast_o,m_axi_wvalid_o,input logic m_axi_wready_i,
    input logic[ID_W-1:0]m_axi_bid_i,input logic[1:0]m_axi_bresp_i,
    input logic m_axi_bvalid_i,output logic m_axi_bready_o
);
    localparam int unsigned ENTRY_W=32+32+16+13+1+3*13+16+1;
    logic[ENTRY_W-1:0]mem[0:DEPTH-1];logic[31:0]pixel_mem[0:DEPTH-1];
    logic[DEPTH-1:0]valid_q;logic[PTR_W-1:0]read_q,write_q;
    logic[ENTRY_W-1:0]head_data;logic writer_ready,writer_busy;
    logic push,pop,active_valid_q;logic[31:0]active_pixel_q;integer index;
    logic[31:0]head_pixel,head_gid;logic[15:0]head_epoch;logic[12:0]head_alpha;
    logic head_pass;logic[12:0]head_r,head_g,head_b;logic[15:0]head_t;logic head_terminated;

    assign s_ready_o=occupancy_o<DEPTH;assign push=s_valid_i&&s_ready_o;
    assign head_data=mem[read_q];
    assign {head_pixel,head_gid,head_epoch,head_alpha,head_pass,head_r,head_g,head_b,head_t,head_terminated}=head_data;
    assign pop=occupancy_o!=0&&writer_ready;
    assign busy_o=occupancy_o!=0||writer_busy||active_valid_q;

    always_comb begin
      hazard_o=active_valid_q&&active_pixel_q==hazard_pixel_id_i;
      for(index=0;index<DEPTH;index=index+1)
        if(valid_q[index]&&pixel_mem[index]==hazard_pixel_id_i)hazard_o=1'b1;
    end

    axi4_pixel_state_write_engine #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W))u_writer(
      .clk_i(clk_i),.rst_ni(rst_ni),.clear_error_i(clear_error_i),.base_addr_i(base_addr_i),
      .s_valid_i(occupancy_o!=0),.s_ready_o(writer_ready),.s_pixel_id_i(head_pixel),.s_gid_i(head_gid),
      .s_epoch_id_i(head_epoch),.s_alpha_q12_i(head_alpha),.s_pass_alpha_i(head_pass),
      .s_r_q12_i(head_r),.s_g_q12_i(head_g),.s_b_q12_i(head_b),.s_t_q16_i(head_t),
      .s_newly_terminated_i(head_terminated),.busy_o(writer_busy),.error_sticky_o(error_sticky_o),
      .error_status_o(error_status_o),.m_axi_awid_o(m_axi_awid_o),.m_axi_awaddr_o(m_axi_awaddr_o),
      .m_axi_awlen_o(m_axi_awlen_o),.m_axi_awsize_o(m_axi_awsize_o),.m_axi_awburst_o(m_axi_awburst_o),
      .m_axi_awvalid_o(m_axi_awvalid_o),.m_axi_awready_i(m_axi_awready_i),.m_axi_wdata_o(m_axi_wdata_o),
      .m_axi_wstrb_o(m_axi_wstrb_o),.m_axi_wlast_o(m_axi_wlast_o),.m_axi_wvalid_o(m_axi_wvalid_o),
      .m_axi_wready_i(m_axi_wready_i),.m_axi_bid_i(m_axi_bid_i),.m_axi_bresp_i(m_axi_bresp_i),
      .m_axi_bvalid_i(m_axi_bvalid_i),.m_axi_bready_o(m_axi_bready_o));

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin read_q<='0;write_q<='0;occupancy_o<='0;valid_q<='0;active_valid_q<=0;active_pixel_q<=0;end
      else begin
        if(push)begin
          mem[write_q]<={s_pixel_id_i,s_gid_i,s_epoch_id_i,s_alpha_q12_i,s_pass_alpha_i,
            s_r_q12_i,s_g_q12_i,s_b_q12_i,s_t_q16_i,s_newly_terminated_i};
          pixel_mem[write_q]<=s_pixel_id_i;valid_q[write_q]<=1;
          write_q<=write_q==DEPTH-1?'0:write_q+1'b1;
        end
        if(pop)begin
          valid_q[read_q]<=0;read_q<=read_q==DEPTH-1?'0:read_q+1'b1;
          active_valid_q<=1;active_pixel_q<=head_pixel;
        end else if(active_valid_q&&!writer_busy)active_valid_q<=0;
        case({push,pop})2'b10:occupancy_o<=occupancy_o+1'b1;
          2'b01:occupancy_o<=occupancy_o-1'b1;default:occupancy_o<=occupancy_o;endcase
      end
    end
`ifndef SYNTHESIS
    initial assert(DEPTH>=2);
    assert property(@(posedge clk_i)disable iff(!rst_ni)s_valid_i&&!s_ready_o|=>
      s_valid_i&&$stable({s_pixel_id_i,s_gid_i,s_epoch_id_i,s_alpha_q12_i,s_pass_alpha_i,
        s_r_q12_i,s_g_q12_i,s_b_q12_i,s_t_q16_i,s_newly_terminated_i}));
`endif
endmodule
