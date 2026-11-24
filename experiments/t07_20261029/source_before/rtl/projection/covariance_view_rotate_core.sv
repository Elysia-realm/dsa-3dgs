// Rotate a symmetric world-space covariance into camera space: V*Sigma*V^T.
// Covariance is signed Q20.20 and view rotation is signed Q2.20.  The two
// rotation multiplies add 40 fractional bits, so the output remains Q20.20.
module covariance_view_rotate_core #(
    parameter int unsigned META_W=64,
    parameter int unsigned COV_W=41,
    parameter int unsigned ROT_W=22
) (
    input logic clk_i,input logic rst_ni,input logic s_valid_i,output logic s_ready_o,
    input logic[META_W-1:0]s_meta_i,
    input logic signed[COV_W-1:0]s_cov_xx_q16_i,s_cov_xy_q16_i,s_cov_xz_q16_i,
    input logic signed[COV_W-1:0]s_cov_yy_q16_i,s_cov_yz_q16_i,s_cov_zz_q16_i,
    input logic s_numeric_overflow_i,
    input logic signed[ROT_W-1:0]cfg_r00_q20_i,cfg_r01_q20_i,cfg_r02_q20_i,
    input logic signed[ROT_W-1:0]cfg_r10_q20_i,cfg_r11_q20_i,cfg_r12_q20_i,
    input logic signed[ROT_W-1:0]cfg_r20_q20_i,cfg_r21_q20_i,cfg_r22_q20_i,
    output logic m_valid_o,input logic m_ready_i,output logic[META_W-1:0]m_meta_o,
    output logic signed[COV_W-1:0]m_cov_xx_q16_o,m_cov_xy_q16_o,m_cov_xz_q16_o,
    output logic signed[COV_W-1:0]m_cov_yy_q16_o,m_cov_yz_q16_o,m_cov_zz_q16_o,
    output logic m_numeric_overflow_o
);
 localparam P_W=COV_W+ROT_W;localparam T_W=P_W+2;
 localparam FINAL_P_W=T_W+ROT_W;localparam A_W=FINAL_P_W+2;
 localparam RESULT_W=META_W+6*COV_W+1;
 logic signed[P_W-1:0]p00,p01,p02,p10,p11,p12,p20,p21,p22;
 logic signed[P_W-1:0]p30,p31,p32,p40,p41,p42,p50,p51,p52;
 logic signed[T_W-1:0]t00,t01,t02,t10,t11,t12,t20,t21,t22;
 logic signed[A_W-1:0]c00w,c01w,c02w,c11w,c12w,c22w;
 logic signed[COV_W-1:0]c00,c01,c02,c11,c12,c22;logic ov;logic[RESULT_W-1:0]data;
 function automatic logic signed[T_W-1:0]sum3_p(
  input logic signed[P_W-1:0]a,b,c);
  begin sum3_p={{(T_W-P_W){a[P_W-1]}},a}+{{(T_W-P_W){b[P_W-1]}},b}
    +{{(T_W-P_W){c[P_W-1]}},c};end endfunction
 function automatic logic signed[FINAL_P_W-1:0]mul_t_rot(
  input logic signed[T_W-1:0]a,input logic signed[ROT_W-1:0]b);
  begin mul_t_rot=a*b;end endfunction
 function automatic logic signed[A_W-1:0]sum3_final(
  input logic signed[FINAL_P_W-1:0]a,b,c);
  begin sum3_final={{(A_W-FINAL_P_W){a[FINAL_P_W-1]}},a}
    +{{(A_W-FINAL_P_W){b[FINAL_P_W-1]}},b}
    +{{(A_W-FINAL_P_W){c[FINAL_P_W-1]}},c};end endfunction
 function automatic logic signed[A_W-1:0]round_view_value(input logic signed[A_W-1:0]v);
  logic signed[A_W-1:0]mag,bias;begin
   bias={{(A_W-40){1'b0}},1'b1,{39{1'b0}}};
   if(v>=0)round_view_value=(v+bias)>>>40;
   else begin mag=-v;round_view_value=-((mag+bias)>>>40);end
  end endfunction
 function automatic logic signed[COV_W-1:0]to_q16(input logic signed[A_W-1:0]v);
  begin to_q16=COV_W'(round_view_value(v));end endfunction
 function automatic logic is_ov(input logic signed[A_W-1:0]v);logic signed[A_W-1:0]sh,maxv,minv;
  begin sh=round_view_value(v);maxv=({{(A_W-1){1'b0}},1'b1}<<<(COV_W-1))-1;
  minv=-({{(A_W-1){1'b0}},1'b1}<<<(COV_W-1));is_ov=sh>maxv||sh<minv;end endfunction
 assign p00=cfg_r00_q20_i*s_cov_xx_q16_i;assign p01=cfg_r01_q20_i*s_cov_xy_q16_i;assign p02=cfg_r02_q20_i*s_cov_xz_q16_i;
 assign p10=cfg_r00_q20_i*s_cov_xy_q16_i;assign p11=cfg_r01_q20_i*s_cov_yy_q16_i;assign p12=cfg_r02_q20_i*s_cov_yz_q16_i;
 assign p20=cfg_r00_q20_i*s_cov_xz_q16_i;assign p21=cfg_r01_q20_i*s_cov_yz_q16_i;assign p22=cfg_r02_q20_i*s_cov_zz_q16_i;
 assign p30=cfg_r10_q20_i*s_cov_xx_q16_i;assign p31=cfg_r11_q20_i*s_cov_xy_q16_i;assign p32=cfg_r12_q20_i*s_cov_xz_q16_i;
 assign p40=cfg_r10_q20_i*s_cov_xy_q16_i;assign p41=cfg_r11_q20_i*s_cov_yy_q16_i;assign p42=cfg_r12_q20_i*s_cov_yz_q16_i;
 assign p50=cfg_r10_q20_i*s_cov_xz_q16_i;assign p51=cfg_r11_q20_i*s_cov_yz_q16_i;assign p52=cfg_r12_q20_i*s_cov_zz_q16_i;
 // Rows 0 and 1 of V*Sigma. Row 2 is formed directly in the final expressions.
 assign t00=sum3_p(p00,p01,p02);assign t01=sum3_p(p10,p11,p12);assign t02=sum3_p(p20,p21,p22);
 assign t10=sum3_p(p30,p31,p32);assign t11=sum3_p(p40,p41,p42);assign t12=sum3_p(p50,p51,p52);
 assign t20=sum3_p(cfg_r20_q20_i*s_cov_xx_q16_i,cfg_r21_q20_i*s_cov_xy_q16_i,cfg_r22_q20_i*s_cov_xz_q16_i);
 assign t21=sum3_p(cfg_r20_q20_i*s_cov_xy_q16_i,cfg_r21_q20_i*s_cov_yy_q16_i,cfg_r22_q20_i*s_cov_yz_q16_i);
 assign t22=sum3_p(cfg_r20_q20_i*s_cov_xz_q16_i,cfg_r21_q20_i*s_cov_yz_q16_i,cfg_r22_q20_i*s_cov_zz_q16_i);
 assign c00w=sum3_final(mul_t_rot(t00,cfg_r00_q20_i),mul_t_rot(t01,cfg_r01_q20_i),mul_t_rot(t02,cfg_r02_q20_i));
 assign c01w=sum3_final(mul_t_rot(t00,cfg_r10_q20_i),mul_t_rot(t01,cfg_r11_q20_i),mul_t_rot(t02,cfg_r12_q20_i));
 assign c02w=sum3_final(mul_t_rot(t00,cfg_r20_q20_i),mul_t_rot(t01,cfg_r21_q20_i),mul_t_rot(t02,cfg_r22_q20_i));
 assign c11w=sum3_final(mul_t_rot(t10,cfg_r10_q20_i),mul_t_rot(t11,cfg_r11_q20_i),mul_t_rot(t12,cfg_r12_q20_i));
 assign c12w=sum3_final(mul_t_rot(t10,cfg_r20_q20_i),mul_t_rot(t11,cfg_r21_q20_i),mul_t_rot(t12,cfg_r22_q20_i));
 assign c22w=sum3_final(mul_t_rot(t20,cfg_r20_q20_i),mul_t_rot(t21,cfg_r21_q20_i),mul_t_rot(t22,cfg_r22_q20_i));
 always_comb begin c00=to_q16(c00w);c01=to_q16(c01w);c02=to_q16(c02w);c11=to_q16(c11w);c12=to_q16(c12w);c22=to_q16(c22w);
  ov=is_ov(c00w)||is_ov(c01w)||is_ov(c02w)||is_ov(c11w)||is_ov(c12w)||is_ov(c22w);end
 assign data={s_meta_i,c00,c01,c02,c11,c12,c22,s_numeric_overflow_i||ov};
 rv_reg_slice #(.DATA_W(RESULT_W))u_result(.clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i),.s_ready_o(s_ready_o),.s_data_i(data),
 .m_valid_o(m_valid_o),.m_ready_i(m_ready_i),.m_data_o({m_meta_o,m_cov_xx_q16_o,m_cov_xy_q16_o,m_cov_xz_q16_o,m_cov_yy_q16_o,m_cov_yz_q16_o,m_cov_zz_q16_o,m_numeric_overflow_o}));
endmodule
