// Normalized quaternion and scale to symmetric world-space covariance.
// Quaternion: signed Q1.20 (w,x,y,z). Scale: unsigned Q4.20.
// Rotation and scaled rotation use Q*.20; covariance output is signed Q20.20.
module quaternion_scale_covariance_core #(
    parameter int unsigned META_W = 64,
    parameter int unsigned QUAT_W = 22,
    parameter int unsigned SCALE_W = 24,
    parameter int unsigned ROT_W = 24,
    parameter int unsigned SCALED_ROT_W = 28,
    parameter int unsigned COV_W = 41,
    parameter int unsigned FRAC_W = 20,
    parameter int unsigned COV_FRAC_W = 20
) (
    input logic cfg_cov_q24_i,
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic                         s_valid_i,
    output logic                         s_ready_o,
    input  logic [META_W-1:0]            s_meta_i,
    input  logic signed [QUAT_W-1:0]     s_qw_q20_i,
    input  logic signed [QUAT_W-1:0]     s_qx_q20_i,
    input  logic signed [QUAT_W-1:0]     s_qy_q20_i,
    input  logic signed [QUAT_W-1:0]     s_qz_q20_i,
    input  logic        [SCALE_W-1:0]    s_scale_x_q20_i,
    input  logic        [SCALE_W-1:0]    s_scale_y_q20_i,
    input  logic        [SCALE_W-1:0]    s_scale_z_q20_i,
    output logic                         m_valid_o,
    input  logic                         m_ready_i,
    output logic [META_W-1:0]            m_meta_o,
    output logic signed [COV_W-1:0]      m_cov_xx_q16_o,
    output logic signed [COV_W-1:0]      m_cov_xy_q16_o,
    output logic signed [COV_W-1:0]      m_cov_xz_q16_o,
    output logic signed [COV_W-1:0]      m_cov_yy_q16_o,
    output logic signed [COV_W-1:0]      m_cov_yz_q16_o,
    output logic signed [COV_W-1:0]      m_cov_zz_q16_o,
    output logic                         m_numeric_overflow_o
);
    localparam int unsigned QPROD_W = 2*QUAT_W;
    localparam int unsigned ROT_ACC_W = QPROD_W + 3;
    localparam int unsigned R_META_W = META_W + 3*SCALE_W + 1;
    localparam int unsigned R_DATA_W = R_META_W + 9*ROT_W;
    localparam int unsigned SR_PROD_W = ROT_W + SCALE_W + 1;
    localparam int unsigned CPROD_W = 2*SCALED_ROT_W;
    localparam int unsigned CACC_W = CPROD_W + 2;
    localparam int unsigned RESULT_W = META_W + 6*COV_W + 1;
    localparam int unsigned COV_SHIFT = 2*FRAC_W-COV_FRAC_W;
    localparam logic signed [ROT_ACC_W-1:0] ONE_Q40 = {
        {(ROT_ACC_W-(2*FRAC_W+1)){1'b0}},1'b1,{(2*FRAC_W){1'b0}}
    };

    logic signed [QPROD_W-1:0] xx,yy,zz,xy,xz,yz,wx,wy,wz;
    logic signed [ROT_ACC_W-1:0] r00_w,r01_w,r02_w,r10_w,r11_w,r12_w,r20_w,r21_w,r22_w;
    logic signed [ROT_W-1:0] r00,r01,r02,r10,r11,r12,r20,r21,r22;
    logic rotation_overflow;
    logic r_valid,r_ready;
    logic [R_META_W-1:0] r_meta;
    logic [META_W-1:0] meta_r;
    logic [SCALE_W-1:0] sx_r,sy_r,sz_r;
    logic rotation_overflow_r;
    logic signed [ROT_W-1:0] rr00,rr01,rr02,rr10,rr11,rr12,rr20,rr21,rr22;
    logic signed [SR_PROD_W-1:0] ms00_w,ms01_w,ms02_w,ms10_w,ms11_w,ms12_w,ms20_w,ms21_w,ms22_w;
    logic signed [SCALED_ROT_W-1:0] ms00,ms01,ms02,ms10,ms11,ms12,ms20,ms21,ms22;
    logic scaled_overflow;
    logic signed [CACC_W-1:0] cxx_w,cxy_w,cxz_w,cyy_w,cyz_w,czz_w;
    logic signed [COV_W-1:0] cxx,cxy,cxz,cyy,cyz,czz;
    logic covariance_overflow;
    logic [RESULT_W-1:0] result_data;

    function automatic logic signed [ROT_ACC_W-1:0] twice_qprod(
        input logic signed [QPROD_W-1:0] value
    );
        logic signed [ROT_ACC_W-1:0] extended;
        begin
            extended={{(ROT_ACC_W-QPROD_W){value[QPROD_W-1]}},value};
            twice_qprod=extended<<<1;
        end
    endfunction

    function automatic logic signed [ROT_ACC_W-1:0] round_rot_value(
        input logic signed [ROT_ACC_W-1:0] value
    );
        logic signed [ROT_ACC_W-1:0] magnitude;
        logic signed [ROT_ACC_W-1:0] bias;
        begin
            bias={{(ROT_ACC_W-FRAC_W){1'b0}},1'b1,{(FRAC_W-1){1'b0}}};
            if(value>=0)round_rot_value=(value+bias)>>>FRAC_W;
            else begin magnitude=-value;round_rot_value=-((magnitude+bias)>>>FRAC_W);end
        end
    endfunction

    function automatic logic signed [SR_PROD_W-1:0] round_scaled_value(
        input logic signed [SR_PROD_W-1:0] value
    );
        logic signed [SR_PROD_W-1:0] magnitude;
        logic signed [SR_PROD_W-1:0] bias;
        begin
            bias={{(SR_PROD_W-FRAC_W){1'b0}},1'b1,{(FRAC_W-1){1'b0}}};
            if(value>=0)round_scaled_value=(value+bias)>>>FRAC_W;
            else begin magnitude=-value;round_scaled_value=-((magnitude+bias)>>>FRAC_W);end
        end
    endfunction

    function automatic logic signed [CACC_W-1:0] round_cov_value_q20(
        input logic signed [CACC_W-1:0] value
    );
        logic signed [CACC_W-1:0] magnitude;
        logic signed [CACC_W-1:0] bias;
        begin
            bias={{(CACC_W-COV_SHIFT){1'b0}},1'b1,{(COV_SHIFT-1){1'b0}}};
            if(value>=0)round_cov_value_q20=(value+bias)>>>COV_SHIFT;
            else begin magnitude=-value;round_cov_value_q20=-((magnitude+bias)>>>COV_SHIFT);end
        end
    endfunction
    function automatic logic signed [CACC_W-1:0] round_cov_value_q24(
        input logic signed [CACC_W-1:0] value
    );
        logic signed [CACC_W-1:0] magnitude;
        logic signed [CACC_W-1:0] bias;
        begin
            bias={{(CACC_W-(COV_SHIFT-4)){1'b0}},1'b1,{((COV_SHIFT-4)-1){1'b0}}};
            if(value>=0)round_cov_value_q24=(value+bias)>>>(COV_SHIFT-4);
            else begin magnitude=-value;round_cov_value_q24=-((magnitude+bias)>>>(COV_SHIFT-4));end
        end
    endfunction
    function automatic logic signed [CACC_W-1:0] round_cov_value(
        input logic signed [CACC_W-1:0] value
    );
        round_cov_value = cfg_cov_q24_i ? round_cov_value_q24(value) : round_cov_value_q20(value);
    endfunction

    function automatic logic signed [ROT_W-1:0] q40_to_q20(
        input logic signed [ROT_ACC_W-1:0] value
    );
        begin
            q40_to_q20=ROT_W'(round_rot_value(value));
        end
    endfunction
    function automatic logic rot_ov(input logic signed [ROT_ACC_W-1:0] value);
        logic signed [ROT_ACC_W-1:0] rounded,maxv,minv;
        begin rounded=round_rot_value(value);maxv=({{(ROT_ACC_W-1){1'b0}},1'b1}<<<(ROT_W-1))-1;
        minv=-({{(ROT_ACC_W-1){1'b0}},1'b1}<<<(ROT_W-1));rot_ov=rounded>maxv||rounded<minv;end
    endfunction
    function automatic logic signed [SCALED_ROT_W-1:0] product_q40_to_q20(
        input logic signed [SR_PROD_W-1:0] value
    );
        begin product_q40_to_q20=SCALED_ROT_W'(round_scaled_value(value));end
    endfunction
    function automatic logic scaled_ov(input logic signed [SR_PROD_W-1:0] value);
        logic signed [SR_PROD_W-1:0] rounded,maxv,minv;
        begin rounded=round_scaled_value(value);maxv=({{(SR_PROD_W-1){1'b0}},1'b1}<<<(SCALED_ROT_W-1))-1;
        minv=-({{(SR_PROD_W-1){1'b0}},1'b1}<<<(SCALED_ROT_W-1));scaled_ov=rounded>maxv||rounded<minv;end
    endfunction
    function automatic logic signed [COV_W-1:0] cov_q40_to_q16(
        input logic signed [CACC_W-1:0] value
    );
        begin cov_q40_to_q16=COV_W'(round_cov_value(value));end
    endfunction
    function automatic logic cov_ov(input logic signed [CACC_W-1:0] value);
        logic signed [CACC_W-1:0] rounded,maxv,minv;
        begin rounded=round_cov_value(value);maxv=({{(CACC_W-1){1'b0}},1'b1}<<<(COV_W-1))-1;
        minv=-({{(CACC_W-1){1'b0}},1'b1}<<<(COV_W-1));cov_ov=rounded>maxv||rounded<minv;end
    endfunction

    assign xx=s_qx_q20_i*s_qx_q20_i;assign yy=s_qy_q20_i*s_qy_q20_i;assign zz=s_qz_q20_i*s_qz_q20_i;
    assign xy=s_qx_q20_i*s_qy_q20_i;assign xz=s_qx_q20_i*s_qz_q20_i;assign yz=s_qy_q20_i*s_qz_q20_i;
    assign wx=s_qw_q20_i*s_qx_q20_i;assign wy=s_qw_q20_i*s_qy_q20_i;assign wz=s_qw_q20_i*s_qz_q20_i;
    assign r00_w=ONE_Q40-twice_qprod(yy)-twice_qprod(zz);
    assign r01_w=twice_qprod(xy)-twice_qprod(wz);assign r02_w=twice_qprod(xz)+twice_qprod(wy);
    assign r10_w=twice_qprod(xy)+twice_qprod(wz);assign r11_w=ONE_Q40-twice_qprod(xx)-twice_qprod(zz);
    assign r12_w=twice_qprod(yz)-twice_qprod(wx);assign r20_w=twice_qprod(xz)-twice_qprod(wy);
    assign r21_w=twice_qprod(yz)+twice_qprod(wx);assign r22_w=ONE_Q40-twice_qprod(xx)-twice_qprod(yy);
    always_comb begin
        r00=q40_to_q20(r00_w);r01=q40_to_q20(r01_w);r02=q40_to_q20(r02_w);
        r10=q40_to_q20(r10_w);r11=q40_to_q20(r11_w);r12=q40_to_q20(r12_w);
        r20=q40_to_q20(r20_w);r21=q40_to_q20(r21_w);r22=q40_to_q20(r22_w);
        rotation_overflow=rot_ov(r00_w)||rot_ov(r01_w)||rot_ov(r02_w)||rot_ov(r10_w)||rot_ov(r11_w)||rot_ov(r12_w)||rot_ov(r20_w)||rot_ov(r21_w)||rot_ov(r22_w);
    end
    rv_reg_slice #(.DATA_W(R_DATA_W))u_rotation(.clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i),.s_ready_o(s_ready_o),
      .s_data_i({s_meta_i,s_scale_x_q20_i,s_scale_y_q20_i,s_scale_z_q20_i,rotation_overflow,r00,r01,r02,r10,r11,r12,r20,r21,r22}),
      .m_valid_o(r_valid),.m_ready_i(r_ready),.m_data_o({r_meta,rr00,rr01,rr02,rr10,rr11,rr12,rr20,rr21,rr22}));
    assign {meta_r,sx_r,sy_r,sz_r,rotation_overflow_r}=r_meta;
    assign ms00_w=$signed(rr00)*$signed({1'b0,sx_r});assign ms01_w=$signed(rr01)*$signed({1'b0,sy_r});assign ms02_w=$signed(rr02)*$signed({1'b0,sz_r});
    assign ms10_w=$signed(rr10)*$signed({1'b0,sx_r});assign ms11_w=$signed(rr11)*$signed({1'b0,sy_r});assign ms12_w=$signed(rr12)*$signed({1'b0,sz_r});
    assign ms20_w=$signed(rr20)*$signed({1'b0,sx_r});assign ms21_w=$signed(rr21)*$signed({1'b0,sy_r});assign ms22_w=$signed(rr22)*$signed({1'b0,sz_r});
    always_comb begin
      ms00=product_q40_to_q20(ms00_w);ms01=product_q40_to_q20(ms01_w);ms02=product_q40_to_q20(ms02_w);
      ms10=product_q40_to_q20(ms10_w);ms11=product_q40_to_q20(ms11_w);ms12=product_q40_to_q20(ms12_w);
      ms20=product_q40_to_q20(ms20_w);ms21=product_q40_to_q20(ms21_w);ms22=product_q40_to_q20(ms22_w);
      scaled_overflow=scaled_ov(ms00_w)||scaled_ov(ms01_w)||scaled_ov(ms02_w)||scaled_ov(ms10_w)||scaled_ov(ms11_w)||scaled_ov(ms12_w)||scaled_ov(ms20_w)||scaled_ov(ms21_w)||scaled_ov(ms22_w);
    end
    assign cxx_w=ms00*ms00+ms01*ms01+ms02*ms02;assign cxy_w=ms00*ms10+ms01*ms11+ms02*ms12;
    assign cxz_w=ms00*ms20+ms01*ms21+ms02*ms22;assign cyy_w=ms10*ms10+ms11*ms11+ms12*ms12;
    assign cyz_w=ms10*ms20+ms11*ms21+ms12*ms22;assign czz_w=ms20*ms20+ms21*ms21+ms22*ms22;
    always_comb begin cxx=cov_q40_to_q16(cxx_w);cxy=cov_q40_to_q16(cxy_w);cxz=cov_q40_to_q16(cxz_w);
      cyy=cov_q40_to_q16(cyy_w);cyz=cov_q40_to_q16(cyz_w);czz=cov_q40_to_q16(czz_w);
      covariance_overflow=cov_ov(cxx_w)||cov_ov(cxy_w)||cov_ov(cxz_w)||cov_ov(cyy_w)||cov_ov(cyz_w)||cov_ov(czz_w);end
    assign result_data={meta_r,cxx,cxy,cxz,cyy,cyz,czz,rotation_overflow_r||scaled_overflow||covariance_overflow};
    rv_reg_slice #(.DATA_W(RESULT_W))u_result(.clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(r_valid),.s_ready_o(r_ready),
      .s_data_i(result_data),.m_valid_o(m_valid_o),.m_ready_i(m_ready_i),.m_data_o({m_meta_o,m_cov_xx_q16_o,m_cov_xy_q16_o,m_cov_xz_q16_o,m_cov_yy_q16_o,m_cov_yz_q16_o,m_cov_zz_q16_o,m_numeric_overflow_o}));
endmodule
