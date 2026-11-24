// Join an already Gaussian-ordered projection block stream with one FIFO entry
// of SH color per Gaussian. The color head is held across all blocks and popped
// only with that Gaussian's accepted last block/cull event.
module ordered_projection_sh_join #(
    parameter int unsigned TASK_W=384,parameter int unsigned META_W=64,
    parameter int unsigned SEQ_W=16,parameter int unsigned COLOR_W=3*13+2,
    parameter int unsigned SH_DEPTH=16,parameter int unsigned COUNT_W=$clog2(SH_DEPTH+1)
) (
    input logic clk_i,input logic rst_ni,
    input logic projection_valid_i,output logic projection_ready_o,input logic[TASK_W-1:0]projection_data_i,
    input logic projection_first_i,projection_last_i,projection_culled_i,
    input logic sh_valid_i,output logic sh_ready_o,input logic[META_W-1:0]sh_meta_i,
    input logic[COLOR_W-1:0]sh_color_i,
    output logic m_valid_o,input logic m_ready_i,output logic[TASK_W-1:0]m_projection_data_o,
    output logic[COLOR_W-1:0]m_color_o,output logic m_first_o,m_last_o,m_culled_o,
    output logic sequence_mismatch_o,output logic[COUNT_W-1:0]sh_occupancy_o,output logic empty_o
);
    localparam int unsigned FIFO_W=META_W+COLOR_W;
    logic fifo_valid,fifo_ready;logic[FIFO_W-1:0]fifo_data;logic[META_W-1:0]head_meta,projection_meta;
    logic output_fire,format_error;logic mismatch_q;
    rv_fifo #(.DATA_W(FIFO_W),.DEPTH(SH_DEPTH))u_sh_fifo(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(sh_valid_i),.s_ready_o(sh_ready_o),.s_data_i({sh_meta_i,sh_color_i}),
      .m_valid_o(fifo_valid),.m_ready_i(fifo_ready),.m_data_o(fifo_data),.occupancy_o(sh_occupancy_o));
    assign {head_meta,m_color_o}=fifo_data;assign projection_meta=projection_data_i[TASK_W-1-:META_W];
    assign m_valid_o=projection_valid_i&&fifo_valid&&head_meta==projection_meta;
    assign projection_ready_o=fifo_valid&&head_meta==projection_meta&&m_ready_i;
    assign m_projection_data_o=projection_data_i;assign m_first_o=projection_first_i;
    assign m_last_o=projection_last_i;assign m_culled_o=projection_culled_i;
    assign output_fire=m_valid_o&&m_ready_i;assign fifo_ready=output_fire&&projection_last_i;
    assign format_error=projection_valid_i&&((projection_culled_i&&(!projection_first_i||!projection_last_i))||
      (!projection_culled_i&&projection_first_i&&projection_last_i&&1'b0));
    assign sequence_mismatch_o=mismatch_q;assign empty_o=sh_occupancy_o==0;
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)mismatch_q<=0;
      else if((projection_valid_i&&fifo_valid&&head_meta!=projection_meta)||format_error)mismatch_q<=1;
    end
`ifndef SYNTHESIS
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_valid_o&&!m_ready_i|=>m_valid_o&&
      $stable({m_projection_data_o,m_color_o,m_first_o,m_last_o,m_culled_o}));
`endif
endmodule
