`timescale 1ns/1ps
module tb_projection_lane_scheduler;
 localparam LANES=4,INPUT_W=16,TASK_W=20;
 logic clk_i=0,rst_ni=0;logic[2:0]cfg_active_lanes_i=2;
 logic s_valid_i=0,s_ready_o;logic[15:0]s_data_i=0;
 logic[3:0]lane_s_valid_o,lane_s_ready_i=4'hf;logic[3:0][15:0]lane_s_data_o;
 logic[3:0]lane_task_valid_i=0,lane_task_ready_o;logic[3:0][19:0]lane_task_data_i='0;
 logic[3:0]lane_task_first_i=0,lane_task_last_i=0,lane_culled_pulse_i=0,lane_idle_i=4'hf;
 logic m_valid_o,m_ready_i=1;logic[19:0]m_data_o;logic m_first_o,m_last_o,culled_pulse_o;
 logic[3:0]active_mask_o;logic all_idle_o;
 always#5 clk_i=~clk_i;
 projection_lane_scheduler #(.LANES(LANES),.INPUT_W(INPUT_W),.TASK_W(TASK_W),.ENABLE_OPERAND_ISOLATION(1))dut(.*);
 task automatic tick;begin@(posedge clk_i);#1;end endtask
 task automatic send(input logic[15:0]value,input integer expected_lane);integer inactive;begin
   while(!s_ready_o)tick();s_data_i=value;s_valid_i=1;#1;
   if(lane_s_valid_o!==(4'b1<<expected_lane)||lane_s_data_o[expected_lane]!==value)
      $fatal(1,"dispatch mismatch value=%h valids=%b",value,lane_s_valid_o);
   for(inactive=0;inactive<LANES;inactive=inactive+1)
     if(inactive!=expected_lane&&lane_s_data_o[inactive]!=='0)
       $fatal(1,"inactive projection lane input toggled lane=%0d",inactive);
   tick();s_valid_i=0;
 end endtask
 initial begin integer timeout;
   repeat(2)tick();rst_ni=1;tick();
   if(active_mask_o!==4'b0011||!all_idle_o)$fatal(1,"reset mode mismatch mask=%b",active_mask_o);
   send(16'h10,0);send(16'h11,1);send(16'h12,0);send(16'h13,1);
   // Lane 0 owns a two-task Gaussian. Lane 1 is valid concurrently, but may
   // not interleave until lane 0's last task is accepted.
   lane_task_valid_i=4'b0011;lane_task_first_i=4'b0011;lane_task_last_i=4'b0010;
   lane_task_data_i[0]=20'h0a0;lane_task_data_i[1]=20'h1b0;#1;
   if(!m_valid_o||m_data_o!==20'h0a0||!m_first_o||m_last_o)
      $fatal(1,"first arbitration mismatch data=%h",m_data_o);
   tick();
   lane_task_first_i[0]=0;lane_task_last_i[0]=1;lane_task_data_i[0]=20'h0a1;#1;
   if(m_data_o!==20'h0a1||!m_last_o)$fatal(1,"lock mismatch data=%h",m_data_o);
   tick();lane_task_valid_i[0]=0;#1;
   if(!m_valid_o||m_data_o!==20'h1b0||!m_first_o||!m_last_o)
      $fatal(1,"round-robin handoff mismatch data=%h",m_data_o);
   tick();lane_task_valid_i=0;lane_task_first_i=0;lane_task_last_i=0;
   // Mode changes only while idle; three enabled lanes then dispatch 0,1,2.
   cfg_active_lanes_i=3;tick();if(active_mask_o!==4'b0111)$fatal(1,"3-lane mask mismatch");
   send(16'h20,0);send(16'h21,1);send(16'h22,2);send(16'h23,0);
   lane_culled_pulse_i=4'b0100;#1;if(!culled_pulse_o)$fatal(1,"cull reduction missing");
   tick();lane_culled_pulse_i=0;
   // Disabled lanes do not prevent global idle.
   cfg_active_lanes_i=1;lane_idle_i=4'b1111;tick();
   lane_idle_i=4'b1110;#1;if(all_idle_o)$fatal(1,"active busy lane ignored");
   lane_idle_i=4'b0001;#1;if(!all_idle_o)$fatal(1,"disabled busy lanes blocked idle");
   tick();$display("PASS: tb_projection_lane_scheduler");$finish;
 end
endmodule
