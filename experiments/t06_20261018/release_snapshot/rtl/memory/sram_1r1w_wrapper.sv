// Technology-independent 1R1W SRAM contract. ASIC flows replace this module
// with a node-specific macro wrapper while preserving one-cycle read latency.
module sram_1r1w_wrapper #(
    parameter int unsigned DATA_W = 64,
    parameter int unsigned DEPTH = 1024,
    parameter int unsigned ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic                 clk_i,
    input  logic                 read_en_i,
    input  logic [ADDR_W-1:0]    read_addr_i,
    output logic [DATA_W-1:0]    read_data_o,
    input  logic                 write_en_i,
    input  logic [ADDR_W-1:0]    write_addr_i,
    input  logic [DATA_W-1:0]    write_data_i
);
    logic [DATA_W-1:0] memory [0:DEPTH-1];
    always_ff @(posedge clk_i) begin
        if (read_en_i)
            read_data_o <= write_en_i && write_addr_i == read_addr_i
                ? write_data_i : memory[read_addr_i];
        if (write_en_i)
            memory[write_addr_i] <= write_data_i;
    end
`ifndef SYNTHESIS
    initial begin
        assert (DEPTH > 0 && (DEPTH & (DEPTH - 1)) == 0);
    end
`endif
endmodule
