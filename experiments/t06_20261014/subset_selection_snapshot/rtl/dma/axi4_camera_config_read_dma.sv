// AXI4 reader for the versioned camera descriptor used by gs_accel_system_top.
// The descriptor contains 28 little-indexed 64-bit words (14 AXI beats):
//   0..8   world-to-camera rotation, signed Q1.20 in 22 bits
//   9..11  translation, signed Q10.16 in 27 bits
//   12..14 camera position, signed Q10.16 in 27 bits
//   15..18 fx, fy, cx, cy, signed Q16.16 in 33 bits
//   19..20 near, far, signed Q10.16 in 27 bits
//   21     covariance regularizer, unsigned Q*.8
//   22..24 depth pivots, signed Q10.16 in 27 bits
//   25..26 image width, height
//   27     [63:32] descriptor tag/version, [31:0] Gaussian count
// Word 2*n is carried in AXI beat n[63:0], word 2*n+1 in [127:64].
module axi4_camera_config_read_dma #(
    parameter int unsigned ADDR_W=64,
    parameter int unsigned DATA_W=128,
    parameter int unsigned ID_W=2,
    parameter int unsigned ROT_W=22,
    parameter int unsigned COORD_W=27,
    parameter int unsigned COV2_W=35,
    parameter logic[ID_W-1:0] AXI_ID='0,
    parameter logic[31:0] DESCRIPTOR_TAG=32'h47534301
) (
    input  logic clk_i,input logic rst_ni,
    input  logic start_i,input logic clear_error_i,
    input  logic[ADDR_W-1:0]base_addr_i,
    output logic busy_o,output logic done_pulse_o,
    output logic result_valid_o,input logic result_ready_i,output logic result_error_o,
    output logic[1:0]error_status_o, // bit0 AXI/protocol, bit1 format/configuration

    output logic signed[ROT_W-1:0]cfg_r00_q20_o,cfg_r01_q20_o,cfg_r02_q20_o,
    output logic signed[ROT_W-1:0]cfg_r10_q20_o,cfg_r11_q20_o,cfg_r12_q20_o,
    output logic signed[ROT_W-1:0]cfg_r20_q20_o,cfg_r21_q20_o,cfg_r22_q20_o,
    output logic signed[COORD_W-1:0]cfg_tx_q16_o,cfg_ty_q16_o,cfg_tz_q16_o,
    output logic signed[COORD_W-1:0]cfg_camera_x_q16_o,cfg_camera_y_q16_o,cfg_camera_z_q16_o,
    output logic signed[32:0]cfg_fx_q16_o,cfg_fy_q16_o,cfg_cx_q16_o,cfg_cy_q16_o,
    output logic signed[COORD_W-1:0]cfg_near_q16_o,cfg_far_q16_o,
    output logic[COV2_W-1:0]cfg_regularizer_q8_o,
    output logic signed[COORD_W-1:0]cfg_depth_pivot0_q16_o,
    output logic signed[COORD_W-1:0]cfg_depth_pivot1_q16_o,
    output logic signed[COORD_W-1:0]cfg_depth_pivot2_q16_o,
    output logic[15:0]image_width_o,image_height_o,
    output logic[31:0]gaussian_count_o,

    output logic[ID_W-1:0]m_axi_arid_o,output logic[ADDR_W-1:0]m_axi_araddr_o,
    output logic[7:0]m_axi_arlen_o,output logic[2:0]m_axi_arsize_o,
    output logic[1:0]m_axi_arburst_o,output logic m_axi_arvalid_o,
    input logic m_axi_arready_i,input logic[ID_W-1:0]m_axi_rid_i,
    input logic[DATA_W-1:0]m_axi_rdata_i,input logic[1:0]m_axi_rresp_i,
    input logic m_axi_rlast_i,input logic m_axi_rvalid_i,output logic m_axi_rready_o
);
    localparam int unsigned BEATS=14;
    localparam int unsigned RECORD_BYTES=DATA_W/8;
    localparam int unsigned SIZE_CODE=$clog2(RECORD_BYTES);
    typedef enum logic[2:0]{S_IDLE,S_ISSUE,S_DATA,S_BETWEEN,S_VALIDATE,S_ERROR_DRAIN,S_RESULT}state_t;
    state_t state_q;
    logic[63:0]word_q[0:27];
    logic[ADDR_W-1:0]next_addr_q;
    logic[4:0]remaining_q,global_beat_q;
    logic[4:0]burst_beats_q,beat_index_q,planned_beats;
    logic[12:0]bytes_to_boundary;
    logic[8:0]boundary_beats;
    logic r_accept,expected_last,r_error,format_error;

    always_comb begin
      bytes_to_boundary=13'd4096-{1'b0,next_addr_q[11:0]};
      boundary_beats=bytes_to_boundary>>SIZE_CODE;
      planned_beats=remaining_q;
      if(boundary_beats<planned_beats)planned_beats=boundary_beats[4:0];
    end

    assign busy_o=state_q!=S_IDLE;
    assign result_valid_o=state_q==S_RESULT;
    assign result_error_o=|error_status_o;
    assign m_axi_arid_o=AXI_ID;
    assign m_axi_araddr_o=next_addr_q;
    assign m_axi_arlen_o=planned_beats-1'b1;
    assign m_axi_arsize_o=SIZE_CODE[2:0];
    assign m_axi_arburst_o=2'b01;
    assign m_axi_arvalid_o=state_q==S_ISSUE;
    assign m_axi_rready_o=state_q==S_DATA||state_q==S_ERROR_DRAIN;
    assign r_accept=m_axi_rvalid_i&&m_axi_rready_o;
    assign expected_last=beat_index_q+1'b1==burst_beats_q;
    assign r_error=(m_axi_rid_i!=AXI_ID)||(m_axi_rresp_i!=2'b00)||(m_axi_rlast_i!=expected_last);

    assign cfg_r00_q20_o=word_q[0][ROT_W-1:0];
    assign cfg_r01_q20_o=word_q[1][ROT_W-1:0];
    assign cfg_r02_q20_o=word_q[2][ROT_W-1:0];
    assign cfg_r10_q20_o=word_q[3][ROT_W-1:0];
    assign cfg_r11_q20_o=word_q[4][ROT_W-1:0];
    assign cfg_r12_q20_o=word_q[5][ROT_W-1:0];
    assign cfg_r20_q20_o=word_q[6][ROT_W-1:0];
    assign cfg_r21_q20_o=word_q[7][ROT_W-1:0];
    assign cfg_r22_q20_o=word_q[8][ROT_W-1:0];
    assign cfg_tx_q16_o=word_q[9][COORD_W-1:0];
    assign cfg_ty_q16_o=word_q[10][COORD_W-1:0];
    assign cfg_tz_q16_o=word_q[11][COORD_W-1:0];
    assign cfg_camera_x_q16_o=word_q[12][COORD_W-1:0];
    assign cfg_camera_y_q16_o=word_q[13][COORD_W-1:0];
    assign cfg_camera_z_q16_o=word_q[14][COORD_W-1:0];
    assign cfg_fx_q16_o=word_q[15][32:0];
    assign cfg_fy_q16_o=word_q[16][32:0];
    assign cfg_cx_q16_o=word_q[17][32:0];
    assign cfg_cy_q16_o=word_q[18][32:0];
    assign cfg_near_q16_o=word_q[19][COORD_W-1:0];
    assign cfg_far_q16_o=word_q[20][COORD_W-1:0];
    assign cfg_regularizer_q8_o=word_q[21][COV2_W-1:0];
    assign cfg_depth_pivot0_q16_o=word_q[22][COORD_W-1:0];
    assign cfg_depth_pivot1_q16_o=word_q[23][COORD_W-1:0];
    assign cfg_depth_pivot2_q16_o=word_q[24][COORD_W-1:0];
    assign image_width_o=word_q[25][15:0];
    assign image_height_o=word_q[26][15:0];
    assign gaussian_count_o=word_q[27][31:0];
    assign format_error=word_q[27][63:32]!=DESCRIPTOR_TAG||
      word_q[25][63:16]!=0||word_q[26][63:16]!=0||
      image_width_o==0||image_height_o==0||
      $signed(cfg_near_q16_o)>=$signed(cfg_far_q16_o)||
      $signed(cfg_depth_pivot0_q16_o)>$signed(cfg_depth_pivot1_q16_o)||
      $signed(cfg_depth_pivot1_q16_o)>$signed(cfg_depth_pivot2_q16_o);

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        state_q<=S_IDLE;next_addr_q<='0;remaining_q<='0;global_beat_q<='0;
        burst_beats_q<='0;beat_index_q<='0;done_pulse_o<=0;error_status_o<=0;
        for(integer i=0;i<28;i=i+1)word_q[i]<='0;
      end else begin
        done_pulse_o<=0;
        if(clear_error_i&&state_q==S_IDLE)error_status_o<=0;
        case(state_q)
          S_IDLE:if(start_i)begin
            error_status_o<=0;next_addr_q<=base_addr_i;remaining_q<=BEATS;global_beat_q<=0;
            if(base_addr_i[SIZE_CODE-1:0]!=0)begin error_status_o[1]<=1;state_q<=S_RESULT;end
            else state_q<=S_ISSUE;
          end
          S_ISSUE:if(m_axi_arvalid_o&&m_axi_arready_i)begin
            burst_beats_q<=planned_beats;beat_index_q<=0;
            next_addr_q<=next_addr_q+planned_beats*RECORD_BYTES;state_q<=S_DATA;
          end
          S_DATA:if(r_accept)begin
            if(r_error)begin
              error_status_o[0]<=1;
              if(m_axi_rlast_i||expected_last)state_q<=S_RESULT;else state_q<=S_ERROR_DRAIN;
            end else begin
              word_q[2*global_beat_q]<=m_axi_rdata_i[63:0];
              word_q[2*global_beat_q+1]<=m_axi_rdata_i[127:64];
              remaining_q<=remaining_q-1'b1;global_beat_q<=global_beat_q+1'b1;
              beat_index_q<=beat_index_q+1'b1;
              if(expected_last)state_q<=remaining_q==1?S_VALIDATE:S_BETWEEN;
            end
          end
          S_BETWEEN:state_q<=S_ISSUE;
          S_VALIDATE:begin
            if(format_error)error_status_o[1]<=1;
            state_q<=S_RESULT;
          end
          S_ERROR_DRAIN:if(r_accept&&m_axi_rlast_i)state_q<=S_RESULT;
          S_RESULT:if(result_ready_i)begin state_q<=S_IDLE;done_pulse_o<=1;end
          default:state_q<=S_IDLE;
        endcase
      end
    end

`ifndef SYNTHESIS
    initial begin
      assert(DATA_W==128);assert(ROT_W<=64);assert(COORD_W<=64);assert(COV2_W<=64);
    end
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      m_axi_arvalid_o&&!m_axi_arready_i|=>$stable({m_axi_araddr_o,m_axi_arlen_o}));
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      result_valid_o&&!result_ready_i|=>$stable({error_status_o,word_q[27]}));
`endif
endmodule
