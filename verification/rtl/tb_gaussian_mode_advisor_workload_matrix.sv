`timescale 1ns/1ps
// Long-window policy calibration matrix.  These profiles intentionally drive
// the advisor boundary directly; system-top tests separately prove that the
// same inputs originate from the real Gaussian render pipeline.
module tb_gaussian_mode_advisor_workload_matrix;
  localparam integer WINDOW_CYCLES=64;
  localparam logic[1:0] MODE_G=2'd0,MODE_P=2'd1,MODE_R=2'd2,MODE_E=2'd3;
  logic clk_i=0,rst_ni=0,enable_i=1,sample_enable_i=1;
  logic[1:0]active_mode_i=MODE_G;logic mode_commit_pulse_i=0;
  logic group_pressure_i=0,sort_busy_i=0,projection_busy_i=0,raster_busy_i=0;
  logic block_candidate_i=0,block_terminated_skip_i=0;
  logic recommendation_valid_o,recommendation_ready_i=0;logic[1:0]recommendation_mode_o;
  logic window_done_pulse_o;logic[1:0]window_winner_o;logic request_outstanding_o;
  logic[31:0]window_index_o;
  logic[31:0]window_group_count_o,window_sort_count_o,window_projection_count_o;
  logic[31:0]window_raster_count_o,window_block_count_o,window_skip_count_o;

  always#5 clk_i=~clk_i;
  gaussian_mode_advisor #(.WINDOW_CYCLES(WINDOW_CYCLES),.HYSTERESIS_WINDOWS(2),
    .MIN_RESIDENCE_WINDOWS(1),.SCORE_MARGIN(4))dut(.*);

  task automatic tick;begin@(posedge clk_i);#1;end endtask

  task automatic clear_events;begin
    group_pressure_i=0;sort_busy_i=0;projection_busy_i=0;raster_busy_i=0;
    block_candidate_i=0;block_terminated_skip_i=0;
  end endtask

  task automatic drive_cycle(input integer profile,input integer index);begin
    clear_events();
    case(profile)
      0:begin // G: grouping plus sorting dominates.
        group_pressure_i=1;sort_busy_i=1;
        projection_busy_i=(index%4)==0;
        raster_busy_i=(index%8)==0;block_candidate_i=(index%8)==0;
      end
      1:begin // P: projection dominates.
        group_pressure_i=(index%8)==0;sort_busy_i=(index%8)==0;
        projection_busy_i=1;
        raster_busy_i=(index%8)==0;block_candidate_i=(index%8)==0;
      end
      2:begin // R: raster work and candidate blocks dominate.
        group_pressure_i=(index%8)==0;sort_busy_i=(index%8)==0;
        projection_busy_i=(index%4)==0;
        raster_busy_i=1;block_candidate_i=1;
      end
      3:begin // E: 56/64 candidate blocks are already terminated.
        group_pressure_i=(index%8)==0;sort_busy_i=(index%8)==0;
        projection_busy_i=(index%4)==0;raster_busy_i=(index%2)==0;
        block_candidate_i=1;block_terminated_skip_i=index<56;
      end
      default:begin // Balanced: equal G/P/R scores retain general mode G.
        group_pressure_i=(index%2)==0;sort_busy_i=(index%2)==1;
        projection_busy_i=1;
        raster_busy_i=(index%2)==0;block_candidate_i=(index%2)==1;
      end
    endcase
  end endtask

  task automatic check_counts(input integer profile);begin
    case(profile)
      0:if(window_group_count_o!=64||window_sort_count_o!=64||
           window_projection_count_o!=16||window_raster_count_o!=8||
           window_block_count_o!=8||window_skip_count_o!=0)
          $fatal(1,"G snapshot mismatch");
      1:if(window_group_count_o!=8||window_sort_count_o!=8||
           window_projection_count_o!=64||window_raster_count_o!=8||
           window_block_count_o!=8||window_skip_count_o!=0)
          $fatal(1,"P snapshot mismatch");
      2:if(window_group_count_o!=8||window_sort_count_o!=8||
           window_projection_count_o!=16||window_raster_count_o!=64||
           window_block_count_o!=64||window_skip_count_o!=0)
          $fatal(1,"R snapshot mismatch");
      3:if(window_group_count_o!=8||window_sort_count_o!=8||
           window_projection_count_o!=16||window_raster_count_o!=32||
           window_block_count_o!=64||window_skip_count_o!=56)
          $fatal(1,"E snapshot mismatch");
      default:if(window_group_count_o!=32||window_sort_count_o!=32||
           window_projection_count_o!=64||window_raster_count_o!=32||
           window_block_count_o!=32||window_skip_count_o!=0)
          $fatal(1,"balanced snapshot mismatch");
    endcase
  end endtask

  task automatic run_profile(input integer profile,input logic[1:0]start_mode,
      input logic[1:0]expected_winner,input logic expect_request);integer window_index,cycle_index;begin
    rst_ni=0;active_mode_i=start_mode;clear_events();repeat(2)tick();rst_ni=1;tick();
    for(window_index=0;window_index<3;window_index=window_index+1)
      for(cycle_index=0;cycle_index<WINDOW_CYCLES;cycle_index=cycle_index+1)begin
        drive_cycle(profile,cycle_index);tick();
      end
    clear_events();
    if(window_index_o!=3||window_winner_o!==expected_winner)
      $fatal(1,"profile %0d winner mismatch index=%0d winner=%0d",profile,window_index_o,window_winner_o);
    if(recommendation_valid_o!==expect_request)
      $fatal(1,"profile %0d request-valid mismatch",profile);
    if(expect_request&&recommendation_mode_o!==expected_winner)
      $fatal(1,"profile %0d recommendation mismatch",profile);
    check_counts(profile);
    case(profile)
      0:$display("ADVISOR_MATRIX class=G active=%0d winner=%0d recommended=%0d valid=%0d window=%0d group=%0d sort=%0d projection=%0d raster=%0d block=%0d skip=%0d",
        start_mode,window_winner_o,recommendation_mode_o,recommendation_valid_o,window_index_o,
        window_group_count_o,window_sort_count_o,window_projection_count_o,window_raster_count_o,
        window_block_count_o,window_skip_count_o);
      1:$display("ADVISOR_MATRIX class=P active=%0d winner=%0d recommended=%0d valid=%0d window=%0d group=%0d sort=%0d projection=%0d raster=%0d block=%0d skip=%0d",
        start_mode,window_winner_o,recommendation_mode_o,recommendation_valid_o,window_index_o,
        window_group_count_o,window_sort_count_o,window_projection_count_o,window_raster_count_o,
        window_block_count_o,window_skip_count_o);
      2:$display("ADVISOR_MATRIX class=R active=%0d winner=%0d recommended=%0d valid=%0d window=%0d group=%0d sort=%0d projection=%0d raster=%0d block=%0d skip=%0d",
        start_mode,window_winner_o,recommendation_mode_o,recommendation_valid_o,window_index_o,
        window_group_count_o,window_sort_count_o,window_projection_count_o,window_raster_count_o,
        window_block_count_o,window_skip_count_o);
      3:$display("ADVISOR_MATRIX class=E active=%0d winner=%0d recommended=%0d valid=%0d window=%0d group=%0d sort=%0d projection=%0d raster=%0d block=%0d skip=%0d",
        start_mode,window_winner_o,recommendation_mode_o,recommendation_valid_o,window_index_o,
        window_group_count_o,window_sort_count_o,window_projection_count_o,window_raster_count_o,
        window_block_count_o,window_skip_count_o);
      default:$display("ADVISOR_MATRIX class=BALANCED active=%0d winner=%0d recommended=%0d valid=%0d window=%0d group=%0d sort=%0d projection=%0d raster=%0d block=%0d skip=%0d",
        start_mode,window_winner_o,recommendation_mode_o,recommendation_valid_o,window_index_o,
        window_group_count_o,window_sort_count_o,window_projection_count_o,window_raster_count_o,
        window_block_count_o,window_skip_count_o);
    endcase
  end endtask

  initial begin
    run_profile(0,MODE_P,MODE_G,1);
    run_profile(1,MODE_G,MODE_P,1);
    run_profile(2,MODE_G,MODE_R,1);
    run_profile(3,MODE_G,MODE_E,1);
    run_profile(4,MODE_G,MODE_G,0);
    $display("PASS: tb_gaussian_mode_advisor_workload_matrix");$finish;
  end
endmodule
