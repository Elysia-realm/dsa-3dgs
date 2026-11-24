// Tile-local image-state store with full pixel/epoch tags. The active frame or
// tile working set must not exceed ENTRIES; the frame controller enforces this
// until a backing-store writeback cache is added. A tag miss
// returns the clear state (RGB=0, T=1.0 represented by 16'hffff). Reset clears
// only valid bits so data arrays remain replaceable by SRAM macros.
module image_state_store #(
    parameter int unsigned PIXEL_W = 12,
    parameter int unsigned EPOCH_W = 16,
    parameter int unsigned ENTRIES = 4096,
    parameter int unsigned INDEX_W = (ENTRIES <= 1) ? 1 : $clog2(ENTRIES)
) (
    input  logic                   clk_i,
    input  logic                   rst_ni,
    input  logic                   query_valid_i,
    output logic                   query_ready_o,
    input  logic [PIXEL_W-1:0]     query_pixel_id_i,
    input  logic [EPOCH_W-1:0]     query_epoch_id_i,
    output logic                   response_valid_o,
    input  logic                   response_ready_i,
    output logic [12:0]            response_r_q12_o,
    output logic [12:0]            response_g_q12_o,
    output logic [12:0]            response_b_q12_o,
    output logic [15:0]            response_t_q16_o,
    input  logic                   update_valid_i,
    input  logic [PIXEL_W-1:0]     update_pixel_id_i,
    input  logic [EPOCH_W-1:0]     update_epoch_id_i,
    input  logic [12:0]            update_r_q12_i,
    input  logic [12:0]            update_g_q12_i,
    input  logic [12:0]            update_b_q12_i,
    input  logic [15:0]            update_t_q16_i
);
    logic [PIXEL_W-1:0] tag_mem [0:ENTRIES-1];
    logic [EPOCH_W-1:0] epoch_mem [0:ENTRIES-1];
    logic [12:0] r_mem [0:ENTRIES-1];
    logic [12:0] g_mem [0:ENTRIES-1];
    logic [12:0] b_mem [0:ENTRIES-1];
    logic [15:0] t_mem [0:ENTRIES-1];
    logic valid_mem [0:ENTRIES-1];
    logic [INDEX_W-1:0] query_index, update_index;
    logic query_hit, write_through;
    logic response_valid_q;
    logic [12:0] response_r_q, response_g_q, response_b_q;
    logic [15:0] response_t_q;
    integer index;

    assign query_index = query_pixel_id_i[INDEX_W-1:0];
    assign update_index = update_pixel_id_i[INDEX_W-1:0];
    assign query_hit = valid_mem[query_index]
        && tag_mem[query_index] == query_pixel_id_i
        && epoch_mem[query_index] == query_epoch_id_i;
    assign write_through = update_valid_i
        && update_pixel_id_i == query_pixel_id_i
        && update_epoch_id_i == query_epoch_id_i;
    assign query_ready_o = !response_valid_q || response_ready_i;
    assign response_valid_o = response_valid_q;
    assign response_r_q12_o = response_r_q;
    assign response_g_q12_o = response_g_q;
    assign response_b_q12_o = response_b_q;
    assign response_t_q16_o = response_t_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            response_valid_q <= 1'b0;
            response_r_q <= '0;
            response_g_q <= '0;
            response_b_q <= '0;
            response_t_q <= 16'hffff;
            for (index = 0; index < ENTRIES; index = index + 1)
                valid_mem[index] <= 1'b0;
        end else begin
            if (query_ready_o) begin
                response_valid_q <= query_valid_i;
                if (query_valid_i) begin
                    if (write_through) begin
                        response_r_q <= update_r_q12_i;
                        response_g_q <= update_g_q12_i;
                        response_b_q <= update_b_q12_i;
                        response_t_q <= update_t_q16_i;
                    end else if (query_hit) begin
                        response_r_q <= r_mem[query_index];
                        response_g_q <= g_mem[query_index];
                        response_b_q <= b_mem[query_index];
                        response_t_q <= t_mem[query_index];
                    end else begin
                        response_r_q <= '0;
                        response_g_q <= '0;
                        response_b_q <= '0;
                        response_t_q <= 16'hffff;
                    end
                end
            end
            if (update_valid_i) begin
                valid_mem[update_index] <= 1'b1;
                tag_mem[update_index] <= update_pixel_id_i;
                epoch_mem[update_index] <= update_epoch_id_i;
                r_mem[update_index] <= update_r_q12_i;
                g_mem[update_index] <= update_g_q12_i;
                b_mem[update_index] <= update_b_q12_i;
                t_mem[update_index] <= update_t_q16_i;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        assert (ENTRIES > 0 && (ENTRIES & (ENTRIES - 1)) == 0);
        assert (PIXEL_W >= INDEX_W);
    end
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        response_valid_o && !response_ready_i
        |=> response_valid_o && $stable({response_r_q12_o, response_g_q12_o,
                                         response_b_q12_o, response_t_q16_o}));
`endif
endmodule
