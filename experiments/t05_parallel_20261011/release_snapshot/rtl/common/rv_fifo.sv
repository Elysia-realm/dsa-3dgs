// Small synthesizable ready/valid FIFO. Storage has no reset assignment;
// validity is represented only by read/write pointers and occupancy.
module rv_fifo #(
    parameter int unsigned DATA_W=32,parameter int unsigned DEPTH=16,
    parameter int unsigned PTR_W=(DEPTH<=2)?1:$clog2(DEPTH),
    parameter int unsigned COUNT_W=$clog2(DEPTH+1)
) (
    input logic clk_i,input logic rst_ni,
    input logic s_valid_i,output logic s_ready_o,input logic[DATA_W-1:0]s_data_i,
    output logic m_valid_o,input logic m_ready_i,output logic[DATA_W-1:0]m_data_o,
    output logic[COUNT_W-1:0]occupancy_o
);
    logic[DATA_W-1:0]mem[0:DEPTH-1];logic[PTR_W-1:0]read_q,write_q;logic push,pop;
    assign s_ready_o=occupancy_o<DEPTH;assign m_valid_o=occupancy_o!=0;
    assign m_data_o=mem[read_q];assign push=s_valid_i&&s_ready_o;assign pop=m_valid_o&&m_ready_i;
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin read_q<='0;write_q<='0;occupancy_o<='0;end
      else begin
        if(push)begin mem[write_q]<=s_data_i;if(write_q==DEPTH-1)write_q<='0;else write_q<=write_q+1'b1;end
        if(pop)begin if(read_q==DEPTH-1)read_q<='0;else read_q<=read_q+1'b1;end
        case({push,pop})2'b10:occupancy_o<=occupancy_o+1'b1;2'b01:occupancy_o<=occupancy_o-1'b1;default:occupancy_o<=occupancy_o;endcase
      end
    end
`ifndef SYNTHESIS
    initial assert(DEPTH>=2);
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_valid_o&&!m_ready_i|=>m_valid_o&&$stable(m_data_o));
`endif
endmodule
