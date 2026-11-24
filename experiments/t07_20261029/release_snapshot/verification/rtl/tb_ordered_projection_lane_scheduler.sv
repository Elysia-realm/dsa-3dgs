`timescale 1ns/1ps
module tb_ordered_projection_lane_scheduler;
  localparam integer LANES=2,INPUT_W=24,TASK_W=32,META_W=8,SEQ_W=8;
  logic clk_i=0,rst_ni=0;logic[1:0]cfg_active_lanes_i=2;
  logic s_valid_i=0,s_ready_o;logic[INPUT_W-1:0]s_data_i=0;
  logic[LANES-1:0]lane_s_valid_o,lane_s_ready_i=2'b11;
  logic[LANES-1:0][INPUT_W-1:0]lane_s_data_o;
  logic[LANES-1:0]lane_task_valid_i=0,lane_task_ready_o;
  logic[LANES-1:0][TASK_W-1:0]lane_task_data_i=0;
  logic[LANES-1:0]lane_task_first_i=0,lane_task_last_i=0,lane_task_culled_i=0,lane_idle_i=2'b11;
  logic m_valid_o,m_ready_i=1;logic[TASK_W-1:0]m_data_o;logic m_first_o,m_last_o,m_culled_o;
  logic culled_pulse_o;logic[LANES-1:0]active_mask_o;logic all_idle_o,retire_wait_o,retire_protocol_error_o;
  logic[2:0]retire_occupancy_o;integer received=0,phase=0;
  always#5 clk_i=~clk_i;
  ordered_projection_lane_scheduler #(.LANES(LANES),.INPUT_W(INPUT_W),.TASK_W(TASK_W),
    .META_W(META_W),.SEQ_W(SEQ_W),.RETIRE_DEPTH(4),.ENABLE_OPERAND_ISOLATION(1))dut(.*);
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic issue(input integer seq,input integer lane);begin
    integer guard;#1;guard=0;while(!s_ready_o&&guard<20)begin tick();guard=guard+1;end
    if(!s_ready_o)$fatal(1,"issue ready timeout seq=%0d",seq);
    s_data_i={seq[7:0],16'h5500};s_valid_i=1;#1;
    if(lane_s_valid_o!==(2'b1<<lane))$fatal(1,"ordered dispatch mismatch seq=%0d",seq);
    if(lane_s_data_o[lane]!==s_data_i||lane_s_data_o[1-lane]!=='0)
      $fatal(1,"projection operand isolation mismatch seq=%0d lane=%0d",seq,lane);
    tick();s_valid_i=0;lane_idle_i[lane]=0;
  end endtask
  task automatic present(input integer lane,input integer seq,input integer payload,
      input logic first,input logic last,input logic culled);begin
    lane_task_data_i[lane]={seq[7:0],payload[23:0]};lane_task_first_i[lane]=first;
    lane_task_last_i[lane]=last;lane_task_culled_i[lane]=culled;lane_task_valid_i[lane]=1;#1;
  end endtask
  task automatic accept_lane(input integer lane);begin
    integer guard;#1;guard=0;while(!lane_task_ready_o[lane]&&guard<30)begin tick();guard=guard+1;end
    if(!lane_task_ready_o[lane])$fatal(1,"phase %0d lane %0d accept timeout wait=%0d occ=%0d",
      phase,lane,retire_wait_o,retire_occupancy_o);
    tick();lane_task_valid_i[lane]=0;
    if(lane_task_last_i[lane])lane_idle_i[lane]=1;
  end endtask
  always@(posedge clk_i)if(rst_ni&&m_valid_o&&m_ready_i)begin
    case(received)
      0:if(m_data_o!={8'd10,24'h10a0}||!m_first_o||m_last_o||m_culled_o)$fatal(1,"retire 0 mismatch");
      1:if(m_data_o!={8'd10,24'h10a1}||m_first_o||!m_last_o||m_culled_o)$fatal(1,"retire 1 mismatch");
      2:if(m_data_o!={8'd11,24'h11b0}||!m_first_o||!m_last_o||m_culled_o)$fatal(1,"retire 2 mismatch");
      3:if(m_data_o!={8'd12,24'h0}||!m_first_o||!m_last_o||!m_culled_o)$fatal(1,"retire cull mismatch");
      default:$fatal(1,"unexpected ordered output");
    endcase
    received<=received+1;
  end
  initial begin integer timeout;
    repeat(2)tick();rst_ni=1;tick();issue(10,0);issue(11,1);
    if(retire_occupancy_o!=2)$fatal(1,"ordered issue FIFO occupancy=%0d",retire_occupancy_o);
    // Younger lane finishes first and must remain stalled until seq 10 retires.
    present(1,11,24'h11b0,1,1,0);tick();
    if(!retire_wait_o||lane_task_ready_o[1])$fatal(1,"younger projection crossed ordered head");
    phase=1;present(0,10,24'h10a0,1,0,0);accept_lane(0);
    phase=2;present(0,10,24'h10a1,0,1,0);m_ready_i=0;repeat(2)tick();m_ready_i=1;accept_lane(0);
    phase=3;accept_lane(1);issue(12,0);
    if(retire_occupancy_o!=1)$fatal(1,"cull issue FIFO occupancy=%0d",retire_occupancy_o);
    phase=4;present(0,12,0,1,1,1);accept_lane(0);
    timeout=0;while(received<4&&timeout<20)begin tick();timeout=timeout+1;end
    tick();
    if(received!=4||!all_idle_o||retire_occupancy_o!=0||retire_protocol_error_o)
      $fatal(1,"ordered scheduler final state mismatch received=%0d idle=%0d occ=%0d err=%0d",
        received,all_idle_o,retire_occupancy_o,retire_protocol_error_o);
    $display("PASS: tb_ordered_projection_lane_scheduler");$finish;
  end
endmodule
