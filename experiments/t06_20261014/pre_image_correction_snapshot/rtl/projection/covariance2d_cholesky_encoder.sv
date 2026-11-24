// Invert a regularized 2D covariance and encode a PSD-preserving Cholesky
// representation for alpha_block_float_core. Covariance inputs are Q27.8.
// Internal conic coefficients are Q4.40 and factors are Q4.20 before an
// independently selected block-float exponent produces Q3.12 outputs.
module covariance2d_cholesky_encoder #(
    parameter int unsigned META_W   = 64,
    parameter int unsigned COV_W    = 35,
    parameter int unsigned SCREEN_W = 27,
    parameter int unsigned PIXEL_W  = 16,
    parameter int unsigned CONIC_W  = 44,
    parameter int unsigned FACTOR_W = 24
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic                         s_valid_i,
    output logic                         s_ready_o,
    input  logic [META_W-1:0]            s_meta_i,
    input  logic        [COV_W-1:0]      s_cov00_q8_i,
    input  logic signed [COV_W-1:0]      s_cov01_q8_i,
    input  logic        [COV_W-1:0]      s_cov11_q8_i,
    input  logic signed [SCREEN_W-1:0]   s_mean_x_q8_i,
    input  logic signed [SCREEN_W-1:0]   s_mean_y_q8_i,
    input  logic        [PIXEL_W-1:0]    s_x0_i,
    input  logic        [PIXEL_W-1:0]    s_y0_i,
    input  logic        [PIXEL_W-1:0]    s_x1_i,
    input  logic        [PIXEL_W-1:0]    s_y1_i,
    input  logic        [12:0]           s_opacity_q12_i,
    input  logic                         s_numeric_overflow_i,
    output logic                         m_valid_o,
    input  logic                         m_ready_i,
    output logic [META_W-1:0]            m_meta_o,
    output logic        [14:0]           m_l00_q12_o,
    output logic signed [15:0]           m_l10_q12_o,
    output logic        [14:0]           m_l11_q12_o,
    output logic signed [5:0]            m_coordinate_shift_o,
    output logic signed [5:0]            m_factor_shift_o,
    output logic        [12:0]           m_opacity_q12_o,
    output logic                         m_numeric_overflow_o
);
    localparam int unsigned DET_W = 2*COV_W + 1;
    localparam int unsigned NUM_W = COV_W + 49;
    localparam int unsigned SQRT0_W = (CONIC_W + 1) / 2;
    localparam int unsigned L10_QUOT_W = FACTOR_W;
    localparam int unsigned RESID_W = 2*FACTOR_W;
    localparam int unsigned FRONT_META_W = META_W + 2*SCREEN_W
        + 4*PIXEL_W + 13 + 1;
    localparam int unsigned SQRT0_META_W = FRONT_META_W + 2*CONIC_W + 1;
    localparam int unsigned L10_META_W = FRONT_META_W + CONIC_W
        + SQRT0_W + 1;
    localparam int unsigned SQRT1_META_W = FRONT_META_W + SQRT0_W
        + L10_QUOT_W + 1;
    localparam int unsigned RESULT_W = META_W + 15 + 16 + 15 + 6 + 6 + 13 + 1;

    logic [2*COV_W-1:0] ad_product,b_square;
    logic [DET_W-1:0] determinant;
    logic determinant_valid;
    logic signed [NUM_W-1:0] numerator00,numerator01,numerator11;
    logic [DET_W-1:0] denominator;
    logic [FRONT_META_W-1:0] front_meta;

    logic div0_s_ready,div1_s_ready,div0_valid,div1_valid;
    logic div0_ready,div1_ready;
    logic signed [CONIC_W-1:0] conic00_q40,conic01_q40;
    logic signed [CONIC_W-1:0] conic11_q40,unused_quotient;
    logic [FRONT_META_W-1:0] div0_meta,div1_meta;
    logic div0_zero,div0_overflow,div1_zero,div1_overflow;

    logic sqrt0_s_ready,sqrt0_valid,sqrt0_ready;
    logic [SQRT0_META_W-1:0] sqrt0_meta_in,sqrt0_meta_out;
    logic [SQRT0_W-1:0] l00_q20;
    logic [FRONT_META_W-1:0] front_meta_s0;
    logic signed [CONIC_W-1:0] conic01_s0,conic11_s0;
    logic error_s0;

    logic l10_valid,l10_ready;
    logic signed [L10_QUOT_W-1:0] l10_q20,l10_unused;
    logic [L10_META_W-1:0] l10_meta_in,l10_meta_out;
    logic l10_zero,l10_overflow;
    logic [FRONT_META_W-1:0] front_meta_l10;
    logic signed [CONIC_W-1:0] conic11_l10;
    logic [SQRT0_W-1:0] l00_l10;
    logic error_l10;

    logic signed [RESID_W-1:0] l10_square;
    logic signed [RESID_W-1:0] conic11_extended,residual_signed;
    logic [RESID_W-1:0] residual_nonnegative;
    logic residual_invalid;
    logic sqrt1_valid;
    logic [SQRT1_META_W-1:0] sqrt1_meta_in,sqrt1_meta_out;
    logic [FACTOR_W-1:0] l11_q20;

    logic [FRONT_META_W-1:0] front_meta_final;
    logic [SQRT0_W-1:0] l00_final;
    logic signed [L10_QUOT_W-1:0] l10_final;
    logic error_final;
    logic [META_W-1:0] meta_final;
    logic signed [SCREEN_W-1:0] mean_x_final,mean_y_final;
    logic [PIXEL_W-1:0] x0_final,y0_final,x1_final,y1_final;
    logic [12:0] opacity_final;
    logic input_overflow_final;

    logic [FACTOR_W-1:0] l00_extended,l10_absolute,max_factor;
    logic signed [5:0] factor_shift,coordinate_shift;
    logic [14:0] l00_encoded,l11_encoded;
    logic signed [15:0] l10_encoded;
    logic factor_encode_overflow;
    logic [SCREEN_W:0] extent_x0,extent_x1,extent_y0,extent_y1,max_extent;
    logic [RESULT_W-1:0] result_data;

    function automatic logic [SCREEN_W:0] absolute_delta(
        input logic signed [SCREEN_W:0] value
    );
        begin absolute_delta=value<0 ? -value : value; end
    endfunction

    function automatic logic signed [SCREEN_W:0] pixel_to_q8(
        input logic [PIXEL_W-1:0] pixel
    );
        begin
            pixel_to_q8 = $signed({{(SCREEN_W+1-PIXEL_W-8){1'b0}},pixel,8'd0});
        end
    endfunction

    function automatic logic signed [SCREEN_W:0] extend_mean(
        input logic signed [SCREEN_W-1:0] mean
    );
        begin extend_mean={mean[SCREEN_W-1],mean}; end
    endfunction

    function automatic logic signed [5:0] choose_factor_shift(
        input logic [FACTOR_W-1:0] value
    );
        integer bit_index,ceil_log2,selected,scan_index;
        logic power_of_two;
        begin
            if(value==0) choose_factor_shift=-6'sd32;
            else begin
                // Use a statically bounded scan so synthesis tools can unroll
                // the priority encoder.  The former data-dependent while loop
                // was legal simulation code but was rejected by Yosys.
                bit_index=0;
                for(scan_index=0;scan_index<FACTOR_W;scan_index=scan_index+1)
                    if(value[scan_index])bit_index=scan_index;
                power_of_two=(value & (value-1'b1))==0;
                ceil_log2=power_of_two ? bit_index : bit_index+1;
                selected=ceil_log2-22;
                if(selected>31)choose_factor_shift=6'sd31;
                else if(selected< -32)choose_factor_shift=-6'sd32;
                else choose_factor_shift=6'(selected);
            end
        end
    endfunction

    function automatic logic signed [5:0] choose_coordinate_shift(
        input logic [SCREEN_W:0] extent_q8
    );
        integer selected,scan_index;
        logic [SCREEN_W:0] limit;
        begin
            selected=0;limit={{(SCREEN_W-11){1'b0}},12'd4095};
            // Fixed trip count preserves the saturating result while keeping
            // the loop statically elaborable for ASIC synthesis.
            for(scan_index=0;scan_index<31;scan_index=scan_index+1)
                if(extent_q8>limit)begin selected=selected+1;limit=limit<<1;end
            choose_coordinate_shift=6'(selected);
        end
    endfunction

    function automatic logic [14:0] encode_unsigned_factor(
        input logic [FACTOR_W-1:0] value,input logic signed [5:0] shift
    );
        logic [63:0] wide,rounded,scaled;integer right_shift;
        begin
            wide={{(64-FACTOR_W){1'b0}},value};right_shift=8+int'(shift);
            if(right_shift>0)begin rounded=64'd1<<(right_shift-1);scaled=(wide+rounded)>>right_shift;end
            else if(right_shift<=-32)scaled=64'hffff_ffff_ffff_ffff;
            else scaled=wide<<(-right_shift);
            encode_unsigned_factor=|scaled[63:15]?15'h7fff:scaled[14:0];
        end
    endfunction

    function automatic logic signed [15:0] encode_signed_factor(
        input logic signed [FACTOR_W-1:0] value,input logic signed [5:0] shift
    );
        logic signed [63:0] wide,scaled;logic [63:0] magnitude;integer right_shift;
        begin
            wide={{(64-FACTOR_W){value[FACTOR_W-1]}},value};right_shift=8+int'(shift);
            if(right_shift>0)begin
                magnitude=wide<0 ? -wide : wide;
                magnitude=(magnitude+(64'd1<<(right_shift-1)))>>right_shift;
                scaled=wide<0 ? -$signed(magnitude) : $signed(magnitude);
            end else if(right_shift<=-32)scaled=wide<0?-64'sh7fff_ffff_ffff_ffff:64'sh7fff_ffff_ffff_ffff;
            else scaled=wide<<<(-right_shift);
            if(scaled>32767)encode_signed_factor=16'sh7fff;
            else if(scaled< -32768)encode_signed_factor=-16'sh8000;
            else encode_signed_factor=scaled[15:0];
        end
    endfunction

    assign ad_product=s_cov00_q8_i*s_cov11_q8_i;
    assign b_square=$signed(s_cov01_q8_i)*$signed(s_cov01_q8_i);
    assign determinant={1'b0,ad_product}-{1'b0,b_square};
    assign determinant_valid={1'b0,ad_product}>{1'b0,b_square}
        &&s_cov00_q8_i!=0&&s_cov11_q8_i!=0;
    assign denominator=determinant_valid?determinant:'0;
    assign numerator00=$signed({1'b0,s_cov11_q8_i,48'd0});
    assign numerator01=-($signed({{(NUM_W-COV_W){s_cov01_q8_i[COV_W-1]}},s_cov01_q8_i})<<<48);
    assign numerator11=$signed({1'b0,s_cov00_q8_i,48'd0});
    assign front_meta={s_meta_i,s_mean_x_q8_i,s_mean_y_q8_i,
        s_x0_i,s_y0_i,s_x1_i,s_y1_i,s_opacity_q12_i,
        s_numeric_overflow_i||!determinant_valid};

    fixed_div_pipe2 #(.NUM_W(NUM_W),.DEN_W(DET_W),.QUOT_W(CONIC_W),.META_W(FRONT_META_W))u_conic_00_01(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i&&div1_s_ready),.s_ready_o(div0_s_ready),
      .s_num0_i(numerator00),.s_num1_i(numerator01),.s_den_i(denominator),.s_meta_i(front_meta),
      .m_valid_o(div0_valid),.m_ready_i(div0_ready),.m_quot0_o(conic00_q40),.m_quot1_o(conic01_q40),
      .m_meta_o(div0_meta),.m_div_zero_o(div0_zero),.m_overflow_o(div0_overflow));
    fixed_div_pipe2 #(.NUM_W(NUM_W),.DEN_W(DET_W),.QUOT_W(CONIC_W),.META_W(FRONT_META_W))u_conic_11(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i&&div0_s_ready),.s_ready_o(div1_s_ready),
      .s_num0_i(numerator11),.s_num1_i({NUM_W{1'b0}}),.s_den_i(denominator),.s_meta_i(front_meta),
      .m_valid_o(div1_valid),.m_ready_i(div1_ready),.m_quot0_o(conic11_q40),.m_quot1_o(unused_quotient),
      .m_meta_o(div1_meta),.m_div_zero_o(div1_zero),.m_overflow_o(div1_overflow));
    assign s_ready_o=div0_s_ready&&div1_s_ready;
    assign sqrt0_meta_in={div0_meta,conic01_q40,conic11_q40,
        div0_zero||div0_overflow||div1_zero||div1_overflow};
    fixed_sqrt_pipe #(.RAD_W(CONIC_W),.META_W(SQRT0_META_W))u_sqrt_l00(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(div0_valid&&div1_valid),.s_ready_o(sqrt0_s_ready),
      .s_radicand_i(conic00_q40[CONIC_W-1]?'0:conic00_q40),.s_meta_i(sqrt0_meta_in),
      .m_valid_o(sqrt0_valid),.m_ready_i(sqrt0_ready),.m_root_o(l00_q20),.m_meta_o(sqrt0_meta_out),.m_exact_o());
    assign div0_ready=sqrt0_s_ready&&div1_valid;
    assign div1_ready=sqrt0_s_ready&&div0_valid;
    assign {front_meta_s0,conic01_s0,conic11_s0,error_s0}=sqrt0_meta_out;

    assign l10_meta_in={front_meta_s0,conic11_s0,l00_q20,error_s0||l00_q20==0};
    fixed_div_pipe2 #(.NUM_W(CONIC_W),.DEN_W(SQRT0_W),.QUOT_W(L10_QUOT_W),.META_W(L10_META_W))u_l10_div(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(sqrt0_valid),.s_ready_o(sqrt0_ready),
      .s_num0_i(conic01_s0),.s_num1_i({CONIC_W{1'b0}}),.s_den_i(l00_q20),.s_meta_i(l10_meta_in),
      .m_valid_o(l10_valid),.m_ready_i(l10_ready),.m_quot0_o(l10_q20),.m_quot1_o(l10_unused),
      .m_meta_o(l10_meta_out),.m_div_zero_o(l10_zero),.m_overflow_o(l10_overflow));
    assign {front_meta_l10,conic11_l10,l00_l10,error_l10}=l10_meta_out;
    assign l10_square=$signed(l10_q20)*$signed(l10_q20);
    assign conic11_extended={{(RESID_W-CONIC_W){conic11_l10[CONIC_W-1]}},conic11_l10};
    assign residual_signed=conic11_extended-l10_square;
    assign residual_invalid=residual_signed<0||l10_zero||l10_overflow||error_l10;
    assign residual_nonnegative=residual_signed<0?'0:residual_signed;
    assign sqrt1_meta_in={front_meta_l10,l00_l10,l10_q20,residual_invalid};
    fixed_sqrt_pipe #(.RAD_W(RESID_W),.META_W(SQRT1_META_W))u_sqrt_l11(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(l10_valid),.s_ready_o(l10_ready),
      .s_radicand_i(residual_nonnegative),.s_meta_i(sqrt1_meta_in),
      .m_valid_o(sqrt1_valid),.m_ready_i(m_ready_i),.m_root_o(l11_q20),.m_meta_o(sqrt1_meta_out),.m_exact_o());
    assign {front_meta_final,l00_final,l10_final,error_final}=sqrt1_meta_out;
    assign {meta_final,mean_x_final,mean_y_final,x0_final,y0_final,x1_final,y1_final,
        opacity_final,input_overflow_final}=front_meta_final;

    assign l00_extended={{(FACTOR_W-SQRT0_W){1'b0}},l00_final};
    assign l10_absolute=l10_final[L10_QUOT_W-1]?-l10_final:l10_final;
    assign max_factor=l00_extended>=l10_absolute
        ?(l00_extended>=l11_q20?l00_extended:l11_q20)
        :(l10_absolute>=l11_q20?l10_absolute:l11_q20);
    assign factor_shift=choose_factor_shift(max_factor);
    assign l00_encoded=encode_unsigned_factor(l00_extended,factor_shift);
    assign l10_encoded=encode_signed_factor(l10_final,factor_shift);
    assign l11_encoded=encode_unsigned_factor(l11_q20,factor_shift);
    assign factor_encode_overflow=(l00_encoded==15'h7fff)||(l11_encoded==15'h7fff)
        ||(l10_encoded==16'sh7fff)||(l10_encoded==-16'sh8000);
    assign extent_x0=absolute_delta(pixel_to_q8(x0_final)-extend_mean(mean_x_final));
    assign extent_y0=absolute_delta(pixel_to_q8(y0_final)-extend_mean(mean_y_final));
    assign extent_x1=absolute_delta(pixel_to_q8(x1_final==0?x1_final:x1_final-PIXEL_W'(1))-extend_mean(mean_x_final));
    assign extent_y1=absolute_delta(pixel_to_q8(y1_final==0?y1_final:y1_final-PIXEL_W'(1))-extend_mean(mean_y_final));
    assign max_extent=extent_x0>=extent_x1
        ?(extent_x0>=extent_y0?(extent_x0>=extent_y1?extent_x0:extent_y1):(extent_y0>=extent_y1?extent_y0:extent_y1))
        :(extent_x1>=extent_y0?(extent_x1>=extent_y1?extent_x1:extent_y1):(extent_y0>=extent_y1?extent_y0:extent_y1));
    assign coordinate_shift=choose_coordinate_shift(max_extent);
    assign result_data={meta_final,l00_encoded,l10_encoded,l11_encoded,
        coordinate_shift,factor_shift,opacity_final,
        input_overflow_final||error_final||factor_encode_overflow};
    assign {m_meta_o,m_l00_q12_o,m_l10_q12_o,m_l11_q12_o,
        m_coordinate_shift_o,m_factor_shift_o,m_opacity_q12_o,
        m_numeric_overflow_o}=result_data;
    assign m_valid_o=sqrt1_valid;

`ifndef SYNTHESIS
    assert property (@(posedge clk_i) disable iff(!rst_ni)
      div0_valid&&div1_valid |-> div0_meta==div1_meta);
    assert property (@(posedge clk_i) disable iff(!rst_ni)
      m_valid_o&&!m_ready_i|=>m_valid_o&&$stable({m_meta_o,m_l00_q12_o,m_l10_q12_o,
      m_l11_q12_o,m_coordinate_shift_o,m_factor_shift_o,m_opacity_q12_o,m_numeric_overflow_o}));
`endif
endmodule
