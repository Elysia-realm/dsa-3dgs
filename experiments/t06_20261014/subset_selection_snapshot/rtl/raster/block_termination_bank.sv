// One logical termination-state bank. The complete block tag prevents a
// capacity alias from becoming a false-positive skip. Epoch tagging provides
// lazy invalidation without clearing the inferred SRAM contents.
module block_termination_bank #(
    parameter int unsigned BLOCK_W = 24,
    parameter int unsigned EPOCH_W = 16,
    parameter int unsigned ROWS    = 256,
    parameter int unsigned ROW_W   = (ROWS <= 1) ? 1 : $clog2(ROWS)
) (
    input  logic               clk_i,
    input  logic               rst_ni,
    input  logic               query_en_i,
    input  logic [ROW_W-1:0]   query_row_i,
    input  logic [BLOCK_W-1:0] query_block_id_i,
    input  logic [EPOCH_W-1:0] query_epoch_id_i,
    output logic               query_terminated_o,
    input  logic               update_en_i,
    input  logic [ROW_W-1:0]   update_row_i,
    input  logic [BLOCK_W-1:0] update_block_id_i,
    input  logic [EPOCH_W-1:0] update_epoch_id_i
);

    logic [BLOCK_W-1:0] tag_mem   [0:ROWS-1];
    logic [EPOCH_W-1:0] epoch_mem [0:ROWS-1];
    logic               valid_mem [0:ROWS-1];
    integer index;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            query_terminated_o <= 1'b0;
            // Only the valid sidecar is reset. Tag/epoch arrays intentionally
            // have no reset assignment so an ASIC flow can map them to SRAM.
            for (index = 0; index < ROWS; index = index + 1) begin
                valid_mem[index] <= 1'b0;
            end
        end else begin
            if (query_en_i) begin
                if (update_en_i
                    && update_row_i == query_row_i
                    && update_block_id_i == query_block_id_i
                    && update_epoch_id_i == query_epoch_id_i) begin
                    query_terminated_o <= 1'b1;
                end else begin
                    query_terminated_o <= valid_mem[query_row_i]
                        && tag_mem[query_row_i] == query_block_id_i
                        && epoch_mem[query_row_i] == query_epoch_id_i;
                end
            end
            if (update_en_i) begin
                valid_mem[update_row_i] <= 1'b1;
                tag_mem[update_row_i]   <= update_block_id_i;
                epoch_mem[update_row_i] <= update_epoch_id_i;
            end
        end
    end

endmodule
