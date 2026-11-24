`timescale 1ns/1ps
module tb_view_direction_normalizer;
  localparam META_W=8,COORD_W=27;
  logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o;
  logic[META_W-1:0]s_meta_i='0;logic signed[COORD_W-1:0]s_dx_q16_i='0,s_dy_q16_i='0,s_dz_q16_i='0;
  logic m_valid_o,m_ready_i=1;logic[META_W-1:0]m_meta_o;
  logic signed[21:0]m_x_q20_o,m_y_q20_o,m_z_q20_o;logic m_zero_fallback_o,m_numeric_overflow_o;
  always#5 clk_i=~clk_i;
  view_direction_normalizer #(.META_W(META_W),.COORD_W(COORD_W))dut(.*);
  task automatic tick;begin @(posedge clk_i);#1;end endtask
  task automatic check_close(input integer got,exp,tol,input[31:0]label);begin
    if(got<exp-tol||got>exp+tol)$fatal(1,"%s got=%0d expected=%0d",label,got,exp);
  end endtask
  task automatic send_check(input[7:0]meta,input integer dx,dy,dz,ex,ey,ez,input logic fallback);
    integer timeout;begin
      while(!s_ready_o)tick();s_meta_i=meta;s_dx_q16_i=dx;s_dy_q16_i=dy;s_dz_q16_i=dz;s_valid_i=1;tick();s_valid_i=0;
      timeout=0;while(!m_valid_o&&timeout<100)begin tick();timeout=timeout+1;end
      if(!m_valid_o)$fatal(1,"normalizer timeout");
      if(m_meta_o!==meta||m_zero_fallback_o!==fallback||m_numeric_overflow_o)
        $fatal(1,"normalizer metadata/flag mismatch meta=%h fallback=%b overflow=%b",m_meta_o,m_zero_fallback_o,m_numeric_overflow_o);
      check_close(m_x_q20_o,ex,2,"x");check_close(m_y_q20_o,ey,2,"y");check_close(m_z_q20_o,ez,2,"z");tick();
    end endtask
  initial begin
    repeat(2)tick();rst_ni=1;tick();
    send_check(8'h31,3*65536,4*65536,0,629145,838860,0,0);
    send_check(8'h32,0,0,-2*65536,0,0,-1048576,0);
    send_check(8'h33,0,0,0,0,0,1048576,1);
    // The registered divider result must remain stable through output backpressure.
    while(!s_ready_o)tick();s_meta_i=8'h44;s_dx_q16_i=65536;s_dy_q16_i=0;s_dz_q16_i=0;s_valid_i=1;tick();s_valid_i=0;
    m_ready_i=0;while(!m_valid_o)tick();repeat(3)begin
      if(m_meta_o!==8'h44||m_x_q20_o!==22'sd1048576||m_y_q20_o!==0||m_z_q20_o!==0)
        $fatal(1,"normalizer changed under backpressure");tick();end
    m_ready_i=1;tick();$display("PASS: tb_view_direction_normalizer");$finish;
  end
endmodule
