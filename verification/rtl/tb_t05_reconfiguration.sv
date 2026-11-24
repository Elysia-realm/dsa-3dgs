`timescale 1ns/1ps
// Reuses the formal APB/camera/mean/attribute/RGB harness. Only the observation
// window is shortened so a small real-data frame can request a next-epoch mode.
module tb_t05_reconfiguration;
  tb_real_dma_workload base();
  defparam base.dut.MODE_ADVISOR_WINDOW_CYCLES=16;
  defparam base.dut.MODE_ADVISOR_HYSTERESIS_WINDOWS=1;
  defparam base.dut.MODE_ADVISOR_MIN_RESIDENCE_WINDOWS=1;
  defparam base.dut.MODE_ADVISOR_SCORE_MARGIN=1;
  logic[1:0]previous_mode=0;logic[15:0]previous_epoch=0;
  integer changes=0,pr_competition=0,gp_competition=0,gr_competition=0;
  always@(posedge base.clk_i)begin
    if(base.rst_ni)begin
      if(base.dut.u_frame.pe_p_req_valid&&base.dut.u_frame.pe_r_req_valid)pr_competition=pr_competition+1;
      if(base.dut.u_frame.pe_g_req_valid&&base.dut.u_frame.pe_p_req_valid)gp_competition=gp_competition+1;
      if(base.dut.u_frame.pe_g_req_valid&&base.dut.u_frame.pe_r_req_valid)gr_competition=gr_competition+1;
      #1;
      if(base.active_mode_o!=previous_mode)begin
        if(!base.dut.mode_commit_done||base.epoch_id_o==previous_epoch||base.dut.shared_pe_busy)
          $fatal(1,"unsafe mode change with in-flight PE response");
        changes=changes+1;
        $display("T05_MODE_CHANGE epoch=%0d old=%0d new=%0d G_lanes=%0d weights=%0d,%0d,%0d PE_busy=%0d",
          base.epoch_id_o,previous_mode,base.active_mode_o,base.dut.u_frame.group_active_lanes,
          base.dut.u_frame.group_weight,base.dut.u_frame.projection_weight,base.dut.u_frame.raster_weight,base.dut.shared_pe_busy);
      end
      previous_mode=base.active_mode_o;previous_epoch=base.epoch_id_o;
    end
  end
  final $display("T05_RESOURCE_PROBE changes=%0d GP=%0d PR=%0d GR=%0d",changes,gp_competition,pr_competition,gr_competition);
endmodule
