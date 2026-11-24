// Descriptor-only QSU scratch port. Two contiguous banks, capacity records
// each; 128-bit records. Burst reader and independent multi-outstanding writer.
// Writes are single beat (scatter destinations may differ every cycle), with
// AW/W independently held and a 16-entry ordered B-retirement queue.
module axi4_qsu_scratch_dma #(
    parameter int ADDR_W=64,ID_W=2,WRITE_DEPTH=16,
    parameter int PTR_W=$clog2(WRITE_DEPTH),COUNT_W=$clog2(WRITE_DEPTH+1)
) (
    input logic clk_i,rst_ni,clear_i,
    input logic [ADDR_W-1:0] base_i,input logic [31:0] capacity_i,
    input logic rd_valid_i,output logic rd_ready_o,input logic rd_bank_i,
    input logic [31:0] rd_offset_i,rd_count_i,
    output logic r_valid_o,input logic r_ready_i,output logic [127:0] r_data_o,
    output logic r_last_o,rd_busy_o,
    input logic wr_valid_i,output logic wr_ready_o,input logic wr_bank_i,
    input logic [31:0] wr_offset_i,input logic [127:0] wr_data_i,
    output logic wr_busy_o,error_o,output logic [1:0] error_status_o,
    output logic [ID_W-1:0] m_axi_arid_o,output logic [ADDR_W-1:0] m_axi_araddr_o,
    output logic [7:0] m_axi_arlen_o,output logic [2:0] m_axi_arsize_o,
    output logic [1:0] m_axi_arburst_o,output logic m_axi_arvalid_o,input logic m_axi_arready_i,
    input logic [ID_W-1:0] m_axi_rid_i,input logic [127:0] m_axi_rdata_i,
    input logic [1:0] m_axi_rresp_i,input logic m_axi_rlast_i,m_axi_rvalid_i,output logic m_axi_rready_o,
    output logic [ID_W-1:0] m_axi_awid_o,output logic [ADDR_W-1:0] m_axi_awaddr_o,
    output logic [7:0] m_axi_awlen_o,output logic [2:0] m_axi_awsize_o,
    output logic [1:0] m_axi_awburst_o,output logic m_axi_awvalid_o,input logic m_axi_awready_i,
    output logic [127:0] m_axi_wdata_o,output logic [15:0] m_axi_wstrb_o,
    output logic m_axi_wlast_o,m_axi_wvalid_o,input logic m_axi_wready_i,
    input logic [ID_W-1:0] m_axi_bid_i,input logic [1:0] m_axi_bresp_i,
    input logic m_axi_bvalid_i,output logic m_axi_bready_o
);
    typedef enum logic [2:0] {R_IDLE,R_ADDR,R_DATA,R_NEXT,R_LAST,R_DRAIN} read_state_t;
    read_state_t rs;
    logic [ADDR_W-1:0] next_addr;
    logic [31:0] remaining;
    logic [8:0] beats,beat_index,planned,boundary;
    logic [12:0] boundary_bytes;
    logic rexpected,rerror,rfire;
    logic [1:0] read_error,write_error;
    logic [ADDR_W:0] end_address;
    logic bad_config;
    assign end_address={1'b0,base_i}+( ( (ADDR_W+1)'(capacity_i))<<5);
    assign bad_config=base_i[3:0]!=0||end_address[ADDR_W];
    assign error_status_o=read_error|write_error;assign error_o=|error_status_o;
    assign rd_ready_o=rs==R_IDLE;
    assign rd_busy_o=rs!=R_IDLE||r_valid_o;
    always_comb begin
        boundary_bytes=13'd4096-{1'b0,next_addr[11:0]};boundary=boundary_bytes>>4;
        planned=16;if(remaining<planned)planned=remaining[8:0];if(boundary<planned)planned=boundary;
    end
    assign m_axi_arid_o='0;assign m_axi_araddr_o=next_addr;assign m_axi_arlen_o=8'(planned-1);
    assign m_axi_arsize_o=4;assign m_axi_arburst_o=1;assign m_axi_arvalid_o=rs==R_ADDR;
    assign m_axi_rready_o=rs==R_DRAIN||(rs==R_DATA&&(!r_valid_o||r_ready_i));
    assign rfire=m_axi_rvalid_i&&m_axi_rready_o;
    assign rexpected=beat_index+1==beats;
    assign rerror=m_axi_rid_i!=0||m_axi_rresp_i!=0||m_axi_rlast_i!=rexpected;
    always_ff @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin rs<=R_IDLE;next_addr<=0;remaining<=0;beats<=0;beat_index<=0;r_valid_o<=0;r_data_o<=0;r_last_o<=0;read_error<=0;end
        else begin
            if(clear_i&&!rd_busy_o)read_error<=0;
            if(r_valid_o&&r_ready_i)r_valid_o<=0;
            case(rs)
                R_IDLE:if(rd_valid_i)begin
                    if(bad_config||rd_count_i==0||{1'b0,rd_offset_i}+{1'b0,rd_count_i}>{1'b0,capacity_i})read_error[1]<=1;
                    else begin
                        next_addr<=base_i+((ADDR_W'(rd_offset_i)+(rd_bank_i?ADDR_W'(capacity_i):0))<<4);
                        remaining<=rd_count_i;rs<=R_ADDR;
                    end
                end
                R_ADDR:if(m_axi_arready_i)begin beats<=planned;beat_index<=0;next_addr<=next_addr+(ADDR_W'(planned)<<4);rs<=R_DATA;end
                R_DATA:if(rfire)begin
                    if(rerror)begin
                        read_error[0]<=1;r_valid_o<=0;
                        rs<=(m_axi_rlast_i||rexpected)?R_IDLE:R_DRAIN;
                    end else begin
                        r_valid_o<=1;r_data_o<=m_axi_rdata_i;r_last_o<=remaining==1;
                        remaining<=remaining-1;beat_index<=beat_index+1;
                        if(rexpected)rs<=remaining==1?R_LAST:R_NEXT;
                    end
                end
                R_NEXT:if(!r_valid_o||r_ready_i)rs<=R_ADDR;
                R_LAST:if(r_valid_o&&r_ready_i)rs<=R_IDLE;
                R_DRAIN:if(rfire&&m_axi_rlast_i)rs<=R_IDLE;
                default:rs<=R_IDLE;
            endcase
        end
    end
    logic [ADDR_W-1:0] addr_mem[WRITE_DEPTH];logic [127:0] data_mem[WRITE_DEPTH];
    logic [PTR_W-1:0] put_ptr,issue_ptr,retire_ptr;
    logic [COUNT_W-1:0] used,outstanding;
    logic aw_done,w_done,issue_valid,aw_fire,w_fire,issue_fire,b_fire,enqueue;
    assign wr_ready_o=used<WRITE_DEPTH||b_fire;
    assign enqueue=wr_valid_i&&wr_ready_o&&!bad_config&&wr_offset_i<capacity_i;
    assign issue_valid=used>outstanding;
    assign m_axi_awid_o='0;assign m_axi_awaddr_o=addr_mem[issue_ptr];
    assign m_axi_awlen_o=0;assign m_axi_awsize_o=4;assign m_axi_awburst_o=1;
    assign m_axi_awvalid_o=issue_valid&&!aw_done;
    assign m_axi_wdata_o=data_mem[issue_ptr];assign m_axi_wstrb_o='1;
    assign m_axi_wlast_o=1;assign m_axi_wvalid_o=issue_valid&&!w_done;
    assign aw_fire=m_axi_awvalid_o&&m_axi_awready_i;assign w_fire=m_axi_wvalid_o&&m_axi_wready_i;
    assign issue_fire=issue_valid&&(aw_done||aw_fire)&&(w_done||w_fire);
    assign m_axi_bready_o=outstanding!=0;assign b_fire=m_axi_bvalid_i&&m_axi_bready_o;
    assign wr_busy_o=used!=0;
    function automatic logic [PTR_W-1:0] next_ptr(input logic [PTR_W-1:0] p);
        next_ptr=p==WRITE_DEPTH-1?'0:p+1'b1;
    endfunction
    always_ff @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin put_ptr<=0;issue_ptr<=0;retire_ptr<=0;used<=0;outstanding<=0;aw_done<=0;w_done<=0;write_error<=0;end
        else begin
            if(clear_i&&!wr_busy_o)write_error<=0;
            if(wr_valid_i&&wr_ready_o&&(bad_config||wr_offset_i>=capacity_i))write_error[1]<=1;
            if(m_axi_bvalid_i&&outstanding==0&&!issue_fire)write_error[0]<=1;
            if(enqueue)begin
                addr_mem[put_ptr]<=base_i+((ADDR_W'(wr_offset_i)+(wr_bank_i?ADDR_W'(capacity_i):0))<<4);
                data_mem[put_ptr]<=wr_data_i;put_ptr<=next_ptr(put_ptr);
            end
            if(aw_fire)aw_done<=1;if(w_fire)w_done<=1;
            if(issue_fire)begin issue_ptr<=next_ptr(issue_ptr);aw_done<=0;w_done<=0;end
            if(b_fire)begin retire_ptr<=next_ptr(retire_ptr);if(m_axi_bid_i!=0||m_axi_bresp_i!=0)write_error[0]<=1;end
            case({enqueue,b_fire})
                2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:used<=used;
            endcase
            case({issue_fire,b_fire})
                2'b10:outstanding<=outstanding+1'b1;2'b01:outstanding<=outstanding-1'b1;default:outstanding<=outstanding;
            endcase
        end
    end
`ifndef SYNTHESIS
    assert property(@(posedge clk_i) disable iff(!rst_ni) m_axi_awvalid_o&&!m_axi_awready_i|=>$stable({m_axi_awvalid_o,m_axi_awaddr_o}));
    assert property(@(posedge clk_i) disable iff(!rst_ni) m_axi_wvalid_o&&!m_axi_wready_i|=>$stable({m_axi_wvalid_o,m_axi_wdata_o}));
    assert property(@(posedge clk_i) disable iff(!rst_ni) outstanding<=used);
`endif
endmodule
