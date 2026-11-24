`timescale 1ns/1ps
module tb_ordered_sh_lane_scheduler;
  localparam LANES=4,SEQ_W=8,INPUT_W=16,RESULT_W=16;
  logic clk_i=0,rst_ni=0;logic[2:0]cfg_active_lanes_i=4;logic s_valid_i=0,s_ready_o;logic[SEQ_W-1:0]s_seq_i=0;
  logic[INPUT_W-1:0]s_data_i=0;logic[LANES-1:0]lane_s_valid_o;logic[LANES-1:0]lane_s_ready_i='1;
  logic[LANES-1:0][INPUT_W-1:0]lane_s_data_o;logic[LANES-1:0]lane_m_valid_i='0;logic[LANES-1:0]lane_m_ready_o;
  logic[LANES-1:0][SEQ_W-1:0]lane_m_seq_i='0;logic[LANES-1:0][RESULT_W-1:0]lane_m_data_i='0;
  logic m_valid_o,m_ready_i=1;logic[SEQ_W-1:0]m_seq_o;logic[RESULT_W-1:0]m_data_o;logic[LANES-1:0]active_mask_o;
  logic all_idle_o,retire_wait_o,protocol_error_o;logic[4:0]outstanding_o;
  logic[LANES-1:0]pending_q;logic[LANES-1:0][SEQ_W-1:0]seq_q;logic[LANES-1:0][3:0]delay_q;integer i;
  always#5 clk_i=~clk_i;
  ordered_sh_lane_scheduler #(.LANES(LANES),.INPUT_W(INPUT_W),.RESULT_W(RESULT_W),.SEQ_W(SEQ_W),
    .RETIRE_DEPTH(16),.ENABLE_OPERAND_ISOLATION(1))dut(.*);
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  // Synthetic lanes use descending latency: lane0 is slowest, lane3 fastest,
  // forcing completion order away from issue order.
  always_ff@(posedge clk_i or negedge rst_ni)begin
    if(!rst_ni)begin pending_q<='0;lane_m_valid_i<='0;end else begin
      for(i=0;i<LANES;i=i+1)begin
        if(lane_s_valid_o[i]&&lane_s_ready_i[i])begin pending_q[i]<=1;seq_q[i]<=s_data_i[SEQ_W-1:0];delay_q[i]<=LANES-i;end
        if(pending_q[i]&&!lane_m_valid_i[i])begin
          if(delay_q[i]==0)begin lane_m_valid_i[i]<=1;lane_m_seq_i[i]<=seq_q[i];lane_m_data_i[i]<={8'hc0,seq_q[i]};end
          else delay_q[i]<=delay_q[i]-1'b1;
        end
        if(lane_m_valid_i[i]&&lane_m_ready_o[i])begin lane_m_valid_i[i]<=0;pending_q[i]<=0;end
      end
    end
  end
  task automatic send(input integer seq);integer selected,lane;begin while(!s_ready_o)tick();s_seq_i=seq;s_data_i=seq;s_valid_i=1;#1;
    selected=-1;for(lane=0;lane<LANES;lane=lane+1)if(lane_s_valid_o[lane])selected=lane;
    if(selected<0||lane_s_data_o[selected]!==s_data_i)$fatal(1,"SH selected input isolation mismatch");
    for(lane=0;lane<LANES;lane=lane+1)if(lane!=selected&&lane_s_data_o[lane]!=='0)
      $fatal(1,"inactive SH lane input toggled lane=%0d",lane);
    tick();s_valid_i=0;end endtask
  initial begin integer expected,timeout;repeat(2)tick();rst_ni=1;tick();
    if(active_mask_o!==4'b1111)$fatal(1,"four-lane mask mismatch");
    send(1);send(2);send(3);send(4);expected=1;timeout=0;
    while(expected<=4&&timeout<40)begin m_ready_i=(timeout%4!=1);
      if(m_valid_o&&m_ready_i)begin
        if(m_seq_o!==expected||m_data_o!=={8'hc0,expected[7:0]})$fatal(1,"SH ordered retire mismatch got=%0d expected=%0d",m_seq_o,expected);
        expected=expected+1;
      end
      tick();timeout=timeout+1;
    end
    if(expected!=5||protocol_error_o)$fatal(1,"SH scheduler timeout/protocol");
    timeout=0;while(!all_idle_o&&timeout<10)begin tick();timeout=timeout+1;end
    if(!all_idle_o||outstanding_o!=0)$fatal(1,"SH scheduler did not drain");
    cfg_active_lanes_i=1;tick();if(active_mask_o!==4'b0001)$fatal(1,"one-lane gating mismatch");
    send(9);timeout=0;while(!(m_valid_o&&m_ready_i)&&timeout<15)begin tick();timeout=timeout+1;end
    if(m_seq_o!==9)$fatal(1,"single-lane issue failed");tick();
    $display("PASS: tb_ordered_sh_lane_scheduler");$finish;
  end
endmodule
