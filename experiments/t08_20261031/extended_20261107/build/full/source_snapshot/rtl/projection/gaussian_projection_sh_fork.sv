// Atomic one-to-two transaction fork. Each branch accepts exactly once even
// when projection and SH apply unrelated backpressure. A new Gaussian cannot
// overwrite the held full attribute record until both branches have consumed it.
module gaussian_projection_sh_fork #(
    parameter int unsigned PROJ_W=256,parameter int unsigned SH_W=1024,
    parameter int unsigned DEPTH=4,parameter int unsigned COUNT_W=$clog2(DEPTH+1)
) (
    input logic clk_i,input logic rst_ni,
    input logic s_valid_i,output logic s_ready_o,
    input logic[PROJ_W-1:0]s_projection_data_i,input logic[SH_W-1:0]s_sh_data_i,
    output logic projection_valid_o,input logic projection_ready_i,output logic[PROJ_W-1:0]projection_data_o,
    output logic sh_valid_o,input logic sh_ready_i,output logic[SH_W-1:0]sh_data_o,
    output logic empty_o,output logic[COUNT_W-1:0]occupancy_o
);
    logic projection_fifo_ready,sh_fifo_ready;logic[COUNT_W-1:0]projection_occupancy,sh_occupancy;
    assign s_ready_o=projection_fifo_ready&&sh_fifo_ready;
    rv_fifo #(.DATA_W(PROJ_W),.DEPTH(DEPTH))u_projection_fifo(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i&&sh_fifo_ready),.s_ready_o(projection_fifo_ready),
      .s_data_i(s_projection_data_i),.m_valid_o(projection_valid_o),.m_ready_i(projection_ready_i),
      .m_data_o(projection_data_o),.occupancy_o(projection_occupancy));
    rv_fifo #(.DATA_W(SH_W),.DEPTH(DEPTH))u_sh_fifo(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i&&projection_fifo_ready),.s_ready_o(sh_fifo_ready),
      .s_data_i(s_sh_data_i),.m_valid_o(sh_valid_o),.m_ready_i(sh_ready_i),
      .m_data_o(sh_data_o),.occupancy_o(sh_occupancy));
    assign occupancy_o=projection_occupancy>=sh_occupancy?projection_occupancy:sh_occupancy;
    assign empty_o=projection_occupancy==0&&sh_occupancy==0;
`ifndef SYNTHESIS
    // Both writes are qualified by the other branch's capacity, so a source
    // acceptance can never enqueue only one copy of the transaction.
    assert property(@(posedge clk_i)disable iff(!rst_ni)s_valid_i&&s_ready_o|->projection_fifo_ready&&sh_fifo_ready);
`endif
endmodule
