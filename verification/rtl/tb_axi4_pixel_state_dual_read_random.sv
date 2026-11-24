`timescale 1ns/1ps
module tb_axi4_pixel_state_dual_read_random;
  localparam int REQUESTS=200;
  logic clk_i=0,rst_ni=0,clear_error_i=0;logic[63:0]base_addr_i=64'h100000;
  logic req_valid_i=0,req_ready_o,req_tag_i=0;logic[31:0]req_pixel_id_i=0;
  logic rsp_valid_o,rsp_ready_i=0,rsp_tag_o,rsp_error_o;logic[127:0]rsp_data_o;
  logic busy_o,error_sticky_o;logic[1:0]error_status_o,m_axi_arid_o,m_axi_rid_i=0;
  logic[63:0]m_axi_araddr_o;logic[7:0]m_axi_arlen_o;logic[2:0]m_axi_arsize_o;
  logic[1:0]m_axi_arburst_o;logic m_axi_arvalid_o,m_axi_arready_i=0;
  logic[127:0]m_axi_rdata_i=0;logic[1:0]m_axi_rresp_i=0;
  logic m_axi_rlast_i=1,m_axi_rvalid_i=0,m_axi_rready_o;
  integer cycle_q=0,seed_q=32'h13579bdf,issued_q=0,received_q=0;
  integer pending_pixel[0:1];integer pending_delay[0:1];logic response_active_q=0;
  logic response_tag_q=0;logic[127:0]response_data_q=0;
  integer expected_pixel[0:1];logic expected_valid[0:1];integer tag_issue_count[0:1];
  always#5 clk_i=~clk_i;
  axi4_pixel_state_dual_read_engine dut(.*);
  function automatic integer next_random(input integer value);
    next_random=(value*32'd1664525)+32'd1013904223;
  endfunction
  function automatic logic[127:0]payload(input integer pixel);
    payload={32'hcafe0000|pixel[15:0],32'h5a5a0000|pixel[15:0],32'ha5a50000|pixel[15:0],pixel[31:0]};
  endfunction
  always_ff@(posedge clk_i)begin
    if(!rst_ni)begin
      cycle_q<=0;seed_q<=32'h13579bdf;m_axi_arready_i<=0;rsp_ready_i<=0;
      pending_pixel[0]<=-1;pending_pixel[1]<=-1;pending_delay[0]<=0;pending_delay[1]<=0;
      response_active_q<=0;m_axi_rvalid_i<=0;issued_q<=0;received_q<=0;
      expected_valid[0]<=0;expected_valid[1]<=0;tag_issue_count[0]<=0;tag_issue_count[1]<=0;
    end else begin
      cycle_q<=cycle_q+1;seed_q<=next_random(seed_q);
      m_axi_arready_i<=seed_q[0]||seed_q[3];rsp_ready_i<=seed_q[1]||seed_q[4];
      if(pending_delay[0]>0)pending_delay[0]<=pending_delay[0]-1;
      if(pending_delay[1]>0)pending_delay[1]<=pending_delay[1]-1;
      if(m_axi_arvalid_o&&m_axi_arready_i)begin
        if(m_axi_arid_o[1]||pending_pixel[m_axi_arid_o[0]]>=0)
          $fatal(1,"AR reused/invalid ID id=%0d pending=%0d",m_axi_arid_o,pending_pixel[m_axi_arid_o[0]]);
        pending_pixel[m_axi_arid_o[0]]<=(m_axi_araddr_o-base_addr_i)>>4;
        pending_delay[m_axi_arid_o[0]]<=seed_q[7:5];
      end
      if(!response_active_q)begin
        // Prefer the pseudo-random tag, deliberately allowing ID1-before-ID0.
        if(pending_pixel[seed_q[8]]>=0&&pending_delay[seed_q[8]]==0)begin
          response_active_q<=1;response_tag_q<=seed_q[8];
          response_data_q<=payload(pending_pixel[seed_q[8]]);
          m_axi_rid_i<={1'b0,seed_q[8]};m_axi_rdata_i<=payload(pending_pixel[seed_q[8]]);
          m_axi_rresp_i<=0;m_axi_rlast_i<=1;m_axi_rvalid_i<=1;
        end else if(pending_pixel[~seed_q[8]]>=0&&pending_delay[~seed_q[8]]==0)begin
          response_active_q<=1;response_tag_q<=~seed_q[8];
          response_data_q<=payload(pending_pixel[~seed_q[8]]);
          m_axi_rid_i<={1'b0,~seed_q[8]};m_axi_rdata_i<=payload(pending_pixel[~seed_q[8]]);
          m_axi_rresp_i<=0;m_axi_rlast_i<=1;m_axi_rvalid_i<=1;
        end
      end else begin
        if(m_axi_rid_i!=={1'b0,response_tag_q}||m_axi_rdata_i!==response_data_q||!m_axi_rvalid_i)
          $fatal(1,"R channel changed under backpressure");
        if(m_axi_rready_o)begin
          pending_pixel[response_tag_q]<=-1;response_active_q<=0;m_axi_rvalid_i<=0;
        end
      end
      if(req_valid_i&&req_ready_o)begin
        if(expected_valid[req_tag_i])$fatal(1,"request tag reused before response tag=%0d",req_tag_i);
        expected_valid[req_tag_i]<=1;expected_pixel[req_tag_i]<=req_pixel_id_i;
        tag_issue_count[req_tag_i]<=tag_issue_count[req_tag_i]+1;issued_q<=issued_q+1;
      end
      if(rsp_valid_o&&rsp_ready_i)begin
        if(!expected_valid[rsp_tag_o])$fatal(1,"unexpected response tag=%0d",rsp_tag_o);
        if(rsp_data_o!==payload(expected_pixel[rsp_tag_o])||rsp_error_o)
          $fatal(1,"response mismatch tag=%0d pixel=%0d",rsp_tag_o,expected_pixel[rsp_tag_o]);
        expected_valid[rsp_tag_o]<=0;received_q<=received_q+1;
      end
    end
  end
  always_comb begin
    req_valid_i=0;req_tag_i=0;req_pixel_id_i=issued_q;
    if(rst_ni&&issued_q<REQUESTS)begin
      if(!expected_valid[0]&&(!expected_valid[1]||seed_q[9]))begin req_valid_i=1;req_tag_i=0;end
      else if(!expected_valid[1])begin req_valid_i=1;req_tag_i=1;end
    end
  end
  initial begin
    repeat(3)@(posedge clk_i);rst_ni=1;
    wait(received_q==REQUESTS);repeat(5)@(posedge clk_i);
    if(busy_o||expected_valid[0]||expected_valid[1]||pending_pixel[0]>=0||pending_pixel[1]>=0)
      $fatal(1,"random test did not drain");
    if(tag_issue_count[0]==0||tag_issue_count[1]==0)$fatal(1,"both tags were not exercised");
    // Unknown RID must be consumed as a protocol error without corrupting data.
    m_axi_rid_i=2'b10;m_axi_rdata_i=128'hbad;m_axi_rvalid_i=1;
    @(posedge clk_i);#1;m_axi_rvalid_i=0;repeat(2)@(posedge clk_i);
    if(!error_sticky_o||!error_status_o[0])$fatal(1,"unknown RID error missing");
    $display("PASS: tb_axi4_pixel_state_dual_read_random requests=%0d cycles=%0d tag0=%0d tag1=%0d",
      REQUESTS,cycle_q,tag_issue_count[0],tag_issue_count[1]);$finish;
  end
  initial begin #200000;$fatal(1,"dual reader random timeout issued=%0d received=%0d",issued_q,received_q);end
endmodule
