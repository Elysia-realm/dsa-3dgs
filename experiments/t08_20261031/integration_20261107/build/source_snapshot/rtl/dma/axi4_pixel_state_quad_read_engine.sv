// Four-outstanding single-beat AXI4 reader for the experimental 4+4 state
// path. Request tag maps directly to ARID[1:0]. Four independent response
// registers decouple AXI RID return order from ordered-window consumption.
module axi4_pixel_state_quad_read_engine #(
    parameter int unsigned ADDR_W=64, parameter int unsigned DATA_W=128,
    parameter int unsigned ID_W=2, parameter int unsigned PIXEL_W=32
) (
    input logic clk_i,input logic rst_ni,input logic clear_error_i,
    input logic[ADDR_W-1:0]base_addr_i,
    input logic req_valid_i,output logic req_ready_o,input logic[1:0]req_tag_i,
    input logic[PIXEL_W-1:0]req_pixel_id_i,
    output logic rsp_valid_o,input logic rsp_ready_i,output logic[1:0]rsp_tag_o,
    output logic rsp_error_o,output logic[DATA_W-1:0]rsp_data_o,output logic busy_o,
    output logic error_sticky_o,output logic[1:0]error_status_o,
    output logic[ID_W-1:0]m_axi_arid_o,output logic[ADDR_W-1:0]m_axi_araddr_o,
    output logic[7:0]m_axi_arlen_o,output logic[2:0]m_axi_arsize_o,
    output logic[1:0]m_axi_arburst_o,output logic m_axi_arvalid_o,
    input logic m_axi_arready_i,input logic[ID_W-1:0]m_axi_rid_i,
    input logic[DATA_W-1:0]m_axi_rdata_i,input logic[1:0]m_axi_rresp_i,
    input logic m_axi_rlast_i,input logic m_axi_rvalid_i,output logic m_axi_rready_o
);
    localparam int unsigned SIZE_CODE=$clog2(DATA_W/8);
    logic ar_valid_q;
    logic[1:0]ar_tag_q;
    logic[ADDR_W-1:0]ar_addr_q;
    logic[3:0]outstanding_q,rsp_valid_q,rsp_error_q;
    logic[DATA_W-1:0]rsp_data_q[0:3];
    logic[1:0]select_rsp,rid_tag;
    logic rid_known;
    logic req_fire,ar_fire,r_fire,rsp_fire;

    assign req_ready_o=!ar_valid_q&&!outstanding_q[req_tag_i]&&
      !rsp_valid_q[req_tag_i]&&base_addr_i[SIZE_CODE-1:0]=='0;
    assign req_fire=req_valid_i&&req_ready_o;
    assign ar_fire=ar_valid_q&&m_axi_arready_i;
    assign m_axi_arvalid_o=ar_valid_q;
    assign m_axi_arid_o={{(ID_W-2){1'b0}},ar_tag_q};
    assign m_axi_araddr_o=ar_addr_q;
    assign m_axi_arlen_o=8'd0;
    assign m_axi_arsize_o=SIZE_CODE[2:0];
    assign m_axi_arburst_o=2'b01;

    assign rid_tag=m_axi_rid_i[1:0];
    assign rid_known=((m_axi_rid_i>>2)=='0)&&outstanding_q[rid_tag];
    // Preserve the selected response packet under downstream backpressure.
    // A lower tag could otherwise preempt the visible fixed-priority winner.
    assign m_axi_rready_o=m_axi_rvalid_i&&(!rid_known||
      (!rsp_valid_q[rid_tag]&&!(rsp_valid_o&&!rsp_ready_i&&rid_tag<select_rsp)));
    assign r_fire=m_axi_rvalid_i&&m_axi_rready_o;

    always_comb begin
      select_rsp=2'd0;
      if(rsp_valid_q[0])select_rsp=2'd0;
      else if(rsp_valid_q[1])select_rsp=2'd1;
      else if(rsp_valid_q[2])select_rsp=2'd2;
      else select_rsp=2'd3;
    end
    assign rsp_valid_o=|rsp_valid_q;
    assign rsp_tag_o=select_rsp;
    assign rsp_error_o=rsp_error_q[select_rsp];
    assign rsp_data_o=rsp_data_q[select_rsp];
    assign rsp_fire=rsp_valid_o&&rsp_ready_i;
    assign busy_o=ar_valid_q||(|outstanding_q)||(|rsp_valid_q);
    assign error_sticky_o=|error_status_o;

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        ar_valid_q<=1'b0;
        ar_tag_q<=2'd0;
        ar_addr_q<='0;
        outstanding_q<=4'b0000;
        rsp_valid_q<=4'b0000;
        rsp_error_q<=4'b0000;
        for(int reset_index=0;reset_index<4;reset_index=reset_index+1)
          rsp_data_q[reset_index]<='0;
        error_status_o<=2'b00;
      end else begin
        if(clear_error_i&&!busy_o)
          error_status_o<=2'b00;
        if(req_valid_i&&base_addr_i[SIZE_CODE-1:0]!='0)
          error_status_o[1]<=1'b1;

        if(req_fire)begin
          ar_valid_q<=1'b1;
          ar_tag_q<=req_tag_i;
          ar_addr_q<=base_addr_i+
            ({{(ADDR_W-PIXEL_W){1'b0}},req_pixel_id_i}<<SIZE_CODE);
        end
        if(ar_fire)begin
          ar_valid_q<=1'b0;
          outstanding_q[ar_tag_q]<=1'b1;
        end

        if(rsp_fire)
          rsp_valid_q[select_rsp]<=1'b0;

        if(r_fire)begin
          if(!rid_known)
            error_status_o[0]<=1'b1;
          else begin
            outstanding_q[rid_tag]<=1'b0;
            rsp_valid_q[rid_tag]<=1'b1;
            rsp_data_q[rid_tag]<=m_axi_rdata_i;
            rsp_error_q[rid_tag]<=m_axi_rresp_i!=2'b00||!m_axi_rlast_i;
            if(m_axi_rresp_i!=2'b00||!m_axi_rlast_i)
              error_status_o[0]<=1'b1;
          end
        end
      end
    end

`ifndef SYNTHESIS
    initial assert(ID_W>=2);
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      rsp_valid_o&&!rsp_ready_i|=>rsp_valid_o&&
      $stable({rsp_tag_o,rsp_error_o,rsp_data_o}));
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      ar_valid_q&&!m_axi_arready_i|=>ar_valid_q&&
      $stable({m_axi_arid_o,m_axi_araddr_o}));
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      req_fire|->!outstanding_q[req_tag_i]&&!rsp_valid_q[req_tag_i]);
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      r_fire&&rid_known|=>rsp_valid_q[$past(rid_tag)]||$past(rsp_ready_i));
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      r_fire&&!rid_known|=>error_status_o[0]);
`endif
endmodule
