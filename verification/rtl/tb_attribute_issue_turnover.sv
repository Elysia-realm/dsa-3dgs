`timescale 1ns/1ps
`ifndef TB_ATTR_TURNOVER
`define TB_ATTR_TURNOVER 1
`endif
`ifndef TB_ATTR_RESPONSE_BYPASS
`define TB_ATTR_RESPONSE_BYPASS 1
`endif
module tb_attribute_issue_turnover;
  logic clk_i=0,rst_ni=0,clear_errors_i=0;
  logic s_valid_i=0,s_ready_o;logic signed[15:0]s_depth_i;logic[7:0]s_gid_i,s_seq_i;
  logic[1:0]s_group_i;logic s_group_first_i,s_group_last_i;
  logic attr_req_valid_o,attr_req_ready_i;logic[7:0]attr_req_gid_o;
  logic attr_rsp_valid_i=0,attr_rsp_ready_o,attr_rsp_in_range_i=1,attr_rsp_loaded_i=1,attr_rsp_error_i=0;
  logic[31:0]attr_rsp_data_i=0,m_attr_data_o;logic m_valid_o,m_ready_i;
  logic signed[15:0]m_depth_o;logic[7:0]m_gid_o,m_seq_o;logic[1:0]m_group_o;
  logic m_group_first_o,m_group_last_o,invalid_gid_sticky_o,unloaded_gid_sticky_o,backend_error_sticky_o,read_pulse_o,idle_o;
  logic stress=0,backend_pending=0,held_req=0,held_out=0;
  logic[7:0]backend_gid=0,previous_req=0;
  logic[67:0]previous_out;
  logic[31:0]rng=32'h83ca47d1;
  integer accepted=0,retired=0,expected=0,cycles=0,turnovers=0,delay=-1,requests=0,bypasses=0;
  always#5 clk_i=~clk_i;
  assign attr_req_ready_i=!backend_pending&&!attr_rsp_valid_i&&(!stress||rng[3]||rng[4]);
  assign m_ready_i=!stress||rng[7];
  ordered_gaussian_attribute_issue #(.GID_W(8),.SEQ_W(8),.DEPTH_W(16),.ATTR_W(32),
    .ENABLE_OUTPUT_TURNOVER(`TB_ATTR_TURNOVER),.ENABLE_RESPONSE_BYPASS(`TB_ATTR_RESPONSE_BYPASS))dut(.*);
  always@(negedge clk_i)begin
    s_valid_i=rst_ni&&accepted<128;s_gid_i=8'(accepted);s_seq_i=8'(accepted);
    s_depth_i=16'(-accepted*3);s_group_i=2'(accepted%4);s_group_first_i=accepted%4==0;s_group_last_i=accepted%4==3;
  end
  always@(posedge clk_i)begin
    if(!rst_ni)begin backend_pending<=0;attr_rsp_valid_i<=0;held_req<=0;held_out<=0;delay<=-1;end
    else begin
      cycles<=cycles+1;rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
      if(held_req&&(!attr_req_valid_o||previous_req!==attr_req_gid_o))$fatal(1,"stalled attribute request changed");
      if(held_out&&(!m_valid_o||previous_out!=={m_depth_o,m_gid_o,m_seq_o,m_group_o,m_group_first_o,m_group_last_o,m_attr_data_o}))$fatal(1,"stalled attribute output changed");
      held_req<=attr_req_valid_o&&!attr_req_ready_i;previous_req<=attr_req_gid_o;
      held_out<=m_valid_o&&!m_ready_i;previous_out<={m_depth_o,m_gid_o,m_seq_o,m_group_o,m_group_first_o,m_group_last_o,m_attr_data_o};
      if(attr_req_valid_o&&attr_req_ready_i)begin
        if(backend_pending||attr_rsp_valid_i||attr_req_gid_o!==8'(accepted)||!s_ready_o)$fatal(1,"request ordering/outstanding contract violated");
        accepted<=accepted+1;requests<=requests+1;backend_pending<=1;backend_gid<=attr_req_gid_o;
        delay<=stress?int'(rng[11:9]):0;
        if(m_valid_o&&m_ready_i)turnovers<=turnovers+1;
      end else if(backend_pending&&!attr_rsp_valid_i)begin
        if(delay>0)delay<=delay-1;
        else begin
          attr_rsp_valid_i<=1;attr_rsp_data_i<=32'h923f16ac^32'(backend_gid);
          attr_rsp_error_i<=int'(backend_gid)%17==16&&(int'(backend_gid)/17)%3==0;
          attr_rsp_in_range_i<=!(int'(backend_gid)%17==16&&(int'(backend_gid)/17)%3==1);
          attr_rsp_loaded_i<=!(int'(backend_gid)%17==16&&(int'(backend_gid)/17)%3==2);
        end
      end
      if(attr_rsp_valid_i&&attr_rsp_ready_o)begin attr_rsp_valid_i<=0;backend_pending<=0;end
      if(m_valid_o&&m_ready_i)begin
        if(dut.response_bypass)bypasses<=bypasses+1;
        while(expected%17==16)expected=expected+1;
        if({m_depth_o,m_gid_o,m_seq_o,m_group_o,m_group_first_o,m_group_last_o,m_attr_data_o}!==
          {16'(-expected*3),8'(expected),8'(expected),2'(expected%4),1'(expected%4==0),1'(expected%4==3),(32'h923f16ac^32'(expected))})
          $fatal(1,"attribute result mismatch expected=%0d gid=%0d",expected,m_gid_o);
        expected=expected+1;retired<=retired+1;
      end
    end
  end
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  initial begin
    for(integer phase=0;phase<2;phase=phase+1)begin
      rst_ni=0;stress=phase!=0;repeat(2)tick();accepted=0;retired=0;expected=0;cycles=0;turnovers=0;requests=0;bypasses=0;rng=32'h83ca47d1;rst_ni=1;
      for(integer timeout=0;!(accepted==128&&idle_o&&!backend_pending&&!attr_rsp_valid_i)&&timeout<20000;timeout=timeout+1)tick();
      if(accepted!=128||requests!=128||retired!=121||!idle_o||!invalid_gid_sticky_o||!unloaded_gid_sticky_o||!backend_error_sticky_o)$fatal(1,"attribute stream incomplete/errors missing");
      if(`TB_ATTR_TURNOVER&&!`TB_ATTR_RESPONSE_BYPASS&&turnovers==0)$fatal(1,"attribute turnover not exercised");
      if(`TB_ATTR_RESPONSE_BYPASS&&bypasses==0)$fatal(1,"attribute response bypass not exercised");
      if(!`TB_ATTR_TURNOVER&&turnovers!=0)$fatal(1,"disabled attribute turnover exercised");
      $display("ATTR_STREAM turnover=%0d bypass=%0d stress=%0d requests=%0d outputs=%0d rejected=7 cycles=%0d turnovers=%0d bypasses=%0d",`TB_ATTR_TURNOVER,`TB_ATTR_RESPONSE_BYPASS,phase,requests,retired,cycles,turnovers,bypasses);
      clear_errors_i=1;tick();clear_errors_i=0;
      if(invalid_gid_sticky_o||unloaded_gid_sticky_o||backend_error_sticky_o)$fatal(1,"attribute errors not cleared");
    end
    $display("PASS: tb_attribute_issue_turnover");$finish;
  end
endmodule
