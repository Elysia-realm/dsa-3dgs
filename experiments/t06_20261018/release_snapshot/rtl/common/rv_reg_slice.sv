// One-entry elastic register slice for internal ready/valid streams.
module rv_reg_slice #(
    parameter int unsigned DATA_W = 32
) (
    input  logic              clk_i,
    input  logic              rst_ni,
    input  logic              s_valid_i,
    output logic              s_ready_o,
    input  logic [DATA_W-1:0] s_data_i,
    output logic              m_valid_o,
    input  logic              m_ready_i,
    output logic [DATA_W-1:0] m_data_o
);

    logic              valid_q;
    logic [DATA_W-1:0] data_q;

    assign s_ready_o = ~valid_q | m_ready_i;
    assign m_valid_o = valid_q;
    assign m_data_o  = data_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_q <= 1'b0;
            data_q  <= '0;
        end else if (s_ready_o) begin
            valid_q <= s_valid_i;
            if (s_valid_i) begin
                data_q <= s_data_i;
            end
        end
    end

`ifndef SYNTHESIS
    property p_output_stable_when_stalled;
        @(posedge clk_i) disable iff (!rst_ni)
            m_valid_o && !m_ready_i |=> m_valid_o && $stable(m_data_o);
    endproperty
    assert property (p_output_stable_when_stalled);
`endif

endmodule
