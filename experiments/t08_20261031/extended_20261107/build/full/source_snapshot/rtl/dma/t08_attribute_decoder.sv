// Candidate decoder only; not yet present in system_top_sources.f.
// Complete packet input, with externally verified AXI framing/length.
module t08_attribute_decoder (
  input logic clk_i,rst_ni,
  input logic s_valid_i,output logic s_ready_o,
  input logic [1151:0] s_packet_i,input logic [3:0] s_beats_i,
  output logic m_valid_o,input logic m_ready_i,output logic m_error_o,
  output logic [1117:0] m_legacy_o,
  output logic [245:0] m_covariance_q20_o,
  output logic m_precomputed_o,output logic [1:0] m_degree_o
);
  localparam logic [15:0] RAW_HEADER=16'h3dc8;
  logic [1117:0] legacy;
  logic [245:0] covariance;
  logic error,precomputed;
  logic [1:0] degree;
  integer kept,width,bits,beats,offset;
  always_comb begin
    legacy='0;covariance='0;offset=0;
    degree=s_packet_i[12:11];precomputed=!s_packet_i[10];
    kept=(int'(degree)+1)*(int'(degree)+1);
    width=s_packet_i[13]?18:16;
    bits=precomputed?254+3*kept*width:1134;
    beats=(bits+127)/128;
    error=s_packet_i[7:0]!=8'hc8||s_packet_i[9:8]!=2'd1||s_packet_i[15:14]!=0||int'(s_beats_i)!=beats;
    if(!precomputed)begin
      error=error||(s_packet_i[15:0]!=RAW_HEADER);
      legacy=s_packet_i[16+:1118];
    end else begin
      legacy[1037+:81]=s_packet_i[16+:81];
      legacy[864+:13]=s_packet_i[97+:13];
      for(integer i=0;i<6;i=i+1)
        covariance[(5-i)*41+:41]={{17{s_packet_i[110+i*24+23]}},s_packet_i[110+i*24+:24]};
      for(integer c=0;c<3;c=c+1)begin
        for(integer k=0;k<16;k=k+1)begin
          offset=254+(c*kept+k)*width;
          if(k<kept)begin
            if(s_packet_i[13])legacy[(c*16+k)*18+:18]=s_packet_i[offset+:18];
            else legacy[(c*16+k)*18+:18]={{2{s_packet_i[offset+15]}},s_packet_i[offset+:16]};
          end
        end
      end
    end
    if(error)begin legacy='0;covariance='0;precomputed=0;degree=0;end
  end
  assign s_ready_o=!m_valid_o||m_ready_i;
  // Payload is reset-free and guarded by valid, preserving the reset-load budget.
  always_ff @(posedge clk_i or negedge rst_ni)begin
    if(!rst_ni)m_valid_o<=0;
    else if(s_ready_o)m_valid_o<=s_valid_i;
  end
  always_ff @(posedge clk_i)if(s_valid_i&&s_ready_o)begin
    m_error_o<=error;m_legacy_o<=legacy;m_covariance_q20_o<=covariance;
    m_precomputed_o<=precomputed;m_degree_o<=degree;
  end
endmodule
