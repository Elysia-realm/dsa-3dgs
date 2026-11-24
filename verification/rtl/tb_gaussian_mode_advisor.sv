`timescale 1ns/1ps
module tb_gaussian_mode_advisor;
  logic clk_i=0,rst_ni=0,enable_i=1,sample_enable_i=1;logic[1:0]active_mode_i=0;logic mode_commit_pulse_i=0;
  logic group_pressure_i=0,sort_busy_i=0,projection_busy_i=0,raster_busy_i=0;
  logic block_candidate_i=0,block_terminated_skip_i=0;
  logic recommendation_valid_o,recommendation_ready_i=0;logic[1:0]recommendation_mode_o;
  logic window_done_pulse_o;logic[1:0]window_winner_o;logic request_outstanding_o;
  logic[31:0]window_index_o;
  logic[31:0]window_group_count_o,window_sort_count_o,window_projection_count_o;
  logic[31:0]window_raster_count_o,window_block_count_o,window_skip_count_o;
  always#5 clk_i=~clk_i;
  gaussian_mode_advisor #(.WINDOW_CYCLES(8),.HYSTERESIS_WINDOWS(2),
    .MIN_RESIDENCE_WINDOWS(2),.SCORE_MARGIN(2))dut(.*);
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic projection_window;begin integer i;
    group_pressure_i=0;sort_busy_i=0;projection_busy_i=1;raster_busy_i=0;
    block_candidate_i=0;block_terminated_skip_i=0;for(i=0;i<8;i=i+1)tick();
    projection_busy_i=0;
  end endtask
  task automatic energy_window;begin integer i;
    group_pressure_i=0;sort_busy_i=0;projection_busy_i=0;raster_busy_i=0;
    block_candidate_i=1;block_terminated_skip_i=1;for(i=0;i<8;i=i+1)tick();
    block_candidate_i=0;block_terminated_skip_i=0;
  end endtask
  initial begin
    repeat(2)tick();rst_ni=1;tick();
    projection_window();if(recommendation_valid_o)$fatal(1,"advisor ignored hysteresis/residence");
    projection_window();if(recommendation_valid_o)$fatal(1,"advisor switched before full residence");
    projection_window();
    if(!recommendation_valid_o||recommendation_mode_o!=1)$fatal(1,"projection recommendation missing");
    if(window_index_o!=3||window_projection_count_o!=8||window_group_count_o!=0)
      $fatal(1,"advisor window snapshot mismatch index=%0d projection=%0d group=%0d",
        window_index_o,window_projection_count_o,window_group_count_o);
    sample_enable_i=0;repeat(12)tick();
    if(!recommendation_valid_o||recommendation_mode_o!=1)$fatal(1,"idle pause lost outstanding recommendation");
    sample_enable_i=1;
    repeat(3)tick();if(!recommendation_valid_o||recommendation_mode_o!=1)$fatal(1,"recommendation not held");
    recommendation_ready_i=1;tick();recommendation_ready_i=0;
    if(recommendation_valid_o)$fatal(1,"recommendation handshake failed");
    active_mode_i=1;mode_commit_pulse_i=1;tick();mode_commit_pulse_i=0;
    energy_window();energy_window();if(recommendation_valid_o)$fatal(1,"energy mode ignored residence");
    energy_window();if(!recommendation_valid_o||recommendation_mode_o!=3)$fatal(1,"energy recommendation missing");
    enable_i=0;tick();if(recommendation_valid_o)$fatal(1,"disabled advisor retained request");
    $display("PASS: tb_gaussian_mode_advisor");$finish;
  end
endmodule
