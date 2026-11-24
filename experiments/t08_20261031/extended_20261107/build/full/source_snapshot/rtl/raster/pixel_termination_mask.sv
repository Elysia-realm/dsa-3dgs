// Per-block 8x8 termination mask store. Each update ORs newly terminated
// pixels into the 64-bit block mask. A full mask emits a one-cycle event that
// can update the coarse block termination table.
//
// Complete block and epoch tags prevent capacity aliases from corrupting
// another block. A tag miss initializes the previous mask to zero. Same-entry
// query/update uses write-through semantics.
module pixel_termination_mask #(
    parameter int unsigned BLOCK_W = 24,
    parameter int unsigned EPOCH_W = 16,
    parameter int unsigned ENTRIES = 256,
    parameter int unsigned INDEX_W = (ENTRIES <= 1) ? 1 : $clog2(ENTRIES),
    parameter int unsigned PIXELS  = 64
) (
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic                    query_valid_i,
    output logic                    query_ready_o,
    input  logic [BLOCK_W-1:0]      query_block_id_i,
    input  logic [EPOCH_W-1:0]      query_epoch_id_i,
    output logic                    response_valid_o,
    input  logic                    response_ready_i,
    output logic [PIXELS-1:0]       response_mask_o,
    output logic                    response_all_terminated_o,
    input  logic                    update_valid_i,
    input  logic [BLOCK_W-1:0]      update_block_id_i,
    input  logic [EPOCH_W-1:0]      update_epoch_id_i,
    input  logic [PIXELS-1:0]       update_new_terminated_i,
    output logic                    block_terminated_pulse_o,
    output logic [BLOCK_W-1:0]      block_terminated_id_o,
    output logic [EPOCH_W-1:0]      block_terminated_epoch_o
);

    logic [BLOCK_W-1:0] tag_mem   [0:ENTRIES-1];
    logic [EPOCH_W-1:0] epoch_mem [0:ENTRIES-1];
    logic [PIXELS-1:0]  mask_mem  [0:ENTRIES-1];
    logic               valid_mem [0:ENTRIES-1];
    logic [INDEX_W-1:0] query_index;
    logic [INDEX_W-1:0] update_index;
    logic [PIXELS-1:0]  previous_update_mask;
    logic [PIXELS-1:0]  merged_update_mask;
    logic               update_hit;
    logic               query_hit;
    logic               same_entry_write_through;
    logic               response_valid_q;
    logic [PIXELS-1:0]  response_mask_q;
    integer index;

    assign query_index  = query_block_id_i[INDEX_W-1:0];
    assign update_index = update_block_id_i[INDEX_W-1:0];
    assign query_ready_o = ~response_valid_q | response_ready_i;
    assign response_valid_o = response_valid_q;
    assign response_mask_o = response_mask_q;
    assign response_all_terminated_o = &response_mask_q;

    assign update_hit = valid_mem[update_index]
        && tag_mem[update_index] == update_block_id_i
        && epoch_mem[update_index] == update_epoch_id_i;
    assign previous_update_mask = update_hit ? mask_mem[update_index] : '0;
    assign merged_update_mask = previous_update_mask | update_new_terminated_i;
    assign query_hit = valid_mem[query_index]
        && tag_mem[query_index] == query_block_id_i
        && epoch_mem[query_index] == query_epoch_id_i;
    assign same_entry_write_through = update_valid_i
        && update_block_id_i == query_block_id_i
        && update_epoch_id_i == query_epoch_id_i;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            response_valid_q <= 1'b0;
            response_mask_q <= '0;
            block_terminated_pulse_o <= 1'b0;
            block_terminated_id_o <= '0;
            block_terminated_epoch_o <= '0;
            // Reset only valid sidecar; data arrays remain reset-free for SRAM.
            for (index = 0; index < ENTRIES; index = index + 1) begin
                valid_mem[index] <= 1'b0;
            end
        end else begin
            block_terminated_pulse_o <= 1'b0;
            if (query_ready_o) begin
                response_valid_q <= query_valid_i;
                if (query_valid_i) begin
                    if (same_entry_write_through) begin
                        response_mask_q <= merged_update_mask;
                    end else begin
                        response_mask_q <= query_hit ? mask_mem[query_index] : '0;
                    end
                end
            end
            if (update_valid_i) begin
                valid_mem[update_index] <= 1'b1;
                tag_mem[update_index] <= update_block_id_i;
                epoch_mem[update_index] <= update_epoch_id_i;
                mask_mem[update_index] <= merged_update_mask;
                if ((&merged_update_mask) && !(&previous_update_mask)) begin
                    block_terminated_pulse_o <= 1'b1;
                    block_terminated_id_o <= update_block_id_i;
                    block_terminated_epoch_o <= update_epoch_id_i;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        assert (ENTRIES > 0 && (ENTRIES & (ENTRIES - 1)) == 0);
        assert (BLOCK_W >= INDEX_W);
        assert (PIXELS == 64);
    end
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        response_valid_o && !response_ready_i
        |=> response_valid_o && $stable(response_mask_o));
`endif

endmodule
