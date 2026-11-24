// AXI4 backend for sorted global-GID attribute requests. One logical
// Gaussian record is 144 bytes (nine 128-bit beats); bits [1117:0] contain the
// internal full-attribute vector and bits [1151:1118] are reserved. A record
// crossing 4 KiB is split into legal INCR bursts and reassembled atomically.
module axi4_gaussian_attribute_read_engine #(
    parameter int unsigned ADDR_W=64,parameter int unsigned DATA_W=128,
    parameter int unsigned ID_W=2,parameter int unsigned GID_W=32,
    parameter int unsigned ATTR_W=1118,parameter int unsigned RECORD_BEATS=9,
    parameter int unsigned RECORD_BYTES=RECORD_BEATS*(DATA_W/8),
    parameter logic[ID_W-1:0]AXI_ID='0
) (
    input logic clk_i,input logic rst_ni,input logic clear_error_i,
    input logic[ADDR_W-1:0]base_addr_i,
    input logic req_valid_i,output logic req_ready_o,input logic[GID_W-1:0]req_gid_i,
    output logic rsp_valid_o,input logic rsp_ready_i,output logic rsp_error_o,
    output logic[ATTR_W-1:0]rsp_data_o,output logic busy_o,
    output logic error_sticky_o,output logic[1:0]error_status_o,
    output logic[ID_W-1:0]m_axi_arid_o,output logic[ADDR_W-1:0]m_axi_araddr_o,
    output logic[7:0]m_axi_arlen_o,output logic[2:0]m_axi_arsize_o,
    output logic[1:0]m_axi_arburst_o,output logic m_axi_arvalid_o,input logic m_axi_arready_i,
    input logic[ID_W-1:0]m_axi_rid_i,input logic[DATA_W-1:0]m_axi_rdata_i,
    input logic[1:0]m_axi_rresp_i,input logic m_axi_rlast_i,m_axi_rvalid_i,
    output logic m_axi_rready_o
);
    localparam int unsigned BEAT_BYTES=DATA_W/8;
    localparam int unsigned SIZE_CODE=$clog2(BEAT_BYTES);
    localparam int unsigned PACK_W=RECORD_BEATS*DATA_W;
    typedef enum logic[2:0]{S_IDLE,S_AR,S_R,S_NEXT,S_ERROR_DRAIN,S_RSP}state_t;
    state_t state_q;
    logic[ADDR_W-1:0]next_addr_q;logic[4:0]remaining_beats_q,burst_beats_q,beat_index_q,total_index_q;
    logic[PACK_W-1:0]record_q;logic rsp_error_q;
    logic[12:0]bytes_to_boundary;logic[8:0]boundary_beats;logic[4:0]planned_beats;
    logic expected_last,r_fire,r_error;
    logic[ADDR_W+GID_W-1:0]gid_byte_offset;

    assign gid_byte_offset=req_gid_i*RECORD_BYTES;
    always_comb begin
      bytes_to_boundary=13'd4096-{1'b0,next_addr_q[11:0]};
      boundary_beats=bytes_to_boundary>>SIZE_CODE;
      planned_beats=remaining_beats_q;
      if(boundary_beats<planned_beats)planned_beats=boundary_beats[4:0];
    end
    assign req_ready_o=state_q==S_IDLE;
    assign rsp_valid_o=state_q==S_RSP;assign rsp_error_o=rsp_error_q;
    assign rsp_data_o=record_q[ATTR_W-1:0];assign busy_o=state_q!=S_IDLE;
    assign error_sticky_o=|error_status_o;
    assign m_axi_arid_o=AXI_ID;assign m_axi_araddr_o=next_addr_q;
    assign m_axi_arlen_o=planned_beats-1'b1;assign m_axi_arsize_o=SIZE_CODE[2:0];
    assign m_axi_arburst_o=2'b01;assign m_axi_arvalid_o=state_q==S_AR;
    assign m_axi_rready_o=(state_q==S_R)||(state_q==S_ERROR_DRAIN);
    assign r_fire=m_axi_rvalid_i&&m_axi_rready_o;
    assign expected_last=beat_index_q+1'b1==burst_beats_q;
    assign r_error=(m_axi_rid_i!=AXI_ID)||(m_axi_rresp_i!=2'b00)||(m_axi_rlast_i!=expected_last);

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        state_q<=S_IDLE;next_addr_q<='0;remaining_beats_q<='0;burst_beats_q<='0;
        beat_index_q<='0;total_index_q<='0;record_q<='0;rsp_error_q<=0;error_status_o<=0;
      end else begin
        if(clear_error_i&&state_q==S_IDLE)error_status_o<=0;
        case(state_q)
          S_IDLE:if(req_valid_i)begin
            record_q<='0;rsp_error_q<=0;remaining_beats_q<=RECORD_BEATS;total_index_q<=0;
            next_addr_q<=base_addr_i+gid_byte_offset[ADDR_W-1:0];
            if(base_addr_i[SIZE_CODE-1:0]!=0)begin
              rsp_error_q<=1;error_status_o[1]<=1;state_q<=S_RSP;
            end else state_q<=S_AR;
          end
          S_AR:if(m_axi_arvalid_o&&m_axi_arready_i)begin
            burst_beats_q<=planned_beats;beat_index_q<=0;
            next_addr_q<=next_addr_q+planned_beats*BEAT_BYTES;state_q<=S_R;
          end
          S_R:if(r_fire)begin
            if(r_error)begin
              rsp_error_q<=1;error_status_o[0]<=1;
              if(m_axi_rlast_i||expected_last)state_q<=S_RSP;else state_q<=S_ERROR_DRAIN;
            end else begin
              record_q[total_index_q*DATA_W+:DATA_W]<=m_axi_rdata_i;
              total_index_q<=total_index_q+1'b1;beat_index_q<=beat_index_q+1'b1;
              remaining_beats_q<=remaining_beats_q-1'b1;
              if(expected_last)begin
                if(remaining_beats_q==1)state_q<=S_RSP;else state_q<=S_NEXT;
              end
            end
          end
          S_NEXT:state_q<=S_AR;
          S_ERROR_DRAIN:if(r_fire&&m_axi_rlast_i)state_q<=S_RSP;
          S_RSP:if(rsp_ready_i)state_q<=S_IDLE;
          default:state_q<=S_IDLE;
        endcase
      end
    end
`ifndef SYNTHESIS
    initial begin assert(DATA_W==128);assert(RECORD_BEATS==9);assert(ATTR_W<=PACK_W);end
    assert property(@(posedge clk_i)disable iff(!rst_ni)rsp_valid_o&&!rsp_ready_i
      |=>rsp_valid_o&&$stable({rsp_error_o,rsp_data_o}));
`endif
endmodule
