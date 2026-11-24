`timescale 1ns/1ps
module tb_t06_dot3_pe;
  logic clk=0,rst=0;always #5 clk=~clk;
  integer tick=0,sent=0,received=0,g_count=0,r_count=0,held_count=0;
  logic pv,pr,ov,ready,gv,rv,gl;
  logic signed[95:0]lhs,rhs;
  logic signed[64:0]acc,result,rr;
  logic signed[63:0]p0,p1,p2;
  logic signed[64:0]expected[0:255];
  logic held=0;logic[64:0]saved;
  function automatic [31:0]word(input integer n,lane);
    case(n%5)
      0:word=32'h80000000;
      1:word=32'h7fffffff;
      2:word=32'hffffffff;
      default:word=32'(n*32'h9e3779b9+lane*32'h85ebca6b);
    endcase
  endfunction
  assign pv=sent<256;assign ready=tick%7<4;
  assign lhs={word(sent,2),word(sent,1),word(sent,0)};
  assign rhs={word(sent+1,4),word(sent+2,3),word(sent+3,2)};
  assign acc=sent%3==0?65'h0ffffffffffffffff:-65'(sent*1777);
  assign p0=$signed(lhs[31:0])*$signed(rhs[31:0]);
  assign p1=$signed(lhs[63:32])*$signed(rhs[63:32]);
  assign p2=$signed(lhs[95:64])*$signed(rhs[95:64]);
  shared_reconfigurable_pe_slice #(.DATA_W(96),.RESULT_W(65),.P_DOT3(1))dut(
    .clk_i(clk),.rst_ni(rst),.group_weight_i(3'd1),.projection_weight_i(3'd4),.raster_weight_i(3'd2),
    .shared_owner_i(2'd1),.aggressive_clock_gate_i(1'b0),.reconfigure_i(1'b0),
    .g_valid_i(1'b1),.g_ready_o(),.g_op_mac_i(1'b0),.g_lhs_i(-96'sd1),.g_rhs_i(96'sd1),.g_acc_i(65'd0),
    .g_lhs_gid_i(32'd0),.g_rhs_gid_i(32'd0),.g_lhs_seq_i(16'd0),.g_rhs_seq_i(16'd0),
    .g_rsp_valid_o(gv),.g_rsp_ready_i(tick%5!=1),.g_result_o(),.g_less_o(gl),
    .p_valid_i(pv),.p_ready_o(pr),.p_op_mac_i(1'b1),.p_lhs_i(lhs),.p_rhs_i(rhs),.p_acc_i(acc),
    .p_lhs_gid_i(32'd0),.p_rhs_gid_i(32'd0),.p_lhs_seq_i(16'd0),.p_rhs_seq_i(16'd0),
    .p_rsp_valid_o(ov),.p_rsp_ready_i(ready),.p_result_o(result),.p_less_o(),
    .r_valid_i(1'b1),.r_ready_o(),.r_op_mac_i(1'b1),.r_lhs_i(-96'sd123),.r_rhs_i(96'sd45),.r_acc_i(65'd7),
    .r_lhs_gid_i(32'd0),.r_rhs_gid_i(32'd0),.r_lhs_seq_i(16'd0),.r_rhs_seq_i(16'd0),
    .r_rsp_valid_o(rv),.r_rsp_ready_i(tick%3!=1),.r_result_o(rr),.r_less_o(),
    .group_grant_pulse_o(),.projection_grant_pulse_o(),.raster_grant_pulse_o(),
    .group_stall_o(),.projection_stall_o(),.raster_stall_o(),.utilization_pulse_o(),.clock_enable_o(),.busy_o());
  always@(posedge clk)if(rst)begin
    tick<=tick+1;
    if(pv&&pr)begin expected[sent]<=$signed({p0[63],p0})+$signed({p1[63],p1})+$signed({p2[63],p2})+acc;sent<=sent+1;end
    if(ov&&ready)begin if(result!==expected[received])$fatal(1,"dot3 mismatch %0d",received);received<=received+1;end
    if(gv&&tick%5!=1)begin if(!gl)$fatal(1,"G compare corrupted");g_count<=g_count+1;end
    if(rv&&tick%3!=1)begin if(rr!==-65'sd5528)$fatal(1,"R MAC corrupted");r_count<=r_count+1;end
    if(held&&(!ov||saved!==result))$fatal(1,"P stalled response changed");
    held<=ov&&!ready;saved<=result;if(held)held_count<=held_count+1;
    if(tick>10000)$fatal(1,"timeout");
    if(received==256)begin
      if(g_count==0||r_count==0||held_count==0)$fatal(1,"contention/stall coverage missing");
      $display("PASS DOT3_PE vectors=256 G=%0d R=%0d held=%0d cycles=%0d",g_count,r_count,held_count,tick);$finish;
    end
  end
  initial begin repeat(3)@(negedge clk);rst=1;end
endmodule
