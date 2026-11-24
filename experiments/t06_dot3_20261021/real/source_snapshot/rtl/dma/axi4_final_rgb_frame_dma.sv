// Final-frame DMA for the production RGB output contract.
//
// Input pixels are the 16-byte renderer state records at state_base_addr_i.
// Output is RGB888 at rgb_base_addr_i, with every row padded with zeroes to a
// 16-byte boundary.  Production places the scratch state immediately after
// the padded RGB frame, so a completed frame never destroys the state epoch
// tags needed to reject stale records on the following frame.
module axi4_final_rgb_frame_dma #(
    parameter int unsigned ADDR_W=64,
    parameter int unsigned DATA_W=128,
    parameter int unsigned ID_W=2,
    parameter logic[ID_W-1:0] AXI_ID='0,
    parameter logic[12:0] BG_R_Q12=13'd0,
    parameter logic[12:0] BG_G_Q12=13'd0,
    parameter logic[12:0] BG_B_Q12=13'd0,
    parameter int unsigned CHUNK_PIXELS=80
) (
    input logic clk_i,input logic rst_ni,input logic start_i,input logic clear_error_i,
    input logic[ADDR_W-1:0]state_base_addr_i,rgb_base_addr_i,
    input logic[15:0]width_i,height_i,
    input logic[15:0]epoch_id_i,
    output logic busy_o,output logic done_pulse_o,output logic error_sticky_o,
    output logic[2:0]error_status_o,output logic[31:0]row_stride_bytes_o,

    output logic[ID_W-1:0]m_axi_arid_o,output logic[ADDR_W-1:0]m_axi_araddr_o,
    output logic[7:0]m_axi_arlen_o,output logic[2:0]m_axi_arsize_o,
    output logic[1:0]m_axi_arburst_o,output logic m_axi_arvalid_o,
    input logic m_axi_arready_i,input logic[ID_W-1:0]m_axi_rid_i,
    input logic[DATA_W-1:0]m_axi_rdata_i,input logic[1:0]m_axi_rresp_i,
    input logic m_axi_rlast_i,m_axi_rvalid_i,output logic m_axi_rready_o,

    output logic[ID_W-1:0]m_axi_awid_o,output logic[ADDR_W-1:0]m_axi_awaddr_o,
    output logic[7:0]m_axi_awlen_o,output logic[2:0]m_axi_awsize_o,
    output logic[1:0]m_axi_awburst_o,output logic m_axi_awvalid_o,
    input logic m_axi_awready_i,output logic[DATA_W-1:0]m_axi_wdata_o,
    output logic[DATA_W/8-1:0]m_axi_wstrb_o,output logic m_axi_wlast_o,
    output logic m_axi_wvalid_o,input logic m_axi_wready_i,
    input logic[ID_W-1:0]m_axi_bid_i,input logic[1:0]m_axi_bresp_i,
    input logic m_axi_bvalid_i,output logic m_axi_bready_o
);
    localparam int unsigned BEAT_BYTES=DATA_W/8;
    localparam int unsigned SIZE_CODE=$clog2(BEAT_BYTES);
    localparam int unsigned CHUNK_BYTES=CHUNK_PIXELS*3;
    localparam int unsigned CHUNK_BEATS=(CHUNK_BYTES+BEAT_BYTES-1)/BEAT_BYTES;
    localparam int unsigned PIX_COUNT_W=$clog2(CHUNK_PIXELS+1);
    localparam int unsigned BEAT_COUNT_W=$clog2(CHUNK_BEATS+1);
    typedef enum logic[3:0]{S_IDLE,S_CHUNK_INIT,S_READ_AR,S_READ_R,
      S_WRITE_AW,S_WRITE_W,S_WRITE_B,S_DONE}state_t;
    state_t state_q;
    logic[7:0]byte_mem[0:CHUNK_BEATS*BEAT_BYTES-1];
    logic[15:0]row_q,row_pixel_q;
    logic[PIX_COUNT_W-1:0]chunk_pixels_q,read_pixel_q;
    logic[BEAT_COUNT_W-1:0]chunk_beats_q,segment_start_q,segment_beats_q,write_beat_q;
    logic[31:0]stride_q;
    logic[ADDR_W-1:0]read_addr,write_addr;
    logic[31:0]global_pixel;
    logic[8:0]page_beats;
    integer lane;

    function automatic logic[12:0]composite_q12(
      input logic[12:0]color,input logic[15:0]transmittance,input logic[12:0]background);
      logic[28:0]product;logic[13:0]sum;logic[12:0]background_part;
      begin
        product=transmittance*background;
        background_part=(transmittance==16'hffff)?background:(product+29'd32768)>>16;
        sum={1'b0,color}+{1'b0,background_part};
        composite_q12=sum>14'd4096 ? 13'd4096 : sum[12:0];
      end
    endfunction

    function automatic logic[7:0]quantize_q12(input logic[12:0]value);
      logic[20:0]scaled;
      begin
        if(value>=13'd4096)quantize_q12=8'hff;
        else begin scaled=value*8'd255+21'd2048;quantize_q12=scaled>>12;end
      end
    endfunction

    assign busy_o=state_q!=S_IDLE;
    assign error_sticky_o=|error_status_o;
    assign row_stride_bytes_o=stride_q;
    assign global_pixel=row_q*width_i+row_pixel_q+read_pixel_q;
    assign read_addr=state_base_addr_i+({{(ADDR_W-32){1'b0}},global_pixel}<<SIZE_CODE);
    assign write_addr=rgb_base_addr_i+row_q*stride_q+row_pixel_q*3+
      segment_start_q*BEAT_BYTES;
    assign page_beats=(13'd4096-{1'b0,write_addr[11:0]})>>SIZE_CODE;

    assign m_axi_arid_o=AXI_ID;assign m_axi_araddr_o=read_addr;
    assign m_axi_arlen_o=0;assign m_axi_arsize_o=SIZE_CODE[2:0];
    assign m_axi_arburst_o=2'b01;assign m_axi_arvalid_o=state_q==S_READ_AR;
    assign m_axi_rready_o=state_q==S_READ_R;
    assign m_axi_awid_o=AXI_ID;assign m_axi_awaddr_o=write_addr;
    assign m_axi_awlen_o=segment_beats_q-1'b1;assign m_axi_awsize_o=SIZE_CODE[2:0];
    assign m_axi_awburst_o=2'b01;assign m_axi_awvalid_o=state_q==S_WRITE_AW;
    assign m_axi_wstrb_o={DATA_W/8{1'b1}};
    assign m_axi_wlast_o=write_beat_q+1'b1==segment_beats_q;
    assign m_axi_wvalid_o=state_q==S_WRITE_W;assign m_axi_bready_o=state_q==S_WRITE_B;

    always_comb begin
      m_axi_wdata_o='0;
      for(lane=0;lane<BEAT_BYTES;lane=lane+1)
        m_axi_wdata_o[lane*8+:8]=byte_mem[(segment_start_q+write_beat_q)*BEAT_BYTES+lane];
    end

    always_ff@(posedge clk_i or negedge rst_ni)begin:frame_dma_state
      logic[12:0]final_r,final_g,final_b;
      logic state_valid;
      integer clear_index;
      if(!rst_ni)begin
        state_q<=S_IDLE;row_q<=0;row_pixel_q<=0;chunk_pixels_q<=0;read_pixel_q<=0;
        chunk_beats_q<=0;segment_start_q<=0;segment_beats_q<=0;write_beat_q<=0;
        stride_q<=0;done_pulse_o<=0;error_status_o<=0;
      end else begin
        done_pulse_o<=0;
        if(clear_error_i&&state_q==S_IDLE)error_status_o<=0;
        case(state_q)
          S_IDLE:if(start_i)begin
            error_status_o<=0;row_q<=0;row_pixel_q<=0;
            stride_q<=(({16'b0,width_i}*32'd3)+32'd15)&32'hfffffff0;
            if(width_i==0||height_i==0||state_base_addr_i[SIZE_CODE-1:0]!=0||
              rgb_base_addr_i[SIZE_CODE-1:0]!=0)begin
              error_status_o[0]<=1;state_q<=S_DONE;
            end else state_q<=S_CHUNK_INIT;
          end
          S_CHUNK_INIT:begin
            for(clear_index=0;clear_index<CHUNK_BEATS*BEAT_BYTES;clear_index=clear_index+1)
              byte_mem[clear_index]<=0;
            if(width_i-row_pixel_q>CHUNK_PIXELS)
              chunk_pixels_q<=CHUNK_PIXELS[PIX_COUNT_W-1:0];
            else chunk_pixels_q<=width_i-row_pixel_q;
            if(width_i-row_pixel_q>CHUNK_PIXELS)
              chunk_beats_q<=CHUNK_BEATS[BEAT_COUNT_W-1:0];
            else chunk_beats_q<=(((width_i-row_pixel_q)*3)+15)>>4;
            read_pixel_q<=0;segment_start_q<=0;state_q<=S_READ_AR;
          end
          S_READ_AR:if(m_axi_arready_i)state_q<=S_READ_R;
          S_READ_R:if(m_axi_rvalid_i)begin
            state_valid=m_axi_rid_i==AXI_ID&&m_axi_rresp_i==2'b00&&m_axi_rlast_i&&
              m_axi_rdata_i[70:55]==epoch_id_i;
            if(m_axi_rid_i!=AXI_ID||m_axi_rresp_i!=2'b00||!m_axi_rlast_i)
              error_status_o[1]<=1;
            final_r=state_valid?composite_q12(m_axi_rdata_i[12:0],m_axi_rdata_i[54:39],BG_R_Q12):BG_R_Q12;
            final_g=state_valid?composite_q12(m_axi_rdata_i[25:13],m_axi_rdata_i[54:39],BG_G_Q12):BG_G_Q12;
            final_b=state_valid?composite_q12(m_axi_rdata_i[38:26],m_axi_rdata_i[54:39],BG_B_Q12):BG_B_Q12;
            byte_mem[read_pixel_q*3]<=quantize_q12(final_r);
            byte_mem[read_pixel_q*3+1]<=quantize_q12(final_g);
            byte_mem[read_pixel_q*3+2]<=quantize_q12(final_b);
            if(read_pixel_q+1'b1==chunk_pixels_q)begin
              segment_start_q<=0;
              segment_beats_q<=page_beats<chunk_beats_q?page_beats[BEAT_COUNT_W-1:0]:chunk_beats_q;
              state_q<=S_WRITE_AW;
            end else begin read_pixel_q<=read_pixel_q+1'b1;state_q<=S_READ_AR;end
          end
          S_WRITE_AW:if(m_axi_awready_i)begin write_beat_q<=0;state_q<=S_WRITE_W;end
          S_WRITE_W:if(m_axi_wready_i)begin
            if(write_beat_q+1'b1==segment_beats_q)state_q<=S_WRITE_B;
            else write_beat_q<=write_beat_q+1'b1;
          end
          S_WRITE_B:if(m_axi_bvalid_i)begin
            if(m_axi_bid_i!=AXI_ID||m_axi_bresp_i!=2'b00)error_status_o[2]<=1;
            if(segment_start_q+segment_beats_q<chunk_beats_q)begin
              segment_start_q<=segment_start_q+segment_beats_q;
              // The first segment ended exactly at a 4 KiB boundary.
              segment_beats_q<=chunk_beats_q-(segment_start_q+segment_beats_q);
              state_q<=S_WRITE_AW;
            end else if(row_pixel_q+chunk_pixels_q<width_i)begin
              row_pixel_q<=row_pixel_q+chunk_pixels_q;state_q<=S_CHUNK_INIT;
            end else if(row_q+1'b1<height_i)begin
              row_q<=row_q+1'b1;row_pixel_q<=0;state_q<=S_CHUNK_INIT;
            end else state_q<=S_DONE;
          end
          S_DONE:begin done_pulse_o<=1;state_q<=S_IDLE;end
          default:state_q<=S_IDLE;
        endcase
      end
    end

`ifndef SYNTHESIS
    initial begin assert(DATA_W==128);assert(CHUNK_PIXELS==80);end
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      m_axi_awvalid_o|->({1'b0,m_axi_awaddr_o[11:0]}+(({5'b0,m_axi_awlen_o}+1'b1)<<SIZE_CODE)<=13'd4096));
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      m_axi_awvalid_o&&!m_axi_awready_i|=>m_axi_awvalid_o&&$stable({m_axi_awaddr_o,m_axi_awlen_o}));
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      m_axi_wvalid_o&&!m_axi_wready_i|=>m_axi_wvalid_o&&$stable({m_axi_wdata_o,m_axi_wlast_o}));
`endif
endmodule
