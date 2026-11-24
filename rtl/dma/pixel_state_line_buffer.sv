// Controller-side experiment. One ordered 16-byte request at a time. A line
// is 64 bytes and dirty victims are acknowledged by memory before replacement.
module pixel_state_line_buffer #(
    parameter int INDEX_W=4
)(
    input logic clk_i,rst_ni,
    input logic s_valid_i,output logic s_ready_o,input logic s_flush_i,s_write_i,
    input logic [63:0] s_addr_i,input logic [127:0] s_data_i,input logic [15:0] s_strb_i,
    output logic m_valid_o,input logic m_ready_i,output logic m_error_o,output logic [127:0] m_data_o,
    output logic mem_valid_o,input logic mem_ready_i,output logic mem_write_o,
    output logic [63:0] mem_addr_o,output logic [511:0] mem_data_o,
    input logic ret_valid_i,output logic ret_ready_o,input logic ret_error_i,input logic [511:0] ret_data_i
);
    localparam N=1<<INDEX_W;
    typedef enum logic [3:0] {IDLE,LOOKUP,SCAN,EVICT,EVICT_WAIT,FILL,FILL_WAIT,RESP} state_t;
    state_t state_q;
    logic [N-1:0] valid_q,dirty_q;
    logic [511:0] line_mem[N];
    logic [63:6+INDEX_W] tag_mem[N];
    logic [63:0] addr_q;
    logic [127:0] data_q,response_q;
    logic [15:0] strb_q;
    logic write_q,flush_q,error_q;
    logic [INDEX_W-1:0] scan_q;
    wire [INDEX_W-1:0] idx=flush_q?scan_q:addr_q[6+:INDEX_W];
    wire [1:0] sector=addr_q[5:4];
    assign s_ready_o=state_q==IDLE;
    assign m_valid_o=state_q==RESP;
    assign m_error_o=error_q;
    assign m_data_o=response_q;
    assign mem_valid_o=(state_q==EVICT || state_q==FILL);
    assign mem_write_o=state_q==EVICT;
    assign mem_addr_o=mem_write_o?{tag_mem[idx],idx,6'b0}:{addr_q[63:6],6'b0};
    assign mem_data_o=line_mem[idx];
    assign ret_ready_o=state_q==EVICT_WAIT || state_q==FILL_WAIT;

    always_ff @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin
            state_q<=IDLE;valid_q<='0;dirty_q<='0;
        end else case(state_q)
            IDLE:if(s_valid_i)begin
                addr_q<=s_addr_i;data_q<=s_data_i;strb_q<=s_strb_i;
                write_q<=s_write_i;flush_q<=s_flush_i;scan_q<=0;
                response_q<=0;error_q<=0;
                if(s_flush_i)state_q<=SCAN;
                else if(s_addr_i[3:0]!=0)begin error_q<=1;state_q<=RESP;end
                else state_q<=LOOKUP;
            end
            LOOKUP:begin
                if(valid_q[idx] && tag_mem[idx]==addr_q[63:6+INDEX_W])begin
                    if(write_q)begin
                        if(|strb_q)dirty_q[idx]<=1;
                    end else response_q<=line_mem[idx][sector*128+:128];
                    state_q<=RESP;
                end else state_q<=valid_q[idx]&&dirty_q[idx]?EVICT:FILL;
            end
            SCAN:begin
                if(valid_q[idx]&&dirty_q[idx])state_q<=EVICT;
                else begin
                    valid_q[idx]<=0;
                    if(&scan_q)state_q<=RESP;
                    else scan_q<=scan_q+1'b1;
                end
            end
            EVICT:if(mem_ready_i)state_q<=EVICT_WAIT;
            EVICT_WAIT:if(ret_valid_i)begin
                if(ret_error_i)begin error_q<=1;state_q<=RESP;end
                else begin
                    dirty_q[idx]<=0;valid_q[idx]<=0;
                    if(!flush_q)state_q<=FILL;
                    else if(&scan_q)state_q<=RESP;
                    else begin scan_q<=scan_q+1'b1;state_q<=SCAN;end
                end
            end
            FILL:if(mem_ready_i)state_q<=FILL_WAIT;
            FILL_WAIT:if(ret_valid_i)begin
                if(ret_error_i)begin error_q<=1;state_q<=RESP;end
                else begin valid_q[idx]<=1;dirty_q[idx]<=0;state_q<=LOOKUP;end
            end
            RESP:if(m_ready_i)state_q<=IDLE;
            default:state_q<=IDLE;
        endcase
    end
    always_ff @(posedge clk_i)begin
        if(state_q==FILL_WAIT && ret_valid_i && !ret_error_i)begin
            tag_mem[idx]<=addr_q[63:6+INDEX_W];
            line_mem[idx]<=ret_data_i;
        end else if(state_q==LOOKUP && valid_q[idx] && tag_mem[idx]==addr_q[63:6+INDEX_W] && write_q)begin
            for(int byte_id=0;byte_id<16;byte_id++)
                if(strb_q[byte_id])line_mem[idx][sector*128+byte_id*8+:8]<=data_q[byte_id*8+:8];
        end
    end
endmodule
