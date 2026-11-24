// Ordered AXI4 writer for committed pixel state. The renderer has one
// stateful blend/image-state writer, and this engine preserves that order by
// allowing one write transaction outstanding. Each pixel occupies 16 bytes at
// OUTPUT_BASE + pixel_id*16, so later updates to the same pixel overwrite the
// earlier state and the final DRAM value is the final rendered pixel.
module axi4_pixel_state_write_engine #(
    parameter int unsigned ADDR_W=64,parameter int unsigned DATA_W=128,
    parameter int unsigned ID_W=2,parameter logic[ID_W-1:0]AXI_ID='0
) (
    input logic clk_i,input logic rst_ni,input logic clear_error_i,
    input logic[ADDR_W-1:0]base_addr_i,
    input logic s_valid_i,output logic s_ready_o,input logic[31:0]s_pixel_id_i,
    input logic[31:0]s_gid_i,input logic[15:0]s_epoch_id_i,
    input logic[12:0]s_alpha_q12_i,input logic s_pass_alpha_i,
    input logic[12:0]s_r_q12_i,s_g_q12_i,s_b_q12_i,input logic[15:0]s_t_q16_i,
    input logic s_newly_terminated_i,
    output logic busy_o,output logic error_sticky_o,output logic[1:0]error_status_o,
    output logic[ID_W-1:0]m_axi_awid_o,output logic[ADDR_W-1:0]m_axi_awaddr_o,
    output logic[7:0]m_axi_awlen_o,output logic[2:0]m_axi_awsize_o,
    output logic[1:0]m_axi_awburst_o,output logic m_axi_awvalid_o,input logic m_axi_awready_i,
    output logic[DATA_W-1:0]m_axi_wdata_o,output logic[DATA_W/8-1:0]m_axi_wstrb_o,
    output logic m_axi_wlast_o,m_axi_wvalid_o,input logic m_axi_wready_i,
    input logic[ID_W-1:0]m_axi_bid_i,input logic[1:0]m_axi_bresp_i,
    input logic m_axi_bvalid_i,output logic m_axi_bready_o
);
    localparam int unsigned BEAT_BYTES=DATA_W/8;
    localparam int unsigned SIZE_CODE=$clog2(BEAT_BYTES);
    typedef enum logic[1:0]{S_IDLE,S_SEND,S_RESP,S_CFG_ERROR}state_t;
    state_t state_q;
    logic aw_pending_q,w_pending_q;
    logic[ADDR_W-1:0]addr_q;logic[DATA_W-1:0]data_q;
    logic request_fire,aw_fire,w_fire,b_fire;

    assign s_ready_o=state_q==S_IDLE;
    assign request_fire=s_valid_i&&s_ready_o;
    assign busy_o=state_q!=S_IDLE;
    assign error_sticky_o=|error_status_o;
    assign m_axi_awid_o=AXI_ID;assign m_axi_awaddr_o=addr_q;
    assign m_axi_awlen_o=0;assign m_axi_awsize_o=SIZE_CODE[2:0];assign m_axi_awburst_o=2'b01;
    assign m_axi_awvalid_o=state_q==S_SEND&&aw_pending_q;
    assign m_axi_wdata_o=data_q;assign m_axi_wstrb_o={DATA_W/8{1'b1}};assign m_axi_wlast_o=1'b1;
    assign m_axi_wvalid_o=state_q==S_SEND&&w_pending_q;
    assign m_axi_bready_o=state_q==S_RESP;
    assign aw_fire=m_axi_awvalid_o&&m_axi_awready_i;
    assign w_fire=m_axi_wvalid_o&&m_axi_wready_i;
    assign b_fire=m_axi_bvalid_i&&m_axi_bready_o;

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        state_q<=S_IDLE;aw_pending_q<=0;w_pending_q<=0;addr_q<='0;data_q<='0;error_status_o<=0;
      end else begin
        if(clear_error_i&&state_q==S_IDLE)error_status_o<=0;
        case(state_q)
          S_IDLE:if(request_fire)begin
            addr_q<=base_addr_i+({{(ADDR_W-32){1'b0}},s_pixel_id_i}<<SIZE_CODE);
            data_q<='0;
            data_q[12:0]<=s_r_q12_i;data_q[25:13]<=s_g_q12_i;data_q[38:26]<=s_b_q12_i;
            data_q[54:39]<=s_t_q16_i;data_q[70:55]<=s_epoch_id_i;data_q[83:71]<=s_alpha_q12_i;
            data_q[84]<=s_pass_alpha_i;data_q[85]<=s_newly_terminated_i;data_q[117:86]<=s_gid_i;
            if(base_addr_i[SIZE_CODE-1:0]!=0)begin
              error_status_o[1]<=1;state_q<=S_CFG_ERROR;
            end else begin
              aw_pending_q<=1;w_pending_q<=1;state_q<=S_SEND;
            end
          end
          S_SEND:begin
            if(aw_fire)aw_pending_q<=0;if(w_fire)w_pending_q<=0;
            if((!aw_pending_q||aw_fire)&&(!w_pending_q||w_fire))state_q<=S_RESP;
          end
          S_RESP:if(b_fire)begin
            if(m_axi_bid_i!=AXI_ID||m_axi_bresp_i!=2'b00)error_status_o[0]<=1;
            state_q<=S_IDLE;
          end
          S_CFG_ERROR:state_q<=S_IDLE;
          default:state_q<=S_IDLE;
        endcase
      end
    end
`ifndef SYNTHESIS
    initial assert(DATA_W==128);
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_axi_awvalid_o&&!m_axi_awready_i
      |=>m_axi_awvalid_o&&$stable(m_axi_awaddr_o));
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_axi_wvalid_o&&!m_axi_wready_i
      |=>m_axi_wvalid_o&&$stable({m_axi_wdata_o,m_axi_wstrb_o,m_axi_wlast_o}));
`endif
endmodule
