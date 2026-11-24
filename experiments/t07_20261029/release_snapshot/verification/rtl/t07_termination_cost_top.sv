// Mapping-only wrapper reproduces the production 292-bit filter payload and
// the legacy coarse+fine termination structures for a same-interface ablation.
module t07_termination_cost_top #(parameter bit PIXEL_SKIP=0)(
 input logic clk_i,rst_ni,task_valid_i,output logic task_ready_o,
 input logic[291:0] task_payload_i,input logic[31:0] task_block_id_i,
 input logic[15:0] task_epoch_id_i,input logic[5:0] task_pixel_i,
 output logic live_valid_o,input logic live_ready_i,output logic[291:0] live_payload_o,
 input logic update_valid_i,input logic[31:0] update_block_id_i,
 input logic[15:0] update_epoch_id_i,input logic[63:0] update_mask_i,
 output logic skipped_pulse_o,block_terminated_pulse_o
);
 generate if(PIXEL_SKIP)begin:g_new
   raster_pixel_termination_filter #(.PAYLOAD_W(292),.BLOCK_W(32),.EPOCH_W(16))u_filter(.*);
 end else begin:g_old
   logic[31:0]full_block;logic[15:0]full_epoch;
   pixel_termination_mask #(.BLOCK_W(32),.EPOCH_W(16))u_mask(
     .clk_i(clk_i),.rst_ni(rst_ni),.query_valid_i(1'b0),.query_ready_o(),
     .query_block_id_i(32'b0),.query_epoch_id_i(16'b0),.response_valid_o(),.response_ready_i(1'b1),
     .response_mask_o(),.response_all_terminated_o(),.update_valid_i(update_valid_i),
     .update_block_id_i(update_block_id_i),.update_epoch_id_i(update_epoch_id_i),.update_new_terminated_i(update_mask_i),
     .block_terminated_pulse_o(block_terminated_pulse_o),.block_terminated_id_o(full_block),.block_terminated_epoch_o(full_epoch));
   raster_termination_filter #(.PAYLOAD_W(292),.BLOCK_W(32),.EPOCH_W(16))u_filter(
     .clk_i(clk_i),.rst_ni(rst_ni),.task_valid_i(task_valid_i),.task_ready_o(task_ready_o),
     .task_payload_i(task_payload_i),.task_block_id_i(task_block_id_i),.task_epoch_id_i(task_epoch_id_i),
     .live_valid_o(live_valid_o),.live_ready_i(live_ready_i),.live_payload_o(live_payload_o),
     .term_update_valid_i(block_terminated_pulse_o),.term_update_block_id_i(full_block),
     .term_update_epoch_id_i(full_epoch),.skipped_pulse_o(skipped_pulse_o));
 end endgenerate
endmodule
