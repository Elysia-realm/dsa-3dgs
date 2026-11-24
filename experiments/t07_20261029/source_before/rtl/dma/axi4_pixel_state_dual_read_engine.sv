// Two-outstanding single-beat AXI4 reader. Request tag 0/1 maps directly to
// the low AXI ID bit, allowing responses to return out of order. Each ID owns
// an independent response register so downstream backpressure cannot lose the
// other response.
module axi4_pixel_state_dual_read_engine #(
    parameter int unsigned ADDR_W=64,parameter int unsigned DATA_W=128,
    parameter int unsigned ID_W=2,parameter int unsigned PIXEL_W=32
) (
    input logic clk_i,input logic rst_ni,input logic clear_error_i,input logic[ADDR_W-1:0]base_addr_i,
    input logic req_valid_i,output logic req_ready_o,input logic req_tag_i,
    input logic[PIXEL_W-1:0]req_pixel_id_i,
    output logic rsp_valid_o,input logic rsp_ready_i,output logic rsp_tag_o,
    output logic rsp_error_o,output logic[DATA_W-1:0]rsp_data_o,output logic busy_o,
    output logic error_sticky_o,output logic[1:0]error_status_o,
    output logic[ID_W-1:0]m_axi_arid_o,output logic[ADDR_W-1:0]m_axi_araddr_o,
    output logic[7:0]m_axi_arlen_o,output logic[2:0]m_axi_arsize_o,
    output logic[1:0]m_axi_arburst_o,output logic m_axi_arvalid_o,input logic m_axi_arready_i,
    input logic[ID_W-1:0]m_axi_rid_i,input logic[DATA_W-1:0]m_axi_rdata_i,
    input logic[1:0]m_axi_rresp_i,input logic m_axi_rlast_i,input logic m_axi_rvalid_i,
    output logic m_axi_rready_o
);
    localparam int unsigned SIZE_CODE=$clog2(DATA_W/8);
    logic ar_valid_q,ar_tag_q;logic[ADDR_W-1:0]ar_addr_q;
    logic[1:0]outstanding_q,rsp_valid_q,rsp_error_q;
    logic[DATA_W-1:0]rsp_data_q[0:1];logic select_rsp,rid_known,rid_tag;
    logic req_fire,ar_fire,r_fire,rsp_fire;

    assign req_ready_o=!ar_valid_q&&!outstanding_q[req_tag_i]&&!rsp_valid_q[req_tag_i]&&
      base_addr_i[SIZE_CODE-1:0]==0;
    assign req_fire=req_valid_i&&req_ready_o;assign ar_fire=ar_valid_q&&m_axi_arready_i;
    assign m_axi_arvalid_o=ar_valid_q;assign m_axi_arid_o={{(ID_W-1){1'b0}},ar_tag_q};
    assign m_axi_araddr_o=ar_addr_q;assign m_axi_arlen_o=0;
    assign m_axi_arsize_o=SIZE_CODE[2:0];assign m_axi_arburst_o=2'b01;
    assign rid_known=(m_axi_rid_i[ID_W-1:1]=='0)&&outstanding_q[m_axi_rid_i[0]];
    assign rid_tag=m_axi_rid_i[0];
    // Do not admit a newly returned lower-priority tag if it would preempt an
    // already visible response while the downstream interface is stalled.
    assign m_axi_rready_o=m_axi_rvalid_i&&(!rid_known||
      (!rsp_valid_q[rid_tag]&&!(rsp_valid_o&&!rsp_ready_i&&rid_tag<select_rsp)));
    assign r_fire=m_axi_rvalid_i&&m_axi_rready_o;
    assign select_rsp=rsp_valid_q[0]?1'b0:1'b1;
    assign rsp_valid_o=|rsp_valid_q;assign rsp_tag_o=select_rsp;
    assign rsp_error_o=rsp_error_q[select_rsp];assign rsp_data_o=rsp_data_q[select_rsp];
    assign rsp_fire=rsp_valid_o&&rsp_ready_i;
    assign busy_o=ar_valid_q||(|outstanding_q)||(|rsp_valid_q);
    assign error_sticky_o=|error_status_o;

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        ar_valid_q<=0;ar_tag_q<=0;ar_addr_q<=0;outstanding_q<=0;rsp_valid_q<=0;
        rsp_error_q<=0;rsp_data_q[0]<=0;rsp_data_q[1]<=0;error_status_o<=0;
      end else begin
        if(clear_error_i&&!busy_o)error_status_o<=0;
        if(req_valid_i&&base_addr_i[SIZE_CODE-1:0]!=0)error_status_o[1]<=1;
        if(req_fire)begin
          ar_valid_q<=1;ar_tag_q<=req_tag_i;
          ar_addr_q<=base_addr_i+({{(ADDR_W-PIXEL_W){1'b0}},req_pixel_id_i}<<SIZE_CODE);
        end
        if(ar_fire)begin ar_valid_q<=0;outstanding_q[ar_tag_q]<=1;end
        if(rsp_fire)rsp_valid_q[select_rsp]<=0;
        if(r_fire)begin
          if(!rid_known)error_status_o[0]<=1;
          else begin
            outstanding_q[rid_tag]<=0;rsp_valid_q[rid_tag]<=1;
            rsp_data_q[rid_tag]<=m_axi_rdata_i;
            rsp_error_q[rid_tag]<=m_axi_rresp_i!=0||!m_axi_rlast_i;
            if(m_axi_rresp_i!=0||!m_axi_rlast_i)error_status_o[0]<=1;
          end
        end
      end
    end
`ifndef SYNTHESIS
    initial assert(ID_W>=1);
    assert property(@(posedge clk_i)disable iff(!rst_ni)rsp_valid_o&&!rsp_ready_i
      |=>rsp_valid_o&&$stable({rsp_tag_o,rsp_error_o,rsp_data_o}));
    assert property(@(posedge clk_i)disable iff(!rst_ni)ar_valid_q&&!m_axi_arready_i
      |=>ar_valid_q&&$stable({m_axi_arid_o,m_axi_araddr_o}));
    assert property(@(posedge clk_i)disable iff(!rst_ni)req_fire
      |->!outstanding_q[req_tag_i]&&!rsp_valid_q[req_tag_i]);
    assert property(@(posedge clk_i)disable iff(!rst_ni)r_fire&&rid_known
      |=>rsp_valid_q[$past(rid_tag)]||$past(rsp_ready_i));
    assert property(@(posedge clk_i)disable iff(!rst_ni)r_fire&&!rid_known
      |=>error_status_o[0]);
`endif
endmodule
