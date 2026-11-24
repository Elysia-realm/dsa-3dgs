// Bank of 64-bit saturating event counters with coherent snapshot support.
module sat_counter_bank #(
    parameter int unsigned NUM_COUNTERS = 8,
    parameter int unsigned COUNTER_W    = 64
) (
    input  logic                              clk_i,
    input  logic                              rst_ni,
    input  logic                              clear_i,
    input  logic                              snapshot_i,
    input  logic [NUM_COUNTERS-1:0]           increment_i,
    output logic [NUM_COUNTERS*COUNTER_W-1:0] live_flat_o,
    output logic [NUM_COUNTERS*COUNTER_W-1:0] snapshot_flat_o
);

    localparam logic [COUNTER_W-1:0] MAX_VALUE = {COUNTER_W{1'b1}};
    logic [COUNTER_W-1:0] counter_q  [0:NUM_COUNTERS-1];
    logic [COUNTER_W-1:0] snapshot_q [0:NUM_COUNTERS-1];
    integer index;

    generate
        genvar lane;
        for (lane = 0; lane < NUM_COUNTERS; lane++) begin : g_flatten
            assign live_flat_o[lane*COUNTER_W +: COUNTER_W] = counter_q[lane];
            assign snapshot_flat_o[lane*COUNTER_W +: COUNTER_W] = snapshot_q[lane];
        end
    endgenerate

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (index = 0; index < NUM_COUNTERS; index = index + 1) begin
                counter_q[index]  <= '0;
                snapshot_q[index] <= '0;
            end
        end else begin
            for (index = 0; index < NUM_COUNTERS; index = index + 1) begin
                if (clear_i) begin
                    counter_q[index] <= '0;
                end else if (increment_i[index] && counter_q[index] != MAX_VALUE) begin
                    counter_q[index] <= counter_q[index] + {{(COUNTER_W-1){1'b0}}, 1'b1};
                end
                if (snapshot_i) begin
                    snapshot_q[index] <= counter_q[index];
                end
            end
        end
    end

endmodule
