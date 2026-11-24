// A conservative cache of committed per-pixel termination state. A tag miss
// runs the normal path. Epoch transitions invalidate only the valid sidecar,
// including epoch wrap; payload/tag/mask arrays have no reset requirement.
module raster_pixel_termination_filter #(
    parameter int unsigned PAYLOAD_W=104, BLOCK_W=32, EPOCH_W=16,
    parameter int unsigned ENTRIES=256,
    parameter int unsigned INDEX_W=(ENTRIES<=1)?1:$clog2(ENTRIES)
) (
    input logic clk_i,rst_ni,
    input logic task_valid_i,output logic task_ready_o,
    input logic[PAYLOAD_W-1:0] task_payload_i,
    input logic[BLOCK_W-1:0] task_block_id_i,
    input logic[EPOCH_W-1:0] task_epoch_id_i,
    input logic[5:0] task_pixel_i,
    output logic live_valid_o,input logic live_ready_i,
    output logic[PAYLOAD_W-1:0] live_payload_o,
    input logic update_valid_i,
    input logic[BLOCK_W-1:0] update_block_id_i,
    input logic[EPOCH_W-1:0] update_epoch_id_i,
    input logic[63:0] update_mask_i,
    output logic skipped_pulse_o,block_terminated_pulse_o
);
    logic[BLOCK_W-1:0] tag_mem[0:ENTRIES-1];
    logic[63:0] mask_mem[0:ENTRIES-1];
    logic[ENTRIES-1:0] valid_q;
    logic epoch_valid_q;
    logic[EPOCH_W-1:0] epoch_q;
    logic response_valid_q,response_skip_q;
    logic[PAYLOAD_W-1:0] payload_q;
    logic[INDEX_W-1:0] query_index,update_index;
    logic epoch_match,response_ready,switch_epoch,update_accept;
    logic update_hit,query_hit,same_update;
    logic[63:0] previous_mask,merged_mask,query_mask;

    assign query_index=task_block_id_i[INDEX_W-1:0];
    assign update_index=update_block_id_i[INDEX_W-1:0];
    assign epoch_match=epoch_valid_q&&task_epoch_id_i==epoch_q;
    assign response_ready=!response_valid_q||response_skip_q||live_ready_i;
    assign switch_epoch=task_valid_i&&!epoch_match&&response_ready;
    // One conservative bubble at a new epoch; old response can finish here.
    assign task_ready_o=epoch_match&&response_ready;
    assign live_valid_o=response_valid_q&&!response_skip_q;
    assign live_payload_o=payload_q;
    assign skipped_pulse_o=response_valid_q&&response_skip_q;
    assign update_accept=update_valid_i&&epoch_valid_q&&update_epoch_id_i==epoch_q&&!switch_epoch;
    assign update_hit=valid_q[update_index]&&tag_mem[update_index]==update_block_id_i;
    assign previous_mask=update_hit?mask_mem[update_index]:64'b0;
    assign merged_mask=previous_mask|update_mask_i;
    assign query_hit=valid_q[query_index]&&tag_mem[query_index]==task_block_id_i;
    assign same_update=update_accept&&update_block_id_i==task_block_id_i;
    assign query_mask=same_update?merged_mask:(query_hit?mask_mem[query_index]:64'b0);

    always_ff@(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin
            valid_q<='0;epoch_valid_q<=0;epoch_q<='0;
            response_valid_q<=0;response_skip_q<=0;
            block_terminated_pulse_o<=0;
        end else begin
            block_terminated_pulse_o<=0;
            if(response_ready)begin
                response_valid_q<=task_valid_i&&task_ready_o;
                if(task_valid_i&&task_ready_o)
                    response_skip_q<=query_mask[task_pixel_i];
            end
            if(switch_epoch)begin
                valid_q<='0;epoch_valid_q<=1;epoch_q<=task_epoch_id_i;
            end else if(update_accept)begin
                valid_q[update_index]<=1;
                block_terminated_pulse_o<=(&merged_mask)&&!(&previous_mask);
            end
        end
    end
    // Enables and valid sidecar protect uninitialized data, keeping reset out
    // of the large data arrays and payload register.
    always_ff@(posedge clk_i)begin
        if(rst_ni&&task_valid_i&&task_ready_o)payload_q<=task_payload_i;
        if(rst_ni&&update_accept)begin
            tag_mem[update_index]<=update_block_id_i;
            mask_mem[update_index]<=merged_mask;
        end
    end
`ifndef SYNTHESIS
    initial begin
        assert(ENTRIES>=2&&(ENTRIES&(ENTRIES-1))==0);
        assert(BLOCK_W>=INDEX_W);
    end
    assert property(@(posedge clk_i)disable iff(!rst_ni)
        live_valid_o&&!live_ready_i |=> live_valid_o&&$stable(live_payload_o));
`endif
endmodule
