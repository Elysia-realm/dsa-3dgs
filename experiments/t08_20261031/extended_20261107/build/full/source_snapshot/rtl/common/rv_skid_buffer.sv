// Two-entry elastic FIFO. It breaks long combinational ready paths and absorbs
// one additional transfer after downstream backpressure is asserted.
module rv_skid_buffer #(
    parameter int unsigned DATA_W = 32
) (
    input  logic              clk_i,
    input  logic              rst_ni,
    input  logic              s_valid_i,
    output logic              s_ready_o,
    input  logic [DATA_W-1:0] s_data_i,
    output logic              m_valid_o,
    input  logic              m_ready_i,
    output logic [DATA_W-1:0] m_data_o,
    output logic [1:0]        occupancy_o
);

    logic [DATA_W-1:0] data_q [0:1];
    logic               rd_ptr_q;
    logic               wr_ptr_q;
    logic [1:0]         count_q;
    logic               push;
    logic               pop;

    assign s_ready_o   = (count_q != 2);
    assign m_valid_o   = (count_q != 0);
    assign m_data_o    = data_q[rd_ptr_q];
    assign occupancy_o = count_q;
    assign push        = s_valid_i && s_ready_o;
    assign pop         = m_valid_o && m_ready_i;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rd_ptr_q <= 1'b0;
            wr_ptr_q <= 1'b0;
            count_q  <= 2'd0;
            data_q[0] <= '0;
            data_q[1] <= '0;
        end else begin
            if (push) begin
                data_q[wr_ptr_q] <= s_data_i;
                wr_ptr_q <= ~wr_ptr_q;
            end
            if (pop) begin
                rd_ptr_q <= ~rd_ptr_q;
            end
            unique case ({push, pop})
                2'b10: count_q <= count_q + 2'd1;
                2'b01: count_q <= count_q - 2'd1;
                default: count_q <= count_q;
            endcase
        end
    end

`ifndef SYNTHESIS
    assert property (@(posedge clk_i) disable iff (!rst_ni) count_q <= 2);
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        m_valid_o && !m_ready_i |=> m_valid_o && $stable(m_data_o));
`endif

endmodule
