`timescale 1ns/1ps

module tb_image_state_cache_backend_4;
  logic clk_i=0,rst_ni=0;
  logic query_valid_i=0,query_ready_o;
  logic[31:0]query_pixel_id_i=0;
  logic[15:0]query_epoch_id_i=0;
  logic[1:0]query_tag_i=0;
  logic response_valid_o,response_ready_i=0;
  logic[1:0]response_tag_o;
  logic[12:0]response_r_q12_o,response_g_q12_o,response_b_q12_o;
  logic[15:0]response_t_q16_o;
  logic update_valid_i=0;
  logic[31:0]update_pixel_id_i=0;
  logic[15:0]update_epoch_id_i=0;
  logic[12:0]update_r_q12_i=0,update_g_q12_i=0,update_b_q12_i=0;
  logic[15:0]update_t_q16_i=0;
  logic miss_req_valid_o,miss_req_ready_i=0;
  logic[1:0]miss_req_tag_o;
  logic[31:0]miss_req_pixel_id_o;
  logic miss_rsp_valid_i=0,miss_rsp_ready_o;
  logic[1:0]miss_rsp_tag_i=0;
  logic miss_rsp_error_i=0;
  logic[127:0]miss_rsp_data_i=0;
  logic error_sticky_o,idle_o;

  always #5 clk_i=~clk_i;

  image_state_cache_backend_4 #(.ENTRIES(4)) dut(.*);

  task automatic tick;
    begin @(posedge clk_i); #1; end
  endtask

  task automatic start_query(
    input logic[1:0]tag,input logic[31:0]pixel,input logic[15:0]epoch
  );
    integer guard;
    begin
      query_pixel_id_i=pixel;
      query_epoch_id_i=epoch;
      query_tag_i=tag;
      guard=0;
      #1;
      while(!query_ready_o&&guard<100)begin tick();guard=guard+1;end
      if(guard>=100)$fatal(1,"query timeout tag=%0d pixel=%0d",tag,pixel);
      query_valid_i=1;
      tick();
      query_valid_i=0;
    end
  endtask

  task automatic accept_miss(input logic[1:0]tag,input logic[31:0]pixel);
    integer guard;
    begin
      guard=0;
      while((!miss_req_valid_o||miss_req_tag_o!==tag)&&guard<100)begin tick();guard=guard+1;end
      if(guard>=100||miss_req_pixel_id_o!==pixel)
        $fatal(1,"bad miss request got tag/pixel=%0d/%0d expected=%0d/%0d",
          miss_req_tag_o,miss_req_pixel_id_o,tag,pixel);
      miss_req_ready_i=1;
      tick();
      miss_req_ready_i=0;
    end
  endtask

  task automatic return_miss(
    input logic[1:0]tag,input logic[15:0]epoch,input logic[12:0]red,
    input logic[15:0]transmittance,input logic error_response
  );
    integer guard;
    begin
      miss_rsp_data_i='0;
      miss_rsp_data_i[12:0]=red;
      miss_rsp_data_i[25:13]=red+1'b1;
      miss_rsp_data_i[38:26]=red+2'd2;
      miss_rsp_data_i[54:39]=transmittance;
      miss_rsp_data_i[70:55]=epoch;
      miss_rsp_tag_i=tag;
      miss_rsp_error_i=error_response;
      miss_rsp_valid_i=1;
      guard=0;
      #1;
      while(!miss_rsp_ready_o&&guard<100)begin tick();guard=guard+1;end
      if(guard>=100)$fatal(1,"miss response timeout tag=%0d",tag);
      tick();
      miss_rsp_valid_i=0;
      miss_rsp_error_i=0;
    end
  endtask

  task automatic expect_response(
    input logic[1:0]tag,input logic[12:0]red,input logic[15:0]transmittance
  );
    integer guard;
    begin
      guard=0;
      while(!response_valid_o&&guard<100)begin tick();guard=guard+1;end
      if(guard>=100)$fatal(1,"cache response timeout tag=%0d",tag);
      if(response_tag_o!==tag||response_r_q12_o!==red||
         response_g_q12_o!==(red+1'b1)||response_b_q12_o!==(red+2'd2)||
         response_t_q16_o!==transmittance)
        $fatal(1,"bad cache response tag/r/g/b/t=%0d/%0d/%0d/%0d/%0d",
          response_tag_o,response_r_q12_o,response_g_q12_o,
          response_b_q12_o,response_t_q16_o);
      tick();
      if(!response_valid_o)$fatal(1,"response not held under backpressure");
      response_ready_i=1;
      tick();
      response_ready_i=0;
    end
  endtask

  task automatic expect_default_response(input logic[1:0]tag);
    integer guard;
    begin
      guard=0;
      while(!response_valid_o&&guard<100)begin tick();guard=guard+1;end
      if(guard>=100)$fatal(1,"default response timeout tag=%0d",tag);
      if(response_tag_o!==tag||response_r_q12_o!==0||response_g_q12_o!==0||
         response_b_q12_o!==0||response_t_q16_o!==16'hffff)
        $fatal(1,"bad default response tag=%0d",tag);
      response_ready_i=1;
      tick();
      response_ready_i=0;
    end
  endtask

  initial begin
    repeat(3)tick();
    rst_ni=1;
    tick();

    // Four simultaneous physical MSHRs, all colliding in direct-map index 0.
    start_query(2'd0,32'd0,16'd1); accept_miss(2'd0,32'd0);
    start_query(2'd1,32'd4,16'd1); accept_miss(2'd1,32'd4);
    start_query(2'd2,32'd8,16'd1); accept_miss(2'd2,32'd8);
    start_query(2'd3,32'd12,16'd1); accept_miss(2'd3,32'd12);
    query_tag_i=2'd2;query_pixel_id_i=32'd16;query_epoch_id_i=16'd1;#1;
    if(query_ready_o)$fatal(1,"tag reused before MSHR response retirement");

    // AXI-style out-of-order response order 3,1,2,0.
    return_miss(2'd3,16'd1,13'd120,16'hc000,1'b0);
    expect_response(2'd3,13'd120,16'hc000);
    return_miss(2'd1,16'd1,13'd40,16'he000,1'b0);
    expect_response(2'd1,13'd40,16'he000);
    return_miss(2'd2,16'd1,13'd80,16'hd000,1'b0);
    expect_response(2'd2,13'd80,16'hd000);
    return_miss(2'd0,16'd1,13'd10,16'hf000,1'b0);
    expect_response(2'd0,13'd10,16'hf000);

    // The last fill owns index 0; resident hit returns without a new miss.
    start_query(2'd2,32'd0,16'd1);
    expect_response(2'd2,13'd10,16'hf000);

    // Epoch mismatch and an explicit read error both map to empty state.
    start_query(2'd0,32'd1,16'd2);accept_miss(2'd0,32'd1);
    return_miss(2'd0,16'd1,13'd30,16'h1111,1'b0);
    expect_default_response(2'd0);
    start_query(2'd1,32'd2,16'd3);accept_miss(2'd1,32'd2);
    return_miss(2'd1,16'd3,13'd50,16'h2222,1'b1);
    expect_default_response(2'd1);
    if(!error_sticky_o)$fatal(1,"read error did not set sticky status");

    // Concurrent fill and architected update to the same line: update wins.
    start_query(2'd3,32'd7,16'd4);accept_miss(2'd3,32'd7);
    update_pixel_id_i=32'd7;
    update_epoch_id_i=16'd4;
    update_r_q12_i=13'd700;
    update_g_q12_i=13'd701;
    update_b_q12_i=13'd702;
    update_t_q16_i=16'ha000;
    update_valid_i=1;
    miss_rsp_data_i='0;
    miss_rsp_data_i[12:0]=13'd7;
    miss_rsp_data_i[25:13]=13'd8;
    miss_rsp_data_i[38:26]=13'd9;
    miss_rsp_data_i[54:39]=16'h0707;
    miss_rsp_data_i[70:55]=16'd4;
    miss_rsp_tag_i=2'd3;
    miss_rsp_valid_i=1;
    #1;
    if(!miss_rsp_ready_o)$fatal(1,"fill/update collision response not ready");
    tick();
    update_valid_i=0;
    miss_rsp_valid_i=0;
    expect_response(2'd3,13'd7,16'h0707);
    start_query(2'd0,32'd7,16'd4);
    expect_response(2'd0,13'd700,16'ha000);

    if(!idle_o)$fatal(1,"quad cache did not drain");
    $display("PASS: quad MSHR cache, OOO fill, collision, error and update priority");
    $finish;
  end
endmodule
