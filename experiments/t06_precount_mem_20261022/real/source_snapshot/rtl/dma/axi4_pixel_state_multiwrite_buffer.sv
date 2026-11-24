// Ordered multi-outstanding AXI4 pixel-state writer.
//
// All transactions use one AXI ID. AXI4 therefore returns B responses in
// issue order for that ID. An entry remains valid from renderer acceptance
// until its B response is consumed, so the full-tag hazard CAM covers queued,
// partially-issued and response-pending writes. AW and W handshake
// independently, but the next transaction is not selected until both channels
// of the current transaction have completed; this preserves address/data
// association because AXI4 W carries no transaction ID.
module axi4_pixel_state_multiwrite_buffer #(
    parameter int unsigned ADDR_W=64,parameter int unsigned DATA_W=128,
    parameter int unsigned ID_W=2,parameter logic[ID_W-1:0]AXI_ID='0,
    parameter int unsigned DEPTH=8,
    parameter bit ENABLE_LOOKUP_FORWARD=1'b1,
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
    input logic[31:0]lookup_pixel_id_i,output logic lookup_hit_o,
    output logic[DATA_W-1:0]lookup_data_o,
    output logic busy_o,output logic error_sticky_o,output logic[1:0]error_status_o,
    output logic[COUNT_W-1:0]occupancy_o,outstanding_o,peak_outstanding_o,
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
    logic[31:0]pixel_mem[0:DEPTH-1];
    logic[ADDR_W-1:0]addr_mem[0:DEPTH-1];
    logic[DATA_W-1:0]data_mem[0:DEPTH-1];
    logic[DEPTH-1:0]valid_q;
    logic[PTR_W-1:0]response_q,issue_q,write_q;
    logic aw_done_q,w_done_q;
    logic input_fire,enqueue,config_error,issue_valid,aw_fire,w_fire,issue_fire,b_fire;
    logic[DATA_W-1:0]input_data;
    logic[COUNT_W-1:0]next_outstanding;
    integer lookup_offset,lookup_index;

    always_comb begin
      input_data='0;
      input_data[12:0]=s_r_q12_i;input_data[25:13]=s_g_q12_i;
      input_data[38:26]=s_b_q12_i;input_data[54:39]=s_t_q16_i;
      input_data[70:55]=s_epoch_id_i;input_data[83:71]=s_alpha_q12_i;
      input_data[84]=s_pass_alpha_i;input_data[85]=s_newly_terminated_i;
      input_data[117:86]=s_gid_i;
    end

    assign config_error=base_addr_i[SIZE_CODE-1:0]!=0;
    // A same-cycle ordered B retirement frees one entry, so a full queue may
    // accept its replacement without inserting a renderer bubble.
    assign s_ready_o=occupancy_o<DEPTH||b_fire;
    assign input_fire=s_valid_i&&s_ready_o;
    assign enqueue=input_fire&&!config_error;
    assign issue_valid=occupancy_o>outstanding_o;
    assign m_axi_awid_o=AXI_ID;assign m_axi_awaddr_o=addr_mem[issue_q];
    assign m_axi_awlen_o=0;assign m_axi_awsize_o=SIZE_CODE[2:0];assign m_axi_awburst_o=2'b01;
    assign m_axi_awvalid_o=issue_valid&&!aw_done_q;
    assign m_axi_wdata_o=data_mem[issue_q];assign m_axi_wstrb_o={DATA_W/8{1'b1}};
    assign m_axi_wlast_o=1;assign m_axi_wvalid_o=issue_valid&&!w_done_q;
    assign aw_fire=m_axi_awvalid_o&&m_axi_awready_i;
    assign w_fire=m_axi_wvalid_o&&m_axi_wready_i;
    assign issue_fire=issue_valid&&(aw_done_q||aw_fire)&&(w_done_q||w_fire);
    assign m_axi_bready_o=outstanding_o!=0;
    assign b_fire=m_axi_bvalid_i&&m_axi_bready_o;
    assign busy_o=occupancy_o!=0;
    assign error_sticky_o=|error_status_o;
    assign next_outstanding=outstanding_o+issue_fire-b_fire;

    // Search in architectural queue order and deliberately let every newer
    // match replace the previous result.  The returned record is therefore
    // the youngest ordered state for this pixel, including entries whose AW/W
    // have issued but whose B response has not retired yet.
    always_comb begin
      hazard_o=1'b0;lookup_hit_o=1'b0;lookup_data_o='0;lookup_index=0;
      for(lookup_offset=0;lookup_offset<DEPTH;lookup_offset=lookup_offset+1)begin
        lookup_index=response_q+lookup_offset;
        if(lookup_index>=DEPTH)lookup_index=lookup_index-DEPTH;
        if(valid_q[lookup_index])begin
          if(pixel_mem[lookup_index]==hazard_pixel_id_i)hazard_o=1'b1;
          if(ENABLE_LOOKUP_FORWARD&&pixel_mem[lookup_index]==lookup_pixel_id_i)begin
            lookup_hit_o=1'b1;lookup_data_o=data_mem[lookup_index];
          end
        end
      end
    end

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        response_q<='0;issue_q<='0;write_q<='0;occupancy_o<='0;outstanding_o<='0;
        peak_outstanding_o<='0;valid_q<='0;aw_done_q<=0;w_done_q<=0;error_status_o<=0;
      end else begin
        if(clear_error_i&&!busy_o)begin error_status_o<=0;peak_outstanding_o<=0;end
        if(m_axi_bvalid_i&&outstanding_o==0)error_status_o[0]<=1;
        if(input_fire&&config_error)error_status_o[1]<=1;
        if(b_fire)begin
          if(m_axi_bid_i!=AXI_ID||m_axi_bresp_i!=2'b00)error_status_o[0]<=1;
          valid_q[response_q]<=0;
          response_q<=response_q==DEPTH-1?'0:response_q+1'b1;
        end
        // Enqueue follows retirement deliberately: when a full ring retires
        // and replaces the same physical slot, the new entry remains valid.
        if(enqueue)begin
          pixel_mem[write_q]<=s_pixel_id_i;
          addr_mem[write_q]<=base_addr_i+({{(ADDR_W-32){1'b0}},s_pixel_id_i}<<SIZE_CODE);
          data_mem[write_q]<=input_data;valid_q[write_q]<=1;
          write_q<=write_q==DEPTH-1?'0:write_q+1'b1;
        end
        if(aw_fire)aw_done_q<=1;
        if(w_fire)w_done_q<=1;
        if(issue_fire)begin
          issue_q<=issue_q==DEPTH-1?'0:issue_q+1'b1;
          aw_done_q<=0;w_done_q<=0;
        end
        case({enqueue,b_fire})
          2'b10:occupancy_o<=occupancy_o+1'b1;
          2'b01:occupancy_o<=occupancy_o-1'b1;
          default:occupancy_o<=occupancy_o;
        endcase
        outstanding_o<=next_outstanding;
        if(next_outstanding>peak_outstanding_o)peak_outstanding_o<=next_outstanding;
      end
    end
`ifndef SYNTHESIS
    initial begin assert(DATA_W==128);assert(DEPTH>=2);end
    assert property(@(posedge clk_i)disable iff(!rst_ni)outstanding_o<=occupancy_o);
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_axi_awvalid_o&&!m_axi_awready_i
      |=>m_axi_awvalid_o&&$stable(m_axi_awaddr_o));
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_axi_wvalid_o&&!m_axi_wready_i
      |=>m_axi_wvalid_o&&$stable({m_axi_wdata_o,m_axi_wstrb_o,m_axi_wlast_o}));
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_axi_bvalid_i&&outstanding_o==0
      |->!m_axi_bready_o);
`endif
endmodule
