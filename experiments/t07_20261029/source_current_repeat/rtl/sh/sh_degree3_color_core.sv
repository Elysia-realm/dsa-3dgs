// Degree-3 real spherical-harmonic evaluator. One Gaussian is evaluated once
// and its RGB is reused for all internal 8x8 blocks. Direction is Q1.20,
// 48 channel-major coefficients are signed Q5.12, output RGB is unsigned Q1.12.
module sh_degree3_color_core #(
    parameter int unsigned META_W=32,
    parameter int unsigned DIR_W=22,
    parameter int unsigned COEFF_W=18,
    parameter int unsigned BASIS_W=32,
    parameter int unsigned COEFFS=16,
    parameter int unsigned CHANNELS=3,
    parameter int unsigned DATA_W=META_W+3*13+1
) (
    input logic clk_i,input logic rst_ni,
    input logic s_valid_i,output logic s_ready_o,input logic[META_W-1:0]s_meta_i,
    input logic signed[DIR_W-1:0]s_x_q20_i,s_y_q20_i,s_z_q20_i,
    input logic[CHANNELS*COEFFS*COEFF_W-1:0]s_coeff_q12_flat_i,
    input logic s_numeric_overflow_i,
    output logic m_valid_o,input logic m_ready_i,output logic[META_W-1:0]m_meta_o,
    output logic[12:0]m_r_q12_o,m_g_q12_o,m_b_q12_o,output logic m_numeric_overflow_o
);
    localparam logic signed[BASIS_W-1:0]C0=32'sd295798,C1=32'sd512337,C2=32'sd1145620;
    localparam logic signed[BASIS_W-1:0]C3=32'sd330712,C4=32'sd572810,C5=32'sd618706;
    localparam logic signed[BASIS_W-1:0]C6=32'sd3031026,C7=32'sd479247,C8=32'sd391304,C9=32'sd1515513;
    logic signed[BASIS_W-1:0]x,y,z,xx,yy,zz,xy,yz,xz;
    logic signed[BASIS_W-1:0]basis[0:COEFFS-1];logic signed[63:0]acc[0:CHANNELS-1];
    logic[12:0]color[0:CHANNELS-1];logic[DATA_W-1:0]result_data;integer c,k;
    function automatic logic signed[BASIS_W-1:0]mul_q20(
      input logic signed[BASIS_W-1:0]a,input logic signed[BASIS_W-1:0]b);
      logic signed[63:0]p,mag,rounded;begin p=a*b;
        if(p>=0)rounded=(p+64'sd524288)>>>20;
        else begin mag=-p;rounded=-((mag+64'sd524288)>>>20);end
        mul_q20=rounded[BASIS_W-1:0];end
    endfunction
    function automatic logic[12:0]encode_color(input logic signed[63:0]sum_q32);
      logic signed[63:0]biased,rounded;begin biased=sum_q32+64'sd2147483648;
        if(biased<=0)encode_color=13'd0;
        else begin rounded=(biased+64'sd524288)>>>20;
          if(rounded>=4096)encode_color=13'd4096;else encode_color=rounded[12:0];end end
    endfunction
    always_comb begin
      x={{(BASIS_W-DIR_W){s_x_q20_i[DIR_W-1]}},s_x_q20_i};
      y={{(BASIS_W-DIR_W){s_y_q20_i[DIR_W-1]}},s_y_q20_i};
      z={{(BASIS_W-DIR_W){s_z_q20_i[DIR_W-1]}},s_z_q20_i};
      xx=mul_q20(x,x);yy=mul_q20(y,y);zz=mul_q20(z,z);
      xy=mul_q20(x,y);yz=mul_q20(y,z);xz=mul_q20(x,z);
      basis[0]=C0;basis[1]=-mul_q20(C1,y);basis[2]=mul_q20(C1,z);basis[3]=-mul_q20(C1,x);
      basis[4]=mul_q20(C2,xy);basis[5]=-mul_q20(C2,yz);
      basis[6]=mul_q20(C3,(zz<<<1)-xx-yy);basis[7]=-mul_q20(C2,xz);basis[8]=mul_q20(C4,xx-yy);
      basis[9]=-mul_q20(C5,mul_q20(y,(xx+xx+xx)-yy));
      basis[10]=mul_q20(C6,mul_q20(xy,z));
      basis[11]=-mul_q20(C7,mul_q20(y,(zz<<<2)-xx-yy));
      basis[12]=mul_q20(C8,mul_q20(z,(zz<<<1)-(xx+xx+xx)-(yy+yy+yy)));
      basis[13]=-mul_q20(C7,mul_q20(x,(zz<<<2)-xx-yy));
      basis[14]=mul_q20(C9,mul_q20(z,xx-yy));
      basis[15]=-mul_q20(C5,mul_q20(x,xx-(yy+yy+yy)));
      for(c=0;c<CHANNELS;c=c+1)begin acc[c]='0;
        for(k=0;k<COEFFS;k=k+1)
          acc[c]=acc[c]+$signed(s_coeff_q12_flat_i[(c*COEFFS+k)*COEFF_W+:COEFF_W])*$signed(basis[k]);
        color[c]=encode_color(acc[c]);
      end
      result_data={s_meta_i,color[0],color[1],color[2],s_numeric_overflow_i};
    end
    rv_reg_slice #(.DATA_W(DATA_W))u_result(.clk_i(clk_i),.rst_ni(rst_ni),
      .s_valid_i(s_valid_i),.s_ready_o(s_ready_o),.s_data_i(result_data),
      .m_valid_o(m_valid_o),.m_ready_i(m_ready_i),
      .m_data_o({m_meta_o,m_r_q12_o,m_g_q12_o,m_b_q12_o,m_numeric_overflow_o}));
endmodule
