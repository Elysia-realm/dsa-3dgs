// Fully-pipelined unsigned integer square root. Two radicand bits are
// consumed per stage using the restoring algorithm. The whole pipeline can
// be stalled by output backpressure; otherwise it accepts one value/cycle.
module fixed_sqrt_pipe #(
    parameter int unsigned RAD_W  = 48,
    parameter int unsigned META_W = 1,
    parameter int unsigned ROOT_W = (RAD_W + 1) / 2,
    parameter int unsigned PAD_W  = 2 * ROOT_W
) (
    input  logic                     clk_i,
    input  logic                     rst_ni,
    input  logic                     s_valid_i,
    output logic                     s_ready_o,
    input  logic [RAD_W-1:0]         s_radicand_i,
    input  logic [META_W-1:0]        s_meta_i,
    output logic                     m_valid_o,
    input  logic                     m_ready_i,
    output logic [ROOT_W-1:0]        m_root_o,
    output logic [META_W-1:0]        m_meta_o,
    output logic                     m_exact_o
);
    localparam int unsigned REM_W = ROOT_W + 2;

    logic [ROOT_W:0] valid_q;
    logic [PAD_W-1:0] radicand_q [0:ROOT_W];
    logic [ROOT_W-1:0] root_q [0:ROOT_W];
    logic [REM_W-1:0] remainder_q [0:ROOT_W];
    logic [META_W-1:0] meta_q [0:ROOT_W];
    logic advance;
    logic [PAD_W-1:0] padded_radicand;
    logic [REM_W-1:0] shifted_remainder [0:ROOT_W-1];
    logic [REM_W-1:0] trial_divisor [0:ROOT_W-1];
    logic [REM_W-1:0] next_remainder [0:ROOT_W-1];
    logic [ROOT_W-1:0] next_root [0:ROOT_W-1];
    integer stage_index;
    genvar combinational_stage;

    assign padded_radicand = {{(PAD_W-RAD_W){1'b0}}, s_radicand_i};
    assign advance = !valid_q[ROOT_W] || m_ready_i;
    assign s_ready_o = advance;
    assign m_valid_o = valid_q[ROOT_W];
    assign m_root_o = root_q[ROOT_W];
    assign m_meta_o = meta_q[ROOT_W];
    assign m_exact_o = remainder_q[ROOT_W] == '0;

    // Each restoring stage consumes exactly two radicand bits.  Explicit
    // concatenations keep the arithmetic at its mathematical width: REM_W for
    // the partial remainder/trial divisor and ROOT_W for the partial root.
    generate
        for (combinational_stage = 0; combinational_stage < ROOT_W;
             combinational_stage = combinational_stage + 1) begin : g_sqrt_stage
            logic take_root_bit;

            assign shifted_remainder[combinational_stage] = {
                remainder_q[combinational_stage][REM_W-3:0],
                radicand_q[combinational_stage]
                    [PAD_W-1-2*combinational_stage -: 2]
            };
            assign trial_divisor[combinational_stage] = {
                root_q[combinational_stage], 2'b01
            };
            assign take_root_bit =
                shifted_remainder[combinational_stage]
                >= trial_divisor[combinational_stage];
            assign next_remainder[combinational_stage] = take_root_bit
                ? shifted_remainder[combinational_stage]
                    - trial_divisor[combinational_stage]
                : shifted_remainder[combinational_stage];
            always_comb begin
                next_root[combinational_stage] =
                    root_q[combinational_stage] << 1;
                next_root[combinational_stage][0] = take_root_bit;
            end
        end
    endgenerate

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_q <= '0;
            for (stage_index = 0; stage_index <= ROOT_W;
                 stage_index = stage_index + 1) begin
                radicand_q[stage_index] <= '0;
                root_q[stage_index] <= '0;
                remainder_q[stage_index] <= '0;
                meta_q[stage_index] <= '0;
            end
        end else if (advance) begin
            valid_q[0] <= s_valid_i;
            if (s_valid_i) begin
                radicand_q[0] <= padded_radicand;
                root_q[0] <= '0;
                remainder_q[0] <= '0;
                meta_q[0] <= s_meta_i;
            end
            for (stage_index = 0; stage_index < ROOT_W;
                 stage_index = stage_index + 1) begin
                valid_q[stage_index+1] <= valid_q[stage_index];
                if (valid_q[stage_index]) begin
                    radicand_q[stage_index+1] <= radicand_q[stage_index];
                    meta_q[stage_index+1] <= meta_q[stage_index];
                    remainder_q[stage_index+1] <= next_remainder[stage_index];
                    root_q[stage_index+1] <= next_root[stage_index];
                end
            end
        end
    end

`ifndef SYNTHESIS
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        m_valid_o && !m_ready_i |=> m_valid_o
        && $stable({m_root_o,m_meta_o}));
`endif
endmodule
