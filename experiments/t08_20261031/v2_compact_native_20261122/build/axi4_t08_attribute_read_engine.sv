// T08 candidate: fixed 144-byte GID slots, legacy or header-first v1 DMA.
// One request owns the port until all responses (including error drain) finish.
module axi4_t08_attribute_read_engine #(
  parameter bit EARLY_ADVANCE=1'b0,
  parameter int unsigned ADDR_W=64,ID_W=2,GID_W=32,
  parameter logic [ID_W-1:0] AXI_ID='0
) (
  input logic clk_i,rst_ni,clear_error_i,
  input logic [ADDR_W-1:0] base_addr_i,input logic [1:0] format_i,
  input logic req_valid_i,output logic req_ready_o,input logic [GID_W-1:0] req_gid_i,
  output logic rsp_valid_o,input logic rsp_ready_i,output logic rsp_error_o,
  output logic [1117:0] rsp_data_o,output logic [245:0] rsp_covariance_q20_o,
  output logic rsp_precomputed_o,output logic [1:0] rsp_degree_o,
  output logic busy_o,error_sticky_o,output logic [1:0] error_status_o,
  output logic [ID_W-1:0] m_axi_arid_o,output logic [ADDR_W-1:0] m_axi_araddr_o,
  output logic [7:0] m_axi_arlen_o,output logic [2:0] m_axi_arsize_o,
  output logic [1:0] m_axi_arburst_o,output logic m_axi_arvalid_o,input logic m_axi_arready_i,
  input logic [ID_W-1:0] m_axi_rid_i,input logic [127:0] m_axi_rdata_i,
  input logic [1:0] m_axi_rresp_i,input logic m_axi_rlast_i,m_axi_rvalid_i,
  output logic m_axi_rready_o
);
  typedef enum logic [3:0] {S_IDLE,S_AR,S_R,S_NEXT,S_ERROR_DRAIN,S_DECODE,S_DECODE_WAIT,S_RSP} state_t;
  state_t state_q;
  logic [ADDR_W-1:0] address_q;
  logic [ADDR_W+GID_W:0] end_address;
  logic compressed_q,header_q,error_q;
  logic [3:0] remaining_q,burst_q,index_q,total_q,record_beats_q,planned,header_beats;
  logic [8:0] boundary_beats;
  logic [1151:0] record_q;
  logic header_bad,expected_last,r_error;
  logic last_to_decoder;logic[1151:0]decoder_packet;
  logic dec_s_ready,dec_valid,dec_error,dec_precomputed;
  logic [1117:0] dec_legacy;
  logic [245:0] dec_cov;
  logic [1:0] dec_degree;
  assign end_address={{(GID_W+1){1'b0}},base_addr_i}+(ADDR_W+GID_W+1)'(req_gid_i)*144+143;
  assign boundary_beats=(13'd4096-{1'b0,address_q[11:0]})>>4;
  assign planned=boundary_beats<remaining_q?boundary_beats[3:0]:remaining_q;
  always_comb begin
    header_bad=m_axi_rdata_i[7:0]!=8'hc8||m_axi_rdata_i[9:8]!=2||m_axi_rdata_i[15:14]!=0;
    case(m_axi_rdata_i[12:11])
      0:header_beats=3;
      1:header_beats=4;
      2:header_beats=6;
      3:header_beats=m_axi_rdata_i[13]?9:8;
      default:header_beats=0;
    endcase
    if(m_axi_rdata_i[10])begin
      header_beats=9;
      header_bad=header_bad||m_axi_rdata_i[15:0]!=16'h3ec8;
    end
  end
  assign req_ready_o=state_q==S_IDLE;
  assign busy_o=state_q!=S_IDLE;
  assign error_sticky_o=|error_status_o;
  assign rsp_valid_o=state_q==S_RSP||(state_q==S_DECODE_WAIT&&dec_valid);
  assign rsp_error_o=state_q==S_DECODE_WAIT?dec_error:error_q;
  assign rsp_data_o=state_q==S_DECODE_WAIT?dec_legacy:(error_q?'0:record_q[1117:0]);
  assign rsp_covariance_q20_o=state_q==S_DECODE_WAIT?dec_cov:'0;
  assign rsp_precomputed_o=state_q==S_DECODE_WAIT&&dec_precomputed;
  assign rsp_degree_o=state_q==S_DECODE_WAIT?dec_degree:2'd3;
  assign m_axi_arid_o=AXI_ID;assign m_axi_araddr_o=address_q;
  assign m_axi_arlen_o={4'd0,planned}-1'b1;assign m_axi_arsize_o=4;assign m_axi_arburst_o=1;
  assign m_axi_arvalid_o=state_q==S_AR;
  assign m_axi_rready_o=(state_q==S_R&&(!EARLY_ADVANCE||!compressed_q||header_q||remaining_q!=1||dec_s_ready))||state_q==S_ERROR_DRAIN;
  assign last_to_decoder=EARLY_ADVANCE&&state_q==S_R&&compressed_q&&!header_q&&remaining_q==1&&!r_error;
  always_comb begin decoder_packet=record_q;if(last_to_decoder)decoder_packet[total_q*128+:128]=m_axi_rdata_i;end
  assign expected_last=index_q+1'b1==burst_q;
  assign r_error=m_axi_rid_i!=AXI_ID||m_axi_rresp_i!=0||m_axi_rlast_i!=expected_last;
  t08_attribute_decoder u_decoder(.clk_i(clk_i),.rst_ni(rst_ni),
    .s_valid_i(state_q==S_DECODE||(last_to_decoder&&m_axi_rvalid_i)),.s_ready_o(dec_s_ready),.s_packet_i(decoder_packet),.s_beats_i(record_beats_q),
    .m_valid_o(dec_valid),.m_ready_i(state_q==S_DECODE_WAIT&&rsp_ready_i),.m_error_o(dec_error),
    .m_legacy_o(dec_legacy),.m_covariance_q20_o(dec_cov),.m_precomputed_o(dec_precomputed),.m_degree_o(dec_degree));
  // record_q is payload: initialization on request, no reset fanout.
  always_ff @(posedge clk_i)begin
    if(req_valid_i&&req_ready_o)record_q<='0;
    else if(state_q==S_R&&m_axi_rvalid_i&&m_axi_rready_o&&!r_error)record_q[total_q*128+:128]<=m_axi_rdata_i;
  end
  always_ff @(posedge clk_i or negedge rst_ni)begin
    if(!rst_ni)begin
      state_q<=S_IDLE;address_q<=0;compressed_q<=0;header_q<=0;error_q<=0;
      remaining_q<=0;burst_q<=0;index_q<=0;total_q<=0;record_beats_q<=0;error_status_o<=0;
    end else begin
      if(clear_error_i&&state_q==S_IDLE)error_status_o<=0;
      case(state_q)
        S_IDLE:if(req_valid_i)begin
          compressed_q<=format_i==2;header_q<=format_i==2;error_q<=0;
          remaining_q<=format_i==2?1:9;record_beats_q<=9;total_q<=0;
          address_q<=base_addr_i+ADDR_W'(req_gid_i)*144;
          if(base_addr_i[3:0]!=0||format_i<2||(|end_address[ADDR_W+GID_W:ADDR_W]))begin
            error_q<=1;error_status_o[1]<=1;state_q<=S_RSP;
          end else state_q<=S_AR;
        end
        S_AR:if(m_axi_arready_i)begin
          burst_q<=planned;index_q<=0;address_q<=address_q+ADDR_W'(planned)*16;state_q<=S_R;
        end
        S_R:if(m_axi_rvalid_i&&m_axi_rready_o)begin
          if(r_error)begin
            error_q<=1;error_status_o[0]<=1;
            // A missing RLAST must drain to the actual terminator, not release
            // the channel at the expected beat and leak a response to a new GID.
            state_q<=m_axi_rlast_i?S_RSP:S_ERROR_DRAIN;
          end else if(header_q)begin
            header_q<=0;record_beats_q<=header_beats;remaining_q<=header_beats-1'b1;total_q<=1;
            if(header_bad)begin error_q<=1;error_status_o[1]<=1;state_q<=S_RSP;end
            else state_q<=EARLY_ADVANCE?S_AR:S_NEXT;
          end else begin
            total_q<=total_q+1'b1;index_q<=index_q+1'b1;remaining_q<=remaining_q-1'b1;
            if(expected_last)begin
              if(remaining_q==1)state_q<=compressed_q?(EARLY_ADVANCE?S_DECODE_WAIT:S_DECODE):S_RSP;
              else state_q<=EARLY_ADVANCE?S_AR:S_NEXT;
            end
          end
        end
        S_NEXT:state_q<=S_AR;
        S_ERROR_DRAIN:if(m_axi_rvalid_i&&m_axi_rlast_i)state_q<=S_RSP;
        S_DECODE:if(dec_s_ready)state_q<=S_DECODE_WAIT;
        S_DECODE_WAIT:if(dec_valid)begin
          if(dec_error)error_status_o[1]<=1;
          if(rsp_ready_i)state_q<=S_IDLE;
        end
        S_RSP:if(rsp_ready_i)state_q<=S_IDLE;
        default:state_q<=S_IDLE;
      endcase
    end
  end
`ifndef SYNTHESIS
  initial begin assert(ADDR_W>=32&&GID_W<=32);end
  assert property(@(posedge clk_i)disable iff(!rst_ni)rsp_valid_o&&!rsp_ready_i
    |=>rsp_valid_o&&$stable({rsp_error_o,rsp_data_o,rsp_covariance_q20_o,rsp_precomputed_o,rsp_degree_o}));
  assert property(@(posedge clk_i)disable iff(!rst_ni)m_axi_arvalid_o&&!m_axi_arready_i
    |=>m_axi_arvalid_o&&$stable({m_axi_araddr_o,m_axi_arlen_o,m_axi_arsize_o,m_axi_arburst_o}));
`endif
endmodule
