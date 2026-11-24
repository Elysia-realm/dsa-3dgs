// Single-beat AXI4 reader for the write-through pixel backing store.
module axi4_pixel_state_read_engine #(
    parameter int unsigned ADDR_W=64,parameter int unsigned DATA_W=128,
    parameter int unsigned ID_W=2,parameter int unsigned PIXEL_W=32,
    parameter logic[ID_W-1:0]AXI_ID='0
) (
    input logic clk_i,input logic rst_ni,input logic clear_error_i,input logic[ADDR_W-1:0]base_addr_i,
    input logic req_valid_i,output logic req_ready_o,input logic[PIXEL_W-1:0]req_pixel_id_i,
    output logic rsp_valid_o,input logic rsp_ready_i,output logic rsp_error_o,
    output logic[DATA_W-1:0]rsp_data_o,output logic busy_o,
    output logic error_sticky_o,output logic[1:0]error_status_o,
    output logic[ID_W-1:0]m_axi_arid_o,output logic[ADDR_W-1:0]m_axi_araddr_o,
    output logic[7:0]m_axi_arlen_o,output logic[2:0]m_axi_arsize_o,
    output logic[1:0]m_axi_arburst_o,output logic m_axi_arvalid_o,input logic m_axi_arready_i,
    input logic[ID_W-1:0]m_axi_rid_i,input logic[DATA_W-1:0]m_axi_rdata_i,
    input logic[1:0]m_axi_rresp_i,input logic m_axi_rlast_i,m_axi_rvalid_i,output logic m_axi_rready_o
);
    localparam int unsigned SIZE_CODE=$clog2(DATA_W/8);
    typedef enum logic[1:0]{S_IDLE,S_AR,S_R,S_RSP}state_t;state_t state_q;
    logic[ADDR_W-1:0]addr_q;logic[DATA_W-1:0]data_q;logic rsp_error_q;
    assign req_ready_o=state_q==S_IDLE;assign rsp_valid_o=state_q==S_RSP;
    assign rsp_error_o=rsp_error_q;assign rsp_data_o=data_q;assign busy_o=state_q!=S_IDLE;
    assign error_sticky_o=|error_status_o;assign m_axi_arid_o=AXI_ID;assign m_axi_araddr_o=addr_q;
    assign m_axi_arlen_o=0;assign m_axi_arsize_o=SIZE_CODE[2:0];assign m_axi_arburst_o=2'b01;
    assign m_axi_arvalid_o=state_q==S_AR;assign m_axi_rready_o=state_q==S_R;
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin state_q<=S_IDLE;addr_q<=0;data_q<=0;rsp_error_q<=0;error_status_o<=0;end
      else begin
        if(clear_error_i&&state_q==S_IDLE)error_status_o<=0;
        case(state_q)
          S_IDLE:if(req_valid_i)begin
            addr_q<=base_addr_i+({{(ADDR_W-PIXEL_W){1'b0}},req_pixel_id_i}<<SIZE_CODE);
            rsp_error_q<=0;
            if(base_addr_i[SIZE_CODE-1:0]!=0)begin rsp_error_q<=1;error_status_o[1]<=1;state_q<=S_RSP;end
            else state_q<=S_AR;
          end
          S_AR:if(m_axi_arready_i)state_q<=S_R;
          S_R:if(m_axi_rvalid_i)begin
            data_q<=m_axi_rdata_i;
            if(m_axi_rid_i!=AXI_ID||m_axi_rresp_i!=0||!m_axi_rlast_i)begin
              rsp_error_q<=1;error_status_o[0]<=1;
            end
            state_q<=S_RSP;
          end
          S_RSP:if(rsp_ready_i)state_q<=S_IDLE;
          default:state_q<=S_IDLE;
        endcase
      end
    end
endmodule
