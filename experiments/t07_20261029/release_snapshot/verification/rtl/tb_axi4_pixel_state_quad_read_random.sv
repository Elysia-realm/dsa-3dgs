`timescale 1ns/1ps

module tb_axi4_pixel_state_quad_read_random;
  localparam int REQUESTS=500;
  localparam int ID_W=3;
  logic clk_i=0,rst_ni=0,clear_error_i=0;
  logic[63:0]base_addr_i=64'h200000;
  logic req_valid_i=0,req_ready_o;
  logic[1:0]req_tag_i=0;
  logic[31:0]req_pixel_id_i=0;
  logic rsp_valid_o,rsp_ready_i=0;
  logic[1:0]rsp_tag_o;
  logic rsp_error_o;
  logic[127:0]rsp_data_o;
  logic busy_o,error_sticky_o;
  logic[1:0]error_status_o;
  logic[ID_W-1:0]m_axi_arid_o,m_axi_rid_i=0;
  logic[63:0]m_axi_araddr_o;
  logic[7:0]m_axi_arlen_o;
  logic[2:0]m_axi_arsize_o;
  logic[1:0]m_axi_arburst_o;
  logic m_axi_arvalid_o,m_axi_arready_i=0;
  logic[127:0]m_axi_rdata_i=0;
  logic[1:0]m_axi_rresp_i=0;
  logic m_axi_rlast_i=1,m_axi_rvalid_i=0,m_axi_rready_o;

  integer cycle_q=0,seed_q=32'h2468ace1,issued_q=0,received_q=0;
  integer pending_pixel[0:3],pending_delay[0:3];
  integer expected_pixel[0:3],tag_issue_count[0:3];
  logic expected_valid[0:3];
  logic response_active_q=0;
  logic[1:0]response_tag_q=0;
  logic[127:0]response_data_q=0;
  logic[1:0]response_resp_q=0;

  always #5 clk_i=~clk_i;
  axi4_pixel_state_quad_read_engine #(.ID_W(ID_W)) dut(.*);

  function automatic integer next_random(input integer value);
    next_random=(value*32'd1664525)+32'd1013904223;
  endfunction
  function automatic logic[127:0]payload(input integer pixel);
    payload={32'hface0000|pixel[15:0],32'h13570000|pixel[15:0],
             32'h24680000|pixel[15:0],pixel[31:0]};
  endfunction

  always_ff@(posedge clk_i)begin : model
    integer index;
    integer preferred_tag;
    logic found_response;
    if(!rst_ni)begin
      cycle_q<=0;
      seed_q<=32'h2468ace1;
      m_axi_arready_i<=0;
      rsp_ready_i<=0;
      response_active_q<=0;
      m_axi_rvalid_i<=0;
      issued_q<=0;
      received_q<=0;
      for(index=0;index<4;index=index+1)begin
        pending_pixel[index]<=-1;
        pending_delay[index]<=0;
        expected_valid[index]<=0;
        tag_issue_count[index]<=0;
      end
    end else begin
      cycle_q<=cycle_q+1;
      seed_q<=next_random(seed_q);
      m_axi_arready_i<=seed_q[0]||seed_q[4];
      rsp_ready_i<=seed_q[1]||seed_q[5];
      for(index=0;index<4;index=index+1)
        if(pending_delay[index]>0)pending_delay[index]<=pending_delay[index]-1;

      if(m_axi_arvalid_o&&m_axi_arready_i)begin
        if((m_axi_arid_o>>2)!=0||pending_pixel[m_axi_arid_o[1:0]]>=0)
          $fatal(1,"AR reused or invalid ID=%0d",m_axi_arid_o);
        pending_pixel[m_axi_arid_o[1:0]]<=(m_axi_araddr_o-base_addr_i)>>4;
        pending_delay[m_axi_arid_o[1:0]]<=seed_q[9:7];
      end

      if(!response_active_q)begin
        preferred_tag=seed_q[11:10];
        found_response=1'b0;
        for(index=0;index<4;index=index+1)begin
          if(!found_response&&pending_pixel[(preferred_tag+index)&3]>=0&&
             pending_delay[(preferred_tag+index)&3]==0)begin
            found_response=1'b1;
            response_active_q<=1'b1;
            response_tag_q<=(preferred_tag+index)&3;
            response_data_q<=payload(pending_pixel[(preferred_tag+index)&3]);
            // Inject occasional SLVERR while keeping the payload/tag paired.
            response_resp_q<=(seed_q[17:12]==6'h3f)?2'b10:2'b00;
            m_axi_rid_i<={{(ID_W-2){1'b0}},2'((preferred_tag+index)&3)};
            m_axi_rdata_i<=payload(pending_pixel[(preferred_tag+index)&3]);
            m_axi_rresp_i<=(seed_q[17:12]==6'h3f)?2'b10:2'b00;
            m_axi_rlast_i<=1'b1;
            m_axi_rvalid_i<=1'b1;
          end
        end
      end else begin
        if(m_axi_rid_i!=={{(ID_W-2){1'b0}},response_tag_q}||
           m_axi_rdata_i!==response_data_q||m_axi_rresp_i!==response_resp_q||
           !m_axi_rvalid_i)
          $fatal(1,"R channel changed while waiting for ready");
        if(m_axi_rready_o)begin
          pending_pixel[response_tag_q]<=-1;
          response_active_q<=1'b0;
          m_axi_rvalid_i<=1'b0;
        end
      end

      if(req_valid_i&&req_ready_o)begin
        if(expected_valid[req_tag_i])
          $fatal(1,"request tag reused before response tag=%0d",req_tag_i);
        expected_valid[req_tag_i]<=1'b1;
        expected_pixel[req_tag_i]<=req_pixel_id_i;
        tag_issue_count[req_tag_i]<=tag_issue_count[req_tag_i]+1;
        issued_q<=issued_q+1;
      end

      if(rsp_valid_o&&rsp_ready_i)begin
        if(!expected_valid[rsp_tag_o])
          $fatal(1,"unexpected response tag=%0d",rsp_tag_o);
        if(rsp_data_o!==payload(expected_pixel[rsp_tag_o]))
          $fatal(1,"response payload mismatch tag=%0d",rsp_tag_o);
        // Error bit is allowed to follow the random AXI error injection.
        expected_valid[rsp_tag_o]<=1'b0;
        received_q<=received_q+1;
      end
    end
  end

  always_comb begin : request_generator
    integer index;
    logic found_tag;
    logic[1:0]start_tag;
    req_valid_i=1'b0;
    req_tag_i=2'd0;
    req_pixel_id_i=issued_q;
    found_tag=1'b0;
    start_tag=seed_q[19:18];
    if(rst_ni&&issued_q<REQUESTS)begin
      for(index=0;index<4;index=index+1)begin
        if(!found_tag&&!expected_valid[(start_tag+index)&3])begin
          found_tag=1'b1;
          req_valid_i=1'b1;
          req_tag_i=(start_tag+index)&3;
        end
      end
    end
  end

  initial begin : test_control
    integer index;
    repeat(3)@(posedge clk_i);
    rst_ni=1;
    wait(received_q==REQUESTS);
    repeat(8)@(posedge clk_i);
    if(busy_o||response_active_q)
      $fatal(1,"quad reader random test did not drain");
    for(index=0;index<4;index=index+1)begin
      if(expected_valid[index]||pending_pixel[index]>=0||tag_issue_count[index]==0)
        $fatal(1,"tag %0d did not drain/exercise count=%0d",index,tag_issue_count[index]);
    end
    if(!error_sticky_o||!error_status_o[0])
      $fatal(1,"random AXI errors were not recorded");

    // High RID bits are illegal and must not corrupt any response slot.
    m_axi_rid_i=3'b100;
    m_axi_rdata_i=128'hbad;
    m_axi_rresp_i=2'b00;
    m_axi_rlast_i=1'b1;
    m_axi_rvalid_i=1'b1;
    @(posedge clk_i);#1;
    m_axi_rvalid_i=1'b0;
    repeat(2)@(posedge clk_i);
    if(!error_status_o[0])$fatal(1,"unknown RID was not reported");

    clear_error_i=1'b1;
    @(posedge clk_i);#1;
    clear_error_i=1'b0;
    if(error_status_o!=0)$fatal(1,"idle error clear failed");
    $display("PASS: quad AXI random requests=%0d cycles=%0d tags=%0d/%0d/%0d/%0d",
      REQUESTS,cycle_q,tag_issue_count[0],tag_issue_count[1],
      tag_issue_count[2],tag_issue_count[3]);
    $finish;
  end

  initial begin
    #500000;
    $fatal(1,"quad AXI random timeout issued=%0d received=%0d",issued_q,received_q);
  end
endmodule
