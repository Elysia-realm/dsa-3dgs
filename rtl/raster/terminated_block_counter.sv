// Commitment of a first T<=7 crossing identifies one previously live pixel.
// A full 8x8 block therefore needs 64 such events within the same frame.
module terminated_block_counter #(
    parameter int ADDRESS_BITS=15, BLOCK_W=32
) (
    input logic clk_i,rst_ni,new_frame_i,
    input logic update_i,input logic [BLOCK_W-1:0] update_block_i,query_block_i,
    output logic query_full_o
);
    localparam int ENTRIES=1<<ADDRESS_BITS;
    logic [5:0] counts[ENTRIES];
    logic full[ENTRIES];
    logic sweeping_q,pending_q,forward_q;
    logic [ADDRESS_BITS-1:0] clear_addr_q,pending_addr_q;
    logic [5:0] read_q,forward_count_q,current_count,next_count;
    wire [ADDRESS_BITS-1:0] update_addr=update_block_i[ADDRESS_BITS-1:0];
    wire learn=update_i && update_block_i<ENTRIES && !sweeping_q && !new_frame_i;
    assign current_count=forward_q ? forward_count_q : read_q;
    assign next_count=current_count+6'd1;
    assign query_full_o=rst_ni && !new_frame_i && !sweeping_q && query_block_i<ENTRIES
                        && full[query_block_i[ADDRESS_BITS-1:0]];

    // Data arrays use a sequential sweep. During a sweep the table gives
    // no hints. Dropping crossings in that interval can only delay a proof.
    always_ff @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin sweeping_q<=1;clear_addr_q<='0;pending_q<=0;end
        else if(new_frame_i)begin sweeping_q<=1;clear_addr_q<='0;pending_q<=0;end
        else if(sweeping_q)begin
            if(&clear_addr_q)sweeping_q<=0;
            clear_addr_q<=clear_addr_q+1'b1;
            pending_q<=0;
        end else pending_q<=learn;
    end
    always_ff @(posedge clk_i)if(rst_ni && !new_frame_i)begin
        if(sweeping_q)begin
            counts[clear_addr_q]<='0;
            full[clear_addr_q]<=0;
        end else begin
            if(learn)begin
                read_q<=counts[update_addr];
                pending_addr_q<=update_addr;
                forward_q<=pending_q && pending_addr_q==update_addr;
                forward_count_q<=next_count;
            end
            if(pending_q)begin
                counts[pending_addr_q]<=next_count;
                if(&current_count)full[pending_addr_q]<=1;
            end
        end
    end
endmodule
