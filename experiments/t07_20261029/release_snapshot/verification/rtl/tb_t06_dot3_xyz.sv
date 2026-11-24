`timescale 1ns/1ps
`ifndef TB_XYZ_TURNOVER
`define TB_XYZ_TURNOVER 1
`endif
`ifndef TB_XYZ_FIRST_REQUEST_BYPASS
`define TB_XYZ_FIRST_REQUEST_BYPASS 1
`endif
`ifndef TB_XYZ_STREAMING
`define TB_XYZ_STREAMING 0
`endif
module tb_t06_dot3_xyz;
  logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o,g_ready;
  logic[15:0]s_meta_i=0,m_meta_o,g_meta;
  logic signed[26:0]s_world_x_q16_i=0,s_world_y_q16_i=0,s_world_z_q16_i=0;
  logic signed[21:0]cfg_r00_q20_i=1048576,cfg_r01_q20_i=0,cfg_r02_q20_i=0;
  logic signed[21:0]cfg_r10_q20_i=0,cfg_r11_q20_i=1048576,cfg_r12_q20_i=0;
  logic signed[21:0]cfg_r20_q20_i=0,cfg_r21_q20_i=0,cfg_r22_q20_i=1048576;
  logic signed[26:0]cfg_tx_q16_i=0,cfg_ty_q16_i=0,cfg_tz_q16_i=0;
  logic m_valid_o,m_ready_i,g_valid,g_sink,sink_ready,busy_o,m_overflow_o,g_overflow;
  logic signed[26:0]m_camera_x_q16_o,m_camera_y_q16_o,m_camera_z_q16_o,g_x,g_y,g_z;
  logic pe_req_valid_o,pe_req_ready_i,pe_rsp_valid_i,pe_rsp_ready_o;
  logic signed[95:0]pe_lhs_o,pe_rhs_o;
  logic signed[64:0]pe_acc_o,pe_result_i;
  logic actual_ready,actual_rsp,p_grant,g_grant,p_stall;
  logic[31:0]rng=32'hb7c12569;
  integer compared=0,p_grants=0,g_grants=0,stalls=0,cycles=0;
  integer accepted=0,turnovers=0;
  integer first_grants=0,first_stalls=0;
  logic stream_mode=0,stress_enable=1;
  wire dut_valid=stream_mode?s_valid_i&&g_ready:s_valid_i;
  logic held_output=0,held_request=0;
  logic[97:0]previous_output;
  logic[256:0]previous_request;
  always#5 clk_i=~clk_i;
  always@(posedge clk_i)if(rst_ni)begin
    rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};cycles<=cycles+1;
    if(p_grant)p_grants<=p_grants+1;if(g_grant)g_grants<=g_grants+1;if(p_stall)stalls<=stalls+1;
    if(stream_mode&&dut_valid&&s_ready_o)accepted<=accepted+1;
    if(dut_valid&&s_ready_o&&m_valid_o&&m_ready_i)turnovers<=turnovers+1;
    if(dut.first_launch)begin
      if(pe_req_ready_i)first_grants<=first_grants+1;
      else first_stalls<=first_stalls+1;
    end
  end
  always@(posedge clk_i)begin
    if(!rst_ni)begin held_output<=0;held_request<=0;end
    else begin
      if(held_output&&(!m_valid_o||previous_output!=={m_meta_o,m_camera_x_q16_o,m_camera_y_q16_o,m_camera_z_q16_o,m_overflow_o}))$fatal(1,"XYZ stalled output changed");
      if(held_request&&(!pe_req_valid_o||previous_request!=={pe_lhs_o,pe_rhs_o,pe_acc_o}))$fatal(1,"XYZ stalled request changed");
      held_output<=m_valid_o&&!m_ready_i;
      previous_output<={m_meta_o,m_camera_x_q16_o,m_camera_y_q16_o,m_camera_z_q16_o,m_overflow_o};
      held_request<=pe_req_valid_o&&!pe_req_ready_i;previous_request<={pe_lhs_o,pe_rhs_o,pe_acc_o};
    end
  end
  always@(negedge clk_i)if(stream_mode)begin
    s_valid_i=rst_ni&&accepted<128;s_meta_i=16'(accepted);
    s_world_x_q16_i=accepted%2?27'sh3ffffff:27'sh4000000;
    s_world_y_q16_i=27'(accepted*39797);s_world_z_q16_i=27'(-accepted*75431);
    cfg_r00_q20_i=22'(accepted*139871);cfg_r01_q20_i=22'(-accepted*213763);cfg_r02_q20_i=22'(accepted*73939);
    cfg_r10_q20_i=22'(-accepted*337319);cfg_r11_q20_i=22'(accepted*56311);cfg_r12_q20_i=22'(accepted*92317);
    cfg_r20_q20_i=22'(accepted*72341);cfg_r21_q20_i=22'(-accepted*87119);cfg_r22_q20_i=22'(accepted*141973);
    cfg_tx_q16_i=27'(-accepted*29173);cfg_ty_q16_i=27'(accepted*65713);cfg_tz_q16_i=27'(-accepted*73127);
  end
  assign sink_ready=!stress_enable||rng[3]||rng[5];
  assign m_ready_i=g_valid&&sink_ready;assign g_sink=m_valid_o&&sink_ready;
  assign pe_req_ready_i=actual_ready&&(!stress_enable||rng[6]);
  assign pe_rsp_valid_i=actual_rsp&&(!stress_enable||rng[7]);
  world_to_camera_shared_mac #(.META_W(16),.PE_DATA_W(96),.PE_RESULT_W(65),.USE_DOT3(1),.ENABLE_OUTPUT_TURNOVER(`TB_XYZ_TURNOVER),
    .ENABLE_FIRST_REQUEST_BYPASS(`TB_XYZ_FIRST_REQUEST_BYPASS))dut(.s_valid_i(dut_valid),.*);
  world_to_camera_core #(.META_W(16))golden(
    .s_valid_i(stream_mode?s_valid_i&&s_ready_o:s_valid_i),
    .s_ready_o(g_ready),.m_valid_o(g_valid),.m_ready_i(g_sink),.m_meta_o(g_meta),
    .m_camera_x_q16_o(g_x),.m_camera_y_q16_o(g_y),.m_camera_z_q16_o(g_z),.m_overflow_o(g_overflow),.*);
  shared_reconfigurable_pe_slice #(.DATA_W(96),.P_DOT3(1),.GID_W(8),.SEQ_W(8),.RESULT_W(65))pe(
    .clk_i(clk_i),.rst_ni(rst_ni),.group_weight_i(3'd4),.projection_weight_i(3'd1),.raster_weight_i(3'd1),
    .shared_owner_i(2'd0),.aggressive_clock_gate_i(1'b0),.reconfigure_i(1'b0),
    .g_valid_i(stress_enable&&rng[0]),.g_ready_o(),.g_op_mac_i(1'b0),.g_lhs_i(32'sd1),.g_rhs_i(32'sd2),.g_acc_i(65'sd0),
    .g_lhs_gid_i(8'd0),.g_rhs_gid_i(8'd0),.g_lhs_seq_i(8'd0),.g_rhs_seq_i(8'd0),
    .g_rsp_valid_o(),.g_rsp_ready_i(rng[1]||rng[2]),.g_result_o(),.g_less_o(),
    .p_valid_i(pe_req_valid_o&&(!stress_enable||rng[6])),.p_ready_o(actual_ready),.p_op_mac_i(1'b1),
    .p_lhs_i(pe_lhs_o),.p_rhs_i(pe_rhs_o),.p_acc_i(pe_acc_o),
    .p_lhs_gid_i(8'd0),.p_rhs_gid_i(8'd0),.p_lhs_seq_i(8'd0),.p_rhs_seq_i(8'd0),
    .p_rsp_valid_o(actual_rsp),.p_rsp_ready_i(pe_rsp_ready_o&&(!stress_enable||rng[7])),.p_result_o(pe_result_i),.p_less_o(),
    .r_valid_i(1'b0),.r_ready_o(),.r_op_mac_i(1'b0),.r_lhs_i(32'sd0),.r_rhs_i(32'sd0),.r_acc_i(65'sd0),
    .r_lhs_gid_i(8'd0),.r_rhs_gid_i(8'd0),.r_lhs_seq_i(8'd0),.r_rhs_seq_i(8'd0),
    .r_rsp_valid_o(),.r_rsp_ready_i(1'b1),.r_result_o(),.r_less_o(),
    .group_grant_pulse_o(g_grant),.projection_grant_pulse_o(p_grant),.raster_grant_pulse_o(),
    .group_stall_o(),.projection_stall_o(p_stall),.raster_stall_o(),.utilization_pulse_o(),.clock_enable_o(),.busy_o());
  always@(posedge clk_i)if(rst_ni&&m_valid_o&&g_valid&&sink_ready)begin
    if({m_meta_o,m_camera_x_q16_o,m_camera_y_q16_o,m_camera_z_q16_o,m_overflow_o}!==
       {g_meta,g_x,g_y,g_z,g_overflow})
      $fatal(1,"shared XYZ mismatch meta=%0d xyz=%0d/%0d/%0d vs %0d/%0d/%0d ov=%b/%b",
        m_meta_o,m_camera_x_q16_o,m_camera_y_q16_o,m_camera_z_q16_o,g_x,g_y,g_z,m_overflow_o,g_overflow);
    compared<=compared+1;
  end
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic random_input;
    begin
      s_world_x_q16_i=$signed(rng[26:0]);tick();s_world_y_q16_i=$signed(rng[26:0]);tick();
      s_world_z_q16_i=$signed(rng[26:0]);tick();
      cfg_r00_q20_i=$signed(rng[21:0]);tick();cfg_r01_q20_i=$signed(rng[21:0]);tick();cfg_r02_q20_i=$signed(rng[21:0]);tick();
      cfg_r10_q20_i=$signed(rng[21:0]);tick();cfg_r11_q20_i=$signed(rng[21:0]);tick();cfg_r12_q20_i=$signed(rng[21:0]);tick();
      cfg_r20_q20_i=$signed(rng[21:0]);tick();cfg_r21_q20_i=$signed(rng[21:0]);tick();cfg_r22_q20_i=$signed(rng[21:0]);tick();
      cfg_tx_q16_i=$signed(rng[26:0]);tick();cfg_ty_q16_i=$signed(rng[26:0]);tick();cfg_tz_q16_i=$signed(rng[26:0]);
    end
  endtask
  task automatic send(input integer id);
    integer timeout;
    begin
      while(!s_ready_o||!g_ready)tick();s_meta_i=16'(id);s_valid_i=1;tick();s_valid_i=0;
      // Inputs/config may move after acceptance; both implementations must
      // retain the accepted transform and metadata while arbitration stalls.
      random_input();timeout=0;
      while(compared<id+1&&timeout<1000)begin tick();timeout=timeout+1;end
      if(compared!=id+1)$fatal(1,"XYZ differential timeout id=%0d",id);
    end
  endtask
  initial begin
    if(`TB_XYZ_STREAMING)begin
      for(integer phase=0;phase<2;phase=phase+1)begin
        rst_ni=0;stream_mode=1;stress_enable=phase!=0;
        repeat(2)tick();accepted=0;compared=0;p_grants=0;g_grants=0;stalls=0;cycles=0;turnovers=0;first_grants=0;first_stalls=0;rng=32'hb7c12569;
        rst_ni=1;
        for(integer timeout=0;compared<128&&timeout<20000;timeout=timeout+1)tick();
        if(compared!=128||accepted!=128||p_grants!=384||busy_o)$fatal(1,"XYZ stream incomplete");
        if(`TB_XYZ_TURNOVER&&turnovers==0)$fatal(1,"output turnover not exercised");
        if(!`TB_XYZ_TURNOVER&&turnovers!=0)$fatal(1,"disabled turnover still exercised");
        if(`TB_XYZ_FIRST_REQUEST_BYPASS&&(first_grants+first_stalls!=128||(phase==1&&first_stalls==0)))$fatal(1,"first request retry coverage absent");
        if(!`TB_XYZ_FIRST_REQUEST_BYPASS&&(first_grants!=0||first_stalls!=0))$fatal(1,"disabled first request still exercised");
        $display("XYZ_STREAM turnover=%0d bypass=%0d stress=%0d vectors=%0d P=%0d G=%0d stalls=%0d cycles=%0d turnovers=%0d first_grants=%0d first_stalls=%0d",`TB_XYZ_TURNOVER,`TB_XYZ_FIRST_REQUEST_BYPASS,phase,compared,p_grants,g_grants,stalls,cycles,turnovers,first_grants,first_stalls);
      end
      $display("PASS: tb_t06_dot3_xyz streaming");$finish;
    end
    repeat(2)tick();rst_ni=1;tick();
    cfg_tx_q16_i=65536;cfg_ty_q16_i=-131072;cfg_tz_q16_i=196608;
    s_world_x_q16_i=65536;s_world_y_q16_i=262144;s_world_z_q16_i=327680;send(0);
    cfg_r00_q20_i=1;cfg_r11_q20_i=1;cfg_r22_q20_i=1;
    cfg_r01_q20_i=0;cfg_r02_q20_i=0;cfg_r10_q20_i=0;cfg_r12_q20_i=0;cfg_r20_q20_i=0;cfg_r21_q20_i=0;
    cfg_tx_q16_i=0;cfg_ty_q16_i=0;cfg_tz_q16_i=0;
    s_world_x_q16_i=524288;s_world_y_q16_i=-524288;s_world_z_q16_i=0;send(1);
    for(int id=2;id<258;id++)begin random_input();send(id);end
    if(p_grants!=3*258||g_grants==0||stalls==0||busy_o)
      $fatal(1,"shared XYZ activity accounting P/G/stall=%0d/%0d/%0d",p_grants,g_grants,stalls);
    $display("PASS: tb_t06_dot3_xyz vectors=%0d P=%0d G=%0d stalls=%0d cycles=%0d",
      compared,p_grants,g_grants,stalls,cycles);$finish;
  end
endmodule
