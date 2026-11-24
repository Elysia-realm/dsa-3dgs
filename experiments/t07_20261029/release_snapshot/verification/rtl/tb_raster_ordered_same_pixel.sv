`timescale 1ns/1ps
`ifndef TB_ALPHA_ZERO_SKIP
`define TB_ALPHA_ZERO_SKIP 0
`endif
module tb_raster_ordered_same_pixel;
  localparam LANES=4;logic clk_i=0,rst_ni=0;logic[2:0]cfg_active_lanes_i=4;logic task_valid_i=0,task_ready_o;
  logic[31:0]task_id_i=0;logic[23:0]block_id_i=24'h44;logic[31:0]gid_i=0;logic[15:0]epoch_id_i=1;logic[11:0]pixel_id_i=12'd99;
  logic[5:0]pixel_in_block_i=0;logic[12:0]color_r_q12_i=4096,color_g_q12_i=0,color_b_q12_i=0;
  logic signed[15:0]alpha_dx_q10_i=0,alpha_dy_q10_i=0;logic[14:0]alpha_l00_q12_i=4096,alpha_l11_q12_i=4096;
  logic signed[15:0]alpha_l10_q12_i=0;logic signed[5:0]alpha_coordinate_shift_i=0,alpha_factor_shift_i=0;logic[12:0]alpha_opacity_q12_i=2048;
  logic block_terminated_pulse_o,skipped_terminated_pulse_o,commit_valid_o,commit_ready_i=1;logic[31:0]commit_task_id_o;
  logic[23:0]commit_block_id_o;logic[31:0]commit_gid_o;logic[15:0]commit_epoch_id_o;logic[12:0]commit_alpha_q12_o;logic commit_pass_alpha_o;
  logic[11:0]commit_pixel_id_o;logic[12:0]commit_r_q12_o,commit_g_q12_o,commit_b_q12_o;logic[15:0]commit_t_q16_o;
  logic commit_newly_terminated_o;logic[1:0]result_occupancy_o;logic[LANES-1:0]active_mask_o;logic retire_wait_o,protocol_error_o,idle_o;
  logic state_miss_req_valid_o,state_miss_req_ready_i=0,state_miss_req_tag_o;
  logic state_miss_rsp_valid_i=0,state_miss_rsp_ready_o,state_miss_rsp_tag_i=0;
  logic[11:0]state_miss_req_pixel_id_o;logic state_miss_rsp_error_i=0;
  logic[127:0]state_miss_rsp_data_i=0;logic state_cache_error_o,state_cache_idle_o;
  always#5 clk_i=~clk_i;raster_pair_shell #(.LANES(LANES),.ENABLE_ALPHA_ZERO_SKIP(`TB_ALPHA_ZERO_SKIP))dut(.*,
    .r_pe_req_valid_o(),.r_pe_req_ready_i(1'b0),.r_pe_lhs_o(),.r_pe_rhs_o(),
    .r_pe_rsp_valid_i(1'b0),.r_pe_rsp_ready_o(),.r_pe_result_i(65'b0));
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic send(input integer id,input integer pixel,input integer red,input integer alpha);begin while(!task_ready_o)tick();task_id_i=id;gid_i=id;
    pixel_id_i=pixel;color_r_q12_i=red;alpha_opacity_q12_i=alpha;task_valid_i=1;tick();task_valid_i=0;end endtask
  initial begin integer expected,timeout;integer expected_r[1:5],expected_t[1:5];
    // Four consecutive tasks hit exactly the same pixel. Correct front-to-back
    // state after each alpha=0.5 contribution is deterministic.
    expected_r[1]=2048;expected_t[1]=32768;expected_r[2]=3072;expected_t[2]=16384;
    expected_r[3]=3584;expected_t[3]=8192;expected_r[4]=3840;expected_t[4]=4096;
    repeat(2)tick();rst_ni=1;tick();send(1,99,4096,2048);
    if(`TB_ALPHA_ZERO_SKIP)send(6,99,4096,0);
    send(2,99,4096,2048);
    if(`TB_ALPHA_ZERO_SKIP)send(7,99,4096,15);
    send(3,99,4096,2048);send(4,99,4096,2048);
    // A different pixel follows; it must still see clear state despite alpha
    // work overlapping in the replicated lanes.
    if(`TB_ALPHA_ZERO_SKIP)send(8,100,2048,0);
    send(5,100,2048,2048);expected=1;timeout=0;
    while(expected<=5&&timeout<150)begin commit_ready_i=(timeout%6!=3);
      if(commit_valid_o&&commit_ready_i)begin
        if(commit_task_id_o!==expected)$fatal(1,"stateful commit reordered got=%0d expected=%0d",commit_task_id_o,expected);
        if(expected<=4)begin
          if(commit_pixel_id_o!==99||commit_r_q12_o!==expected_r[expected]||commit_t_q16_o!==expected_t[expected])
            $fatal(1,"same-pixel RAW hazard failure n=%0d r=%0d t=%0d",expected,commit_r_q12_o,commit_t_q16_o);
        end else if(commit_pixel_id_o!==100||commit_r_q12_o!==1024||commit_t_q16_o!==32768)
          $fatal(1,"different-pixel clear-state failure");
        expected=expected+1;
      end tick();timeout=timeout+1;
    end
    if(expected!=6||protocol_error_o)$fatal(1,"ordered same-pixel timeout/protocol");timeout=0;while(!idle_o&&timeout<20)begin tick();timeout=timeout+1;end
    if(!idle_o)$fatal(1,"raster did not drain");
    if(`TB_ALPHA_ZERO_SKIP&&dut.alpha_skipped_count_q!==3)
      $fatal(1,"transparent interleaved tasks were not retired exactly once");
    $display("PASS: tb_raster_ordered_same_pixel");$finish;
  end
endmodule
