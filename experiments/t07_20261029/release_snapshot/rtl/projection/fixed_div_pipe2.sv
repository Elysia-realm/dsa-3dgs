// Two-lane fully pipelined restoring divider. Both signed numerators share one
// positive denominator and advance atomically. One quotient bit is resolved per
// stage, so latency is QUOT_W cycles and throughput is one pair per cycle.
module fixed_div_pipe2 #(
    parameter int unsigned NUM_W  = 52,
    parameter int unsigned DEN_W  = 27,
    parameter int unsigned QUOT_W = 32,
    parameter int unsigned META_W = 1,
    parameter int unsigned WORK_W = ((DEN_W + QUOT_W + 1) > (NUM_W + 1))
                                  ? (DEN_W + QUOT_W + 1) : (NUM_W + 1)
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic                         s_valid_i,
    output logic                         s_ready_o,
    input  logic signed [NUM_W-1:0]      s_num0_i,
    input  logic signed [NUM_W-1:0]      s_num1_i,
    input  logic        [DEN_W-1:0]      s_den_i,
    input  logic        [META_W-1:0]     s_meta_i,
    output logic                         m_valid_o,
    input  logic                         m_ready_i,
    output logic signed [QUOT_W-1:0]     m_quot0_o,
    output logic signed [QUOT_W-1:0]     m_quot1_o,
    output logic        [META_W-1:0]     m_meta_o,
    output logic                         m_div_zero_o,
    output logic                         m_overflow_o
);
    logic [QUOT_W:0] valid_q;
    logic [WORK_W-1:0] rem0_q [0:QUOT_W];
    logic [WORK_W-1:0] rem1_q [0:QUOT_W];
    logic [WORK_W-1:0] den_q  [0:QUOT_W];
    logic [QUOT_W-1:0] quot0_q [0:QUOT_W];
    logic [QUOT_W-1:0] quot1_q [0:QUOT_W];
    logic [META_W-1:0] meta_q [0:QUOT_W];
    logic sign0_q [0:QUOT_W];
    logic sign1_q [0:QUOT_W];
    logic div_zero_q [0:QUOT_W];
    logic wide_overflow0_q [0:QUOT_W];
    logic wide_overflow1_q [0:QUOT_W];
    logic advance;
    logic [WORK_W-1:0] num0_magnitude, num1_magnitude, den_extended;
    logic [WORK_W-1:0] overflow_threshold;
    logic [QUOT_W-1:0] quot0_magnitude, quot1_magnitude;
    logic signed_overflow0, signed_overflow1;
    integer stage_index;

    always_comb begin
        num0_magnitude = {{(WORK_W-NUM_W){s_num0_i[NUM_W-1]}}, s_num0_i};
        num1_magnitude = {{(WORK_W-NUM_W){s_num1_i[NUM_W-1]}}, s_num1_i};
        if (s_num0_i[NUM_W-1])
            num0_magnitude = -$signed(num0_magnitude);
        if (s_num1_i[NUM_W-1])
            num1_magnitude = -$signed(num1_magnitude);
        den_extended = {{(WORK_W-DEN_W){1'b0}}, s_den_i};
        overflow_threshold = den_extended << QUOT_W;
    end

    assign advance = !valid_q[QUOT_W] || m_ready_i;
    assign s_ready_o = advance;
    assign m_valid_o = valid_q[QUOT_W];
    assign m_meta_o = meta_q[QUOT_W];
    assign m_div_zero_o = div_zero_q[QUOT_W];
    assign quot0_magnitude = quot0_q[QUOT_W];
    assign quot1_magnitude = quot1_q[QUOT_W];
    assign signed_overflow0 = wide_overflow0_q[QUOT_W]
        || (!sign0_q[QUOT_W] && quot0_magnitude[QUOT_W-1])
        || (sign0_q[QUOT_W] && quot0_magnitude[QUOT_W-1]
            && |quot0_magnitude[QUOT_W-2:0]);
    assign signed_overflow1 = wide_overflow1_q[QUOT_W]
        || (!sign1_q[QUOT_W] && quot1_magnitude[QUOT_W-1])
        || (sign1_q[QUOT_W] && quot1_magnitude[QUOT_W-1]
            && |quot1_magnitude[QUOT_W-2:0]);
    assign m_overflow_o = signed_overflow0 || signed_overflow1;

    always_comb begin
        if (div_zero_q[QUOT_W] || signed_overflow0)
            m_quot0_o = sign0_q[QUOT_W]
                ? {1'b1, {(QUOT_W-1){1'b0}}}
                : {1'b0, {(QUOT_W-1){1'b1}}};
        else if (sign0_q[QUOT_W])
            m_quot0_o = -$signed(quot0_magnitude);
        else
            m_quot0_o = $signed(quot0_magnitude);

        if (div_zero_q[QUOT_W] || signed_overflow1)
            m_quot1_o = sign1_q[QUOT_W]
                ? {1'b1, {(QUOT_W-1){1'b0}}}
                : {1'b0, {(QUOT_W-1){1'b1}}};
        else if (sign1_q[QUOT_W])
            m_quot1_o = -$signed(quot1_magnitude);
        else
            m_quot1_o = $signed(quot1_magnitude);
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_q <= '0;
            for (stage_index = 0; stage_index <= QUOT_W; stage_index = stage_index + 1) begin
                rem0_q[stage_index] <= '0;
                rem1_q[stage_index] <= '0;
                den_q[stage_index] <= '0;
                quot0_q[stage_index] <= '0;
                quot1_q[stage_index] <= '0;
                meta_q[stage_index] <= '0;
                sign0_q[stage_index] <= 1'b0;
                sign1_q[stage_index] <= 1'b0;
                div_zero_q[stage_index] <= 1'b0;
                wide_overflow0_q[stage_index] <= 1'b0;
                wide_overflow1_q[stage_index] <= 1'b0;
            end
        end else if (advance) begin
            valid_q[0] <= s_valid_i;
            if (s_valid_i) begin
                rem0_q[0] <= num0_magnitude;
                rem1_q[0] <= num1_magnitude;
                den_q[0] <= den_extended;
                quot0_q[0] <= '0;
                quot1_q[0] <= '0;
                meta_q[0] <= s_meta_i;
                sign0_q[0] <= s_num0_i[NUM_W-1];
                sign1_q[0] <= s_num1_i[NUM_W-1];
                div_zero_q[0] <= s_den_i == '0;
                wide_overflow0_q[0] <= (s_den_i == '0)
                    || (num0_magnitude >= overflow_threshold);
                wide_overflow1_q[0] <= (s_den_i == '0)
                    || (num1_magnitude >= overflow_threshold);
            end
            for (stage_index = 0; stage_index < QUOT_W; stage_index = stage_index + 1) begin
                valid_q[stage_index+1] <= valid_q[stage_index];
                if (valid_q[stage_index]) begin
                    den_q[stage_index+1] <= den_q[stage_index];
                    meta_q[stage_index+1] <= meta_q[stage_index];
                    sign0_q[stage_index+1] <= sign0_q[stage_index];
                    sign1_q[stage_index+1] <= sign1_q[stage_index];
                    div_zero_q[stage_index+1] <= div_zero_q[stage_index];
                    wide_overflow0_q[stage_index+1] <= wide_overflow0_q[stage_index];
                    wide_overflow1_q[stage_index+1] <= wide_overflow1_q[stage_index];
                    quot0_q[stage_index+1] <= quot0_q[stage_index];
                    quot1_q[stage_index+1] <= quot1_q[stage_index];
                    if (!div_zero_q[stage_index]
                        && rem0_q[stage_index] >= (den_q[stage_index] << (QUOT_W-1-stage_index))) begin
                        rem0_q[stage_index+1] <= rem0_q[stage_index]
                            - (den_q[stage_index] << (QUOT_W-1-stage_index));
                        quot0_q[stage_index+1][QUOT_W-1-stage_index] <= 1'b1;
                    end else begin
                        rem0_q[stage_index+1] <= rem0_q[stage_index];
                    end
                    if (!div_zero_q[stage_index]
                        && rem1_q[stage_index] >= (den_q[stage_index] << (QUOT_W-1-stage_index))) begin
                        rem1_q[stage_index+1] <= rem1_q[stage_index]
                            - (den_q[stage_index] << (QUOT_W-1-stage_index));
                        quot1_q[stage_index+1][QUOT_W-1-stage_index] <= 1'b1;
                    end else begin
                        rem1_q[stage_index+1] <= rem1_q[stage_index];
                    end
                end
            end
        end
    end

endmodule
