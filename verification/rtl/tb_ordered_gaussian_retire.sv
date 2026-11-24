`timescale 1ns/1ps
module tb_ordered_gaussian_retire;
  logic clk_i=0,rst_ni=0,issue_valid_i=0,issue_ready_o;logic[7:0]issue_seq_i=0;
  logic[1:0]lane_valid_i=0,lane_ready_o;logic[1:0][7:0]lane_seq_i=0,lane_data_i=0;
  logic[1:0]lane_first_i=0,lane_last_i=0,lane_culled_i=0;
  logic m_valid_o,m_ready_i=1;logic[7:0]m_seq_o,m_data_o;logic m_first_o,m_last_o,m_culled_o;
  logic[2:0]occupancy_o;logic empty_o,retire_wait_o,protocol_error_o;
  logic[7:0]expect_seq[0:3],expect_data[0:3];logic expect_first[0:3],expect_last[0:3],expect_culled[0:3];
  integer received=0;
  always#5 clk_i=~clk_i;
  ordered_gaussian_retire #(.LANES(2),.DEPTH(4),.SEQ_W(8),.DATA_W(8))dut(
    .clk_i(clk_i),.rst_ni(rst_ni),.issue_valid_i(issue_valid_i),.issue_ready_o(issue_ready_o),
    .issue_seq_i(issue_seq_i),.lane_valid_i(lane_valid_i),.lane_ready_o(lane_ready_o),.lane_seq_i(lane_seq_i),
    .lane_data_i(lane_data_i),.lane_first_i(lane_first_i),.lane_last_i(lane_last_i),.lane_culled_i(lane_culled_i),
    .m_valid_o(m_valid_o),.m_ready_i(m_ready_i),.m_seq_o(m_seq_o),.m_data_o(m_data_o),
    .m_first_o(m_first_o),.m_last_o(m_last_o),.m_culled_o(m_culled_o),.occupancy_o(occupancy_o),
    .empty_o(empty_o),.retire_wait_o(retire_wait_o),.protocol_error_o(protocol_error_o));
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic issue(input integer seq);begin
    while(!issue_ready_o)tick();issue_seq_i=seq;issue_valid_i=1;tick();issue_valid_i=0;
  end endtask
  task automatic set_lane(input integer lane,input integer seq,input integer data,
      input logic first,input logic last,input logic culled);begin
    lane_seq_i[lane]=seq;lane_data_i[lane]=data;lane_first_i[lane]=first;
    lane_last_i[lane]=last;lane_culled_i[lane]=culled;lane_valid_i[lane]=1;#1;
  end endtask
  task automatic wait_lane_accept(input integer lane);begin
    #1;while(!(lane_valid_i[lane]&&lane_ready_o[lane]))tick();tick();lane_valid_i[lane]=0;
  end endtask
  always@(posedge clk_i)if(rst_ni&&m_valid_o&&m_ready_i)begin
    if(received>3||m_seq_o!==expect_seq[received]||m_data_o!==expect_data[received]||
       m_first_o!==expect_first[received]||m_last_o!==expect_last[received]||m_culled_o!==expect_culled[received])
      $fatal(1,"retire[%0d] mismatch seq/data/f/l/c=%0d/%0d/%0d/%0d/%0d",
        received,m_seq_o,m_data_o,m_first_o,m_last_o,m_culled_o);
    received<=received+1;
  end
  initial begin integer timeout;logic[7:0]held_data;
    expect_seq[0]=10;expect_data[0]=8'hA0;expect_first[0]=1;expect_last[0]=0;expect_culled[0]=0;
    expect_seq[1]=10;expect_data[1]=8'hA1;expect_first[1]=0;expect_last[1]=1;expect_culled[1]=0;
    expect_seq[2]=11;expect_data[2]=8'hB0;expect_first[2]=1;expect_last[2]=1;expect_culled[2]=0;
    expect_seq[3]=12;expect_data[3]=0;expect_first[3]=1;expect_last[3]=1;expect_culled[3]=1;
    repeat(2)tick();rst_ni=1;tick();issue(10);issue(11);issue(12);
    if(occupancy_o!==3)$fatal(1,"issue occupancy=%0d",occupancy_o);
    set_lane(1,11,8'hB0,1,1,0);tick();
    if(!retire_wait_o||lane_ready_o[1])$fatal(1,"younger Gaussian retired before head");
    set_lane(0,10,8'hA0,1,0,0);wait_lane_accept(0);
    set_lane(0,10,8'hA1,0,1,0);m_ready_i=0;tick();held_data=m_data_o;
    repeat(2)begin tick();if(!m_valid_o||m_data_o!==held_data||lane_ready_o[0])$fatal(1,"retire stall failure");end
    m_ready_i=1;wait_lane_accept(0);
    // Lane 1 has held Gaussian 11 stable throughout the head retirement.
    wait_lane_accept(1);
    set_lane(0,12,0,1,1,1);wait_lane_accept(0);
    timeout=0;while(received<4&&timeout<20)begin tick();timeout=timeout+1;end
    if(received!=4||!empty_o||occupancy_o!=0||protocol_error_o)
      $fatal(1,"retire final received/occ/error=%0d/%0d/%0d",received,occupancy_o,protocol_error_o);
    $display("PASS: tb_ordered_gaussian_retire");$finish;
  end
endmodule
