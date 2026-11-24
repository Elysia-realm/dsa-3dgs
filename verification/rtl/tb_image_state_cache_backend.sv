`timescale 1ns/1ps
module tb_image_state_cache_backend;
  logic clk_i=0,rst_ni=0,query_valid_i=0,query_ready_o;logic[31:0]query_pixel_id_i=0;
  logic[15:0]query_epoch_id_i=0;logic query_tag_i=0;logic response_valid_o,response_ready_i=0,response_tag_o;
  logic[12:0]response_r_q12_o,response_g_q12_o,response_b_q12_o;logic[15:0]response_t_q16_o;
  logic update_valid_i=0;logic[31:0]update_pixel_id_i=0;logic[15:0]update_epoch_id_i=0;
  logic[12:0]update_r_q12_i=0,update_g_q12_i=0,update_b_q12_i=0;logic[15:0]update_t_q16_i=0;
  logic miss_req_valid_o,miss_req_ready_i=0,miss_req_tag_o;logic[31:0]miss_req_pixel_id_o;
  logic miss_rsp_valid_i=0,miss_rsp_ready_o,miss_rsp_tag_i=0,miss_rsp_error_i=0;logic[127:0]miss_rsp_data_i=0;
  logic error_sticky_o,idle_o;
  always #5 clk_i=~clk_i;
  image_state_cache_backend #(.ENTRIES(2))dut(.*);
  task automatic tick;begin @(posedge clk_i);#1;end endtask
  task automatic start_query(input tag,input[31:0]pixel,input[15:0]epoch);begin
    integer guard;query_pixel_id_i=pixel;query_epoch_id_i=epoch;query_tag_i=tag;guard=0;#1;
    while(!query_ready_o&&guard<50)begin tick();guard=guard+1;end
    if(guard>=50)$fatal(1,"query timeout pixel=%0d mshr=%b issued=%b rsp=%b",pixel,dut.mshr_valid_q,dut.mshr_issued_q,response_valid_o);
    query_valid_i=1;
    tick();query_valid_i=0;
  end endtask
  task automatic accept_miss(input tag,input[31:0]pixel);begin
    if(!miss_req_valid_o||miss_req_tag_o!==tag||miss_req_pixel_id_o!==pixel)
      $fatal(1,"bad miss request tag=%0d pixel=%0d",miss_req_tag_o,miss_req_pixel_id_o);
    miss_req_ready_i=1;tick();miss_req_ready_i=0;
  end endtask
  task automatic return_miss(input tag,input[15:0]epoch,input[12:0]r,input[12:0]g,input[12:0]b,input[15:0]t,input err);begin
    miss_rsp_data_i='0;miss_rsp_data_i[12:0]=r;miss_rsp_data_i[25:13]=g;
    miss_rsp_data_i[38:26]=b;miss_rsp_data_i[54:39]=t;miss_rsp_data_i[70:55]=epoch;
    miss_rsp_tag_i=tag;miss_rsp_error_i=err;miss_rsp_valid_i=1;#1;
    if(!miss_rsp_ready_o)$fatal(1,"miss response tag %0d not ready mshr=%b issued=%b rsp=%b/%b",
      tag,dut.mshr_valid_q,dut.mshr_issued_q,response_valid_o,response_ready_i);
    tick();miss_rsp_valid_i=0;miss_rsp_error_i=0;
  end endtask
  task automatic expect_rsp(input tag,input[12:0]r,input[12:0]g,input[12:0]b,input[15:0]t);begin
    integer guard;guard=0;while(!response_valid_o&&guard<50)begin tick();guard=guard+1;end
    if(guard>=50)$fatal(1,"response timeout tag=%0d mshr=%b issued=%b",tag,dut.mshr_valid_q,dut.mshr_issued_q);
    if(!response_valid_o||{response_r_q12_o,response_g_q12_o,response_b_q12_o,response_t_q16_o}!={r,g,b,t})
      $fatal(1,"bad response %0d %0d %0d %0d",response_r_q12_o,response_g_q12_o,response_b_q12_o,response_t_q16_o);
    if(response_tag_o!==tag)$fatal(1,"bad response tag got=%0d expected=%0d",response_tag_o,tag);
    tick();if(!response_valid_o)$fatal(1,"response not held");response_ready_i=1;tick();response_ready_i=0;
  end endtask
  task automatic update(input[31:0]pixel,input[15:0]epoch,input[12:0]r,input[15:0]t);begin
    update_pixel_id_i=pixel;update_epoch_id_i=epoch;update_r_q12_i=r;update_g_q12_i=r+1;
    update_b_q12_i=r+2;update_t_q16_i=t;update_valid_i=1;tick();update_valid_i=0;
  end endtask
  initial begin
    repeat(2)tick();rst_ni=1;tick();
    start_query(0,0,1);accept_miss(0,0);return_miss(0,0,9,9,9,9,0);expect_rsp(0,0,0,0,16'hffff);
    update(0,1,10,16'hf000);start_query(0,0,1);expect_rsp(0,10,11,12,16'hf000);
    // Two MSHRs may be issued together. Pixel 2 and pixel 4 deliberately map
    // to the same direct-mapped cache index, while ID1 returns before ID0.
    start_query(0,2,1);accept_miss(0,2);
    start_query(1,4,1);accept_miss(1,4);
    query_tag_i=0;query_pixel_id_i=6;query_epoch_id_i=1;#1;
    if(query_ready_o)$fatal(1,"query tag reused before its MSHR was released");
    return_miss(1,1,40,41,42,16'hd000,0);expect_rsp(1,40,41,42,16'hd000);
    return_miss(0,1,20,21,22,16'he000,0);expect_rsp(0,20,21,22,16'he000);
    // A differently tagged resident hit may pass an older outstanding miss.
    update(1,1,50,16'hb000);start_query(0,8,1);accept_miss(0,8);
    start_query(1,1,1);expect_rsp(1,50,51,52,16'hb000);
    return_miss(0,1,80,81,82,16'he000,0);expect_rsp(0,80,81,82,16'he000);
    start_query(0,0,1);accept_miss(0,0);return_miss(0,1,10,11,12,16'hf000,0);expect_rsp(0,10,11,12,16'hf000);
    start_query(0,0,2);accept_miss(0,0);return_miss(0,1,10,11,12,16'hf000,0);expect_rsp(0,0,0,0,16'hffff);
    start_query(0,4,2);accept_miss(0,4);return_miss(0,2,30,31,32,16'hd000,1);expect_rsp(0,0,0,0,16'hffff);
    if(!error_sticky_o)$fatal(1,"miss error not sticky");
    // Update and miss fill target the same direct-mapped entry. The newer
    // blend update must win over the stale fill in that cycle.
    start_query(0,6,3);accept_miss(0,6);
    update_pixel_id_i=6;update_epoch_id_i=3;update_r_q12_i=40;update_g_q12_i=41;
    update_b_q12_i=42;update_t_q16_i=16'hc000;update_valid_i=1;
    miss_rsp_data_i='0;miss_rsp_data_i[12:0]=1;miss_rsp_data_i[25:13]=2;miss_rsp_data_i[38:26]=3;
    miss_rsp_data_i[54:39]=16'h1111;miss_rsp_data_i[70:55]=3;miss_rsp_tag_i=0;miss_rsp_valid_i=1;tick();
    update_valid_i=0;miss_rsp_valid_i=0;expect_rsp(0,1,2,3,16'h1111);
    start_query(0,6,3);expect_rsp(0,40,41,42,16'hc000);
    if(!idle_o)$fatal(1,"cache not idle");
    $display("PASS: tb_image_state_cache_backend");$finish;
  end
endmodule
