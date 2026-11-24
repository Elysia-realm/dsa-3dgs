// Banked one-query/one-update block termination table.
//
// Mapping:
//   bank = block_id low BANK_W bits
//   row  = next ROW_W bits
// A complete block tag and epoch are stored in each row. Query responses have
// one cycle of latency and use ready/valid backpressure. Updates are accepted
// every cycle; same-address query/update is write-through.
module block_termination_table #(
    parameter int unsigned BLOCK_W         = 24,
    parameter int unsigned EPOCH_W         = 16,
    parameter int unsigned NUM_BANKS       = 4,
    parameter int unsigned ROWS_PER_BANK   = 256,
    parameter int unsigned BANK_W          = (NUM_BANKS <= 1) ? 1 : $clog2(NUM_BANKS),
    parameter int unsigned ROW_W           = (ROWS_PER_BANK <= 1) ? 1 : $clog2(ROWS_PER_BANK)
) (
    input  logic               clk_i,
    input  logic               rst_ni,
    input  logic               query_valid_i,
    output logic               query_ready_o,
    input  logic [BLOCK_W-1:0] query_block_id_i,
    input  logic [EPOCH_W-1:0] query_epoch_id_i,
    output logic               response_valid_o,
    input  logic               response_ready_i,
    output logic               response_terminated_o,
    input  logic               update_valid_i,
    input  logic [BLOCK_W-1:0] update_block_id_i,
    input  logic [EPOCH_W-1:0] update_epoch_id_i
);

    logic [NUM_BANKS-1:0] query_bank_en;
    logic [NUM_BANKS-1:0] update_bank_en;
    logic [NUM_BANKS-1:0] bank_terminated;
    logic [BANK_W-1:0] query_bank;
    logic [BANK_W-1:0] update_bank;
    logic [ROW_W-1:0] query_row;
    logic [ROW_W-1:0] update_row;
    logic [BANK_W-1:0] response_bank_q;
    logic response_valid_q;
    logic query_fire;

    assign query_bank  = query_block_id_i[BANK_W-1:0];
    assign update_bank = update_block_id_i[BANK_W-1:0];
    assign query_row   = query_block_id_i[BANK_W +: ROW_W];
    assign update_row  = update_block_id_i[BANK_W +: ROW_W];
    assign query_ready_o = ~response_valid_q | response_ready_i;
    assign query_fire = query_valid_i && query_ready_o;
    assign response_valid_o = response_valid_q;
    assign response_terminated_o = bank_terminated[response_bank_q];

    always_comb begin
        query_bank_en  = '0;
        update_bank_en = '0;
        if (query_fire) begin
            query_bank_en[query_bank] = 1'b1;
        end
        if (update_valid_i) begin
            update_bank_en[update_bank] = 1'b1;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            response_valid_q <= 1'b0;
            response_bank_q  <= '0;
        end else if (query_ready_o) begin
            response_valid_q <= query_valid_i;
            if (query_valid_i) begin
                response_bank_q <= query_bank;
            end
        end
    end

    generate
        genvar bank;
        for (bank = 0; bank < NUM_BANKS; bank++) begin : g_bank
            block_termination_bank #(
                .BLOCK_W(BLOCK_W), .EPOCH_W(EPOCH_W),
                .ROWS(ROWS_PER_BANK), .ROW_W(ROW_W)
            ) u_bank (
                .clk_i(clk_i), .rst_ni(rst_ni),
                .query_en_i(query_bank_en[bank]),
                .query_row_i(query_row),
                .query_block_id_i(query_block_id_i),
                .query_epoch_id_i(query_epoch_id_i),
                .query_terminated_o(bank_terminated[bank]),
                .update_en_i(update_bank_en[bank]),
                .update_row_i(update_row),
                .update_block_id_i(update_block_id_i),
                .update_epoch_id_i(update_epoch_id_i)
            );
        end
    endgenerate

`ifndef SYNTHESIS
    initial begin
        assert (NUM_BANKS >= 2 && (NUM_BANKS & (NUM_BANKS - 1)) == 0);
        assert (ROWS_PER_BANK > 0 && (ROWS_PER_BANK & (ROWS_PER_BANK - 1)) == 0);
        assert (BLOCK_W >= BANK_W + ROW_W);
    end
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        response_valid_o && !response_ready_i
        |=> response_valid_o && $stable(response_terminated_o));
`endif

endmodule
