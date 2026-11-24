`timescale 1ns/1ps
module tb_projection_epoch_lane_ctrl;
 logic clk_i=0,rst_ni=0,shadow_we_i=0,commit_i=0,epoch_boundary_i=0,lane_array_idle_i=1;
 logic[1:0]shadow_mode_i=0,shadow_mode_o,active_mode_o;logic[2:0]active_lanes_o;
 logic[15:0]epoch_id_o;logic commit_pending_o,commit_pulse_o,commit_overrun_o;
 always#5 clk_i=~clk_i;
 projection_epoch_lane_ctrl dut(.*);
 task automatic tick;begin@(posedge clk_i);#1;end endtask
 initial begin
   repeat(2)tick();rst_ni=1;tick();
   if(active_lanes_o!==2||epoch_id_o!==0)$fatal(1,"reset G-mode lane mismatch");
   // Request four lanes while work is in flight. Even an epoch marker cannot
   // expose the new mode until the lane array reports empty.
   lane_array_idle_i=0;shadow_mode_i=1;shadow_we_i=1;commit_i=1;tick();
   shadow_we_i=0;commit_i=0;epoch_boundary_i=1;tick();
   if(active_lanes_o!==2||!commit_pending_o)$fatal(1,"unsafe mode commit occurred");
   lane_array_idle_i=1;tick();
   if(active_lanes_o!==4||epoch_id_o!==1||!commit_pulse_o||commit_pending_o)
     $fatal(1,"safe 4-lane commit failed lanes=%0d epoch=%0d",active_lanes_o,epoch_id_o);
   epoch_boundary_i=0;tick();
   // Energy mode enables one of the four physical lanes.
   shadow_mode_i=3;shadow_we_i=1;commit_i=1;epoch_boundary_i=1;tick();
   if(active_lanes_o!==1||epoch_id_o!==2)$fatal(1,"E-mode commit failed");
   tick();$display("PASS: tb_projection_epoch_lane_ctrl");$finish;
 end
endmodule
