// AXI4 read engine for the first, mean-only pass of the Gaussian-wise flow.
// Each Gaussian occupies one 128-bit/16-byte record:
//   [31:0]   global GID (frame-local remapping is optional, not required)
//   [58:32]  world X, signed Q10.16
//   [85:59]  world Y, signed Q10.16
//   [112:86] world Z, signed Q10.16
//   [127:113] reserved
// The engine permits one outstanding INCR burst. It never crosses a 4-KiB
// boundary and holds output data stable under downstream backpressure.
module axi4_gaussian_mean_read_dma #(
    parameter int unsigned ADDR_W = 64,
    parameter int unsigned DATA_W = 128,
    parameter int unsigned ID_W = 2,
    parameter int unsigned GID_W = 32,
    parameter int unsigned COORD_W = 27,
    parameter int unsigned MAX_BURST_BEATS = 16,
    parameter logic [ID_W-1:0] AXI_ID = '0
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic start_i,
    input  logic clear_error_i,
    input  logic [ADDR_W-1:0] base_addr_i,
    input  logic [31:0] gaussian_count_i,
    output logic busy_o,
    output logic done_pulse_o,
    output logic error_sticky_o,
    output logic [1:0] error_status_o, // bit0 AXI/protocol, bit1 configuration

    output logic m_valid_o,
    input  logic m_ready_i,
    output logic [GID_W-1:0] m_gid_o,
    output logic signed [COORD_W-1:0] m_world_x_q16_o,
    output logic signed [COORD_W-1:0] m_world_y_q16_o,
    output logic signed [COORD_W-1:0] m_world_z_q16_o,
    output logic m_last_o,
    // Empty frames and failed reads terminate without inventing a Gaussian.
    output logic end_valid_o,
    input  logic end_ready_i,

    output logic [ID_W-1:0] m_axi_arid_o,
    output logic [ADDR_W-1:0] m_axi_araddr_o,
    output logic [7:0] m_axi_arlen_o,
    output logic [2:0] m_axi_arsize_o,
    output logic [1:0] m_axi_arburst_o,
    output logic m_axi_arvalid_o,
    input  logic m_axi_arready_i,
    input  logic [ID_W-1:0] m_axi_rid_i,
    input  logic [DATA_W-1:0] m_axi_rdata_i,
    input  logic [1:0] m_axi_rresp_i,
    input  logic m_axi_rlast_i,
    input  logic m_axi_rvalid_i,
    output logic m_axi_rready_o
);
    localparam int unsigned RECORD_BYTES = DATA_W/8;
    localparam int unsigned SIZE_CODE = $clog2(RECORD_BYTES);
    typedef enum logic [2:0] {S_IDLE,S_ISSUE,S_DATA,S_BETWEEN,S_LAST_WAIT,S_ERROR_DRAIN,S_END} state_t;
    state_t state_q;

    logic [ADDR_W-1:0] next_addr_q;
    logic [31:0] remaining_q;
    logic [8:0] burst_beats_q, beat_index_q;
    logic out_valid_q, out_last_q;
    logic [DATA_W-1:0] out_data_q;
    logic [8:0] planned_beats;
    logic [12:0] bytes_to_boundary;
    logic [8:0] boundary_beats;
    logic r_accept, expected_last, r_error;

    always_comb begin
        bytes_to_boundary = 13'd4096 - {1'b0,next_addr_q[11:0]};
        boundary_beats = bytes_to_boundary >> SIZE_CODE;
        planned_beats = MAX_BURST_BEATS;
        if (remaining_q < planned_beats) planned_beats = remaining_q[8:0];
        if (boundary_beats < planned_beats) planned_beats = boundary_beats;
    end

    assign busy_o = state_q != S_IDLE;
    assign error_sticky_o = |error_status_o;
    assign m_valid_o = out_valid_q;
    assign m_gid_o = out_data_q[31:0];
    assign m_world_x_q16_o = out_data_q[58:32];
    assign m_world_y_q16_o = out_data_q[85:59];
    assign m_world_z_q16_o = out_data_q[112:86];
    assign m_last_o = out_last_q;
    assign end_valid_o = state_q == S_END;

    assign m_axi_arid_o = AXI_ID;
    assign m_axi_araddr_o = next_addr_q;
    assign m_axi_arlen_o = planned_beats - 1'b1;
    assign m_axi_arsize_o = SIZE_CODE[2:0];
    assign m_axi_arburst_o = 2'b01; // INCR
    assign m_axi_arvalid_o = state_q == S_ISSUE;
    // A response is accepted only when the output holding register can take
    // it. During error drain no payload is forwarded.
    assign m_axi_rready_o = (state_q == S_DATA) ? (!out_valid_q || m_ready_i) :
                                (state_q == S_ERROR_DRAIN);
    assign r_accept = m_axi_rvalid_i && m_axi_rready_o;
    assign expected_last = beat_index_q + 1'b1 == burst_beats_q;
    assign r_error = (m_axi_rid_i != AXI_ID) || (m_axi_rresp_i != 2'b00) ||
                     (m_axi_rlast_i != expected_last);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= S_IDLE;
            next_addr_q <= '0;
            remaining_q <= '0;
            burst_beats_q <= '0;
            beat_index_q <= '0;
            out_valid_q <= 1'b0;
            out_last_q <= 1'b0;
            out_data_q <= '0;
            done_pulse_o <= 1'b0;
            error_status_o <= 2'b00;
        end else begin
            done_pulse_o <= 1'b0;
            if (clear_error_i && state_q == S_IDLE) error_status_o <= 2'b00;
            if (out_valid_q && m_ready_i) out_valid_q <= 1'b0;

            case (state_q)
                S_IDLE: if (start_i) begin
                    error_status_o <= 2'b00;
                    next_addr_q <= base_addr_i;
                    remaining_q <= gaussian_count_i;
                    out_valid_q <= 1'b0;
                    if (base_addr_i[SIZE_CODE-1:0] != '0) begin
                        error_status_o[1] <= 1'b1;
                        state_q <= S_END;
                    end else if (gaussian_count_i == 0) begin
                        state_q <= S_END;
                    end else begin
                        state_q <= S_ISSUE;
                    end
                end

                S_ISSUE: if (m_axi_arvalid_o && m_axi_arready_i) begin
                    burst_beats_q <= planned_beats;
                    beat_index_q <= '0;
                    next_addr_q <= next_addr_q + planned_beats * RECORD_BYTES;
                    state_q <= S_DATA;
                end

                S_DATA: if (r_accept) begin
                    if (r_error) begin
                        error_status_o[0] <= 1'b1;
                        out_valid_q <= 1'b0;
                        if (m_axi_rlast_i || expected_last) state_q <= S_END;
                        else state_q <= S_ERROR_DRAIN;
                    end else begin
                        out_data_q <= m_axi_rdata_i;
                        out_last_q <= remaining_q == 1;
                        out_valid_q <= 1'b1;
                        remaining_q <= remaining_q - 1'b1;
                        beat_index_q <= beat_index_q + 1'b1;
                        if (expected_last) begin
                            if (remaining_q == 1) state_q <= S_LAST_WAIT;
                            else state_q <= S_BETWEEN;
                        end
                    end
                end

                S_BETWEEN: if (!out_valid_q || m_ready_i) state_q <= S_ISSUE;

                S_LAST_WAIT: if (out_valid_q && m_ready_i) begin
                    state_q <= S_IDLE;
                    done_pulse_o <= 1'b1;
                end

                S_ERROR_DRAIN: if (r_accept && m_axi_rlast_i) state_q <= S_END;

                S_END: if (end_ready_i) begin
                    state_q <= S_IDLE;
                    done_pulse_o <= 1'b1;
                end

                default: state_q <= S_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        assert (DATA_W == 128);
        assert (COORD_W == 27);
        assert (GID_W == 32);
        assert (MAX_BURST_BEATS >= 1 && MAX_BURST_BEATS <= 256);
    end
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        m_axi_arvalid_o && !m_axi_arready_i |=> $stable({m_axi_araddr_o,m_axi_arlen_o}));
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        m_valid_o && !m_ready_i |=> $stable({m_gid_o,m_world_x_q16_o,m_world_y_q16_o,m_world_z_q16_o,m_last_o}));
`endif
endmodule
