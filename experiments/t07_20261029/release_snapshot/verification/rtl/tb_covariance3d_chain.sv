`timescale 1ns/1ps
module tb_covariance3d_chain;
 localparam integer TESTS=4;
 logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o;logic[15:0]s_meta_i='0;
 logic signed[21:0]s_qw_q20_i=22'sd1048576,s_qx_q20_i=0,s_qy_q20_i=0,s_qz_q20_i=0;
 logic[23:0]s_scale_x_q20_i=24'd1048576,s_scale_y_q20_i=24'd2097152,s_scale_z_q20_i=24'd3145728;
 logic world_valid,world_ready;logic[15:0]world_meta;logic signed[40:0]wxx,wxy,wxz,wyy,wyz,wzz;logic world_ov;
 logic signed[21:0]cfg_r00_q20_i=0,cfg_r01_q20_i=22'sd1048576,cfg_r02_q20_i=0;
 logic signed[21:0]cfg_r10_q20_i=-22'sd1048576,cfg_r11_q20_i=0,cfg_r12_q20_i=0;
 logic signed[21:0]cfg_r20_q20_i=0,cfg_r21_q20_i=0,cfg_r22_q20_i=22'sd1048576;
 logic m_valid_o,m_ready_i=1;logic[15:0]m_meta_o;logic signed[40:0]cxx,cxy,cxz,cyy,cyz,czz;logic m_numeric_overflow_o;
 logic[15:0]expected_meta[0:TESTS-1];logic signed[40:0]expected_xx[0:TESTS-1],expected_xy[0:TESTS-1];
 logic signed[40:0]expected_xz[0:TESTS-1],expected_yy[0:TESTS-1],expected_yz[0:TESTS-1],expected_zz[0:TESTS-1];
 logic expected_ov[0:TESTS-1];integer accepted=0,received=0,cycles=0;
 always#5 clk_i=~clk_i;
 quaternion_scale_covariance_core #(.META_W(16))u_world(.clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i),.s_ready_o(s_ready_o),
 .s_meta_i(s_meta_i),.s_qw_q20_i(s_qw_q20_i),.s_qx_q20_i(s_qx_q20_i),.s_qy_q20_i(s_qy_q20_i),.s_qz_q20_i(s_qz_q20_i),
 .s_scale_x_q20_i(s_scale_x_q20_i),.s_scale_y_q20_i(s_scale_y_q20_i),.s_scale_z_q20_i(s_scale_z_q20_i),
 .m_valid_o(world_valid),.m_ready_i(world_ready),.m_meta_o(world_meta),.m_cov_xx_q16_o(wxx),.m_cov_xy_q16_o(wxy),
 .m_cov_xz_q16_o(wxz),.m_cov_yy_q16_o(wyy),.m_cov_yz_q16_o(wyz),.m_cov_zz_q16_o(wzz),.m_numeric_overflow_o(world_ov));
 covariance_view_rotate_core #(.META_W(16))u_view(.clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(world_valid),.s_ready_o(world_ready),
 .s_meta_i(world_meta),.s_cov_xx_q16_i(wxx),.s_cov_xy_q16_i(wxy),.s_cov_xz_q16_i(wxz),.s_cov_yy_q16_i(wyy),.s_cov_yz_q16_i(wyz),
 .s_cov_zz_q16_i(wzz),.s_numeric_overflow_i(world_ov),.cfg_r00_q20_i(cfg_r00_q20_i),.cfg_r01_q20_i(cfg_r01_q20_i),
 .cfg_r02_q20_i(cfg_r02_q20_i),.cfg_r10_q20_i(cfg_r10_q20_i),.cfg_r11_q20_i(cfg_r11_q20_i),.cfg_r12_q20_i(cfg_r12_q20_i),
 .cfg_r20_q20_i(cfg_r20_q20_i),.cfg_r21_q20_i(cfg_r21_q20_i),.cfg_r22_q20_i(cfg_r22_q20_i),.m_valid_o(m_valid_o),.m_ready_i(m_ready_i),
 .m_meta_o(m_meta_o),.m_cov_xx_q16_o(cxx),.m_cov_xy_q16_o(cxy),.m_cov_xz_q16_o(cxz),.m_cov_yy_q16_o(cyy),.m_cov_yz_q16_o(cyz),
 .m_cov_zz_q16_o(czz),.m_numeric_overflow_o(m_numeric_overflow_o));
 task automatic tick;begin@(posedge clk_i);#1;end endtask
 task automatic send(input logic[15:0]meta,input logic signed[21:0]qw,qx,qy,qz,
   input logic[23:0]sx,sy,sz,input logic signed[40:0]exx,exy,exz,eyy,eyz,ezz,input logic eov);
  begin
   while(!s_ready_o)tick();
   expected_meta[accepted]=meta;expected_xx[accepted]=exx;expected_xy[accepted]=exy;
   expected_xz[accepted]=exz;expected_yy[accepted]=eyy;expected_yz[accepted]=eyz;
   expected_zz[accepted]=ezz;expected_ov[accepted]=eov;
   s_meta_i=meta;s_qw_q20_i=qw;s_qx_q20_i=qx;s_qy_q20_i=qy;s_qz_q20_i=qz;
   s_scale_x_q20_i=sx;s_scale_y_q20_i=sy;s_scale_z_q20_i=sz;s_valid_i=1;
   accepted=accepted+1;tick();s_valid_i=0;
  end
 endtask
 always@(posedge clk_i)begin
  if(rst_ni&&m_valid_o&&m_ready_i)begin
   if(m_meta_o!==expected_meta[received]||m_numeric_overflow_o!==expected_ov[received]||
      (!expected_ov[received]&&(cxx!==expected_xx[received]||cxy!==expected_xy[received]||
      cxz!==expected_xz[received]||cyy!==expected_yy[received]||cyz!==expected_yz[received]||
      czz!==expected_zz[received])))
    $fatal(1,"3D covariance[%0d] mismatch meta=%h diag=%0d,%0d,%0d off=%0d,%0d,%0d ov=%b",
      received,m_meta_o,cxx,cyy,czz,cxy,cxz,cyz,m_numeric_overflow_o);
   received<=received+1;
  end
 end
 initial begin
  // Overflow must be evaluated after the same round-to-nearest operation used
  // by the datapath.  Exactly half an LSB beyond either signed limit is an
  // overflow, while one raw Q40 code below the boundary is still representable.
  if(u_world.rot_ov((47'sd8388607<<<20)+(47'sd1<<<19)-1))$fatal(1,"positive pre-round boundary flagged early");
  if(!u_world.rot_ov((47'sd8388607<<<20)+(47'sd1<<<19)))$fatal(1,"positive rounding overflow missed");
  if(u_world.rot_ov(-(47'sd8388608<<<20)-(47'sd1<<<19)+1))$fatal(1,"negative pre-round boundary flagged early");
  if(!u_world.rot_ov(-(47'sd8388608<<<20)-(47'sd1<<<19)))$fatal(1,"negative rounding overflow missed");
  if(u_view.is_ov((89'sd1099511627775<<<40)+(89'sd1<<<39)-1))$fatal(1,"view positive boundary flagged early");
  if(!u_view.is_ov((89'sd1099511627775<<<40)+(89'sd1<<<39)))$fatal(1,"view positive rounding overflow missed");
  if(u_view.is_ov(-(89'sd1099511627776<<<40)-(89'sd1<<<39)+1))$fatal(1,"view negative boundary flagged early");
  if(!u_view.is_ov(-(89'sd1099511627776<<<40)-(89'sd1<<<39)))$fatal(1,"view negative rounding overflow missed");
  repeat(2)tick();rst_ni=1;tick();
  // World diag(1,4,9), view 90-degree z rotation -> diag(4,1,9).
  send(16'hc301,22'sd1048576,0,0,0,24'd1048576,24'd2097152,24'd3145728,
    41'sd4194304,0,0,41'sd1048576,0,41'sd9437184,0);
  // q=(.5,.5,.5,.5) is an exact cyclic axis permutation. World diag is
  // (9,1,4); the fixed view rotation swaps x/y -> diag(1,9,4).
  send(16'hc302,22'sd524288,22'sd524288,22'sd524288,22'sd524288,
    24'd1048576,24'd2097152,24'd3145728,
    41'sd1048576,0,0,41'sd9437184,0,41'sd4194304,0);
  // Large legal isotropic scale remains invariant under both rotations.
  send(16'hc303,22'sd524288,22'sd524288,22'sd524288,22'sd524288,
    24'd15728640,24'd15728640,24'd15728640,
    41'sd235929600,0,0,41'sd235929600,0,41'sd235929600,0);
  // Deliberately non-normalized quaternion must be reported, never silent.
  send(16'hc304,22'sd2097151,22'sd2097151,22'sd2097151,22'sd2097151,
    24'd1048576,24'd1048576,24'd1048576,0,0,0,0,0,0,1);
  m_ready_i=0;repeat(5)tick();m_ready_i=1;
  while(received<TESTS&&cycles<100)begin
   m_ready_i=(cycles%4)!=1;tick();cycles=cycles+1;
  end
  if(received!=TESTS)$fatal(1,"3D covariance timeout received=%0d",received);
  m_ready_i=1;tick();$display("PASS: tb_covariance3d_chain transactions=%0d",received);$finish;
 end
endmodule
