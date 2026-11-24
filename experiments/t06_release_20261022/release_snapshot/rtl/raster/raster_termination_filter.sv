// Queries block termination state before expensive attribute fetch and alpha
// issue. Query and payload are accepted atomically and rejoin after the table's
// one-cycle lookup. Terminated tasks are consumed locally; live tasks continue
// through the output ready/valid stream.
module raster_termination_filter #(
    parameter int unsigned PAYLOAD_W       = 104,
    parameter int unsigned BLOCK_W         = 24,
    parameter int unsigned EPOCH_W         = 16,
    parameter int unsigned NUM_BANKS       = 4,
    parameter int unsigned ROWS_PER_BANK   = 256
) (
    input  logic                 clk_i,
    input  logic                 rst_ni,
    input  logic                 task_valid_i,
    output logic                 task_ready_o,
    input  logic [PAYLOAD_W-1:0] task_payload_i,
    input  logic [BLOCK_W-1:0]   task_block_id_i,
    input  logic [EPOCH_W-1:0]   task_epoch_id_i,
    output logic                 live_valid_o,
    input  logic                 live_ready_i,
    output logic [PAYLOAD_W-1:0] live_payload_o,
    input  logic                 term_update_valid_i,
    input  logic [BLOCK_W-1:0]   term_update_block_id_i,
    input  logic [EPOCH_W-1:0]   term_update_epoch_id_i,
    output logic                 skipped_pulse_o
);

    logic table_query_valid;
    logic table_query_ready;
    logic table_response_valid;
    logic table_response_ready;
    logic table_terminated;
    logic payload_s_valid;
    logic payload_s_ready;
    logic payload_m_valid;
    logic payload_m_ready;
    logic joined_valid;
    logic joined_consume;

    // Atomic fork: neither branch accepts unless the other branch is ready.
    assign task_ready_o      = table_query_ready && payload_s_ready;
    assign table_query_valid = task_valid_i && payload_s_ready;
    assign payload_s_valid   = task_valid_i && table_query_ready;

    assign joined_valid = table_response_valid && payload_m_valid;
    assign live_valid_o = joined_valid && !table_terminated;
    assign joined_consume = joined_valid && (table_terminated || live_ready_i);
    assign table_response_ready = payload_m_valid && (table_terminated || live_ready_i);
    assign payload_m_ready = table_response_valid && (table_terminated || live_ready_i);
    assign skipped_pulse_o = joined_consume && table_terminated;

    rv_reg_slice #(.DATA_W(PAYLOAD_W)) u_payload_pipe (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .s_valid_i(payload_s_valid), .s_ready_o(payload_s_ready),
        .s_data_i(task_payload_i),
        .m_valid_o(payload_m_valid), .m_ready_i(payload_m_ready),
        .m_data_o(live_payload_o)
    );

    block_termination_table #(
        .BLOCK_W(BLOCK_W), .EPOCH_W(EPOCH_W),
        .NUM_BANKS(NUM_BANKS), .ROWS_PER_BANK(ROWS_PER_BANK)
    ) u_table (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .query_valid_i(table_query_valid), .query_ready_o(table_query_ready),
        .query_block_id_i(task_block_id_i), .query_epoch_id_i(task_epoch_id_i),
        .response_valid_o(table_response_valid), .response_ready_i(table_response_ready),
        .response_terminated_o(table_terminated),
        .update_valid_i(term_update_valid_i),
        .update_block_id_i(term_update_block_id_i),
        .update_epoch_id_i(term_update_epoch_id_i)
    );

`ifndef SYNTHESIS
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        live_valid_o && !live_ready_i |=> live_valid_o && $stable(live_payload_o));
`endif

endmodule
