// Testbench timing only. Production RTL computes every address and data byte.
import "DPI-C" function void t08_shared_init(input string cfg,input string stats);
import "DPI-C" function void t08_shared_addr(input int port_id,input int tag,input longint unsigned addr,input int beats);
import "DPI-C" function void t08_shared_wlast(input int port_id);
import "DPI-C" function void t08_shared_step(output int done_mask,output int qsu_writes,output int out_writes);
import "DPI-C" function void t08_shared_finish(output longint unsigned lines,output longint unsigned tail);
bit ddr_timed;
logic [7:0] ddr_read_done=0;
integer ddr_qsu_done=0,ddr_out_done=0;
longint unsigned ddr_expected_lines=0;
string ddr_conf,ddr_stats;
initial begin
    ddr_timed=$test$plusargs("LPDDR_TIMED");
    if(ddr_timed)begin
        if(!$value$plusargs("MODEL_CFG=%s",ddr_conf)||!$value$plusargs("MODEL_STATS=%s",ddr_stats))$fatal;
        t08_shared_init(ddr_conf,ddr_stats);
    end
end
task automatic ddr_offer(input int port_id,input int tag,input logic[63:0] addr,input logic[7:0] len);
    integer beats;
    beats=int'(len)+1;
    t08_shared_addr(port_id,tag,addr,beats);
    ddr_expected_lines+=64'((int'(addr[5:0])+beats*16+63)/64);
endtask
always @(posedge clk_i)if(rst_ni&&ddr_timed)begin : shared_service
    integer mask_done,qsu_done,out_done;
    if(m_axi_camera_arvalid_o&&m_axi_camera_arready_i)ddr_offer(0,0,m_axi_camera_araddr_o,m_axi_camera_arlen_o);
    if(m_axi_mean_arvalid_o&&m_axi_mean_arready_i)ddr_offer(1,0,m_axi_mean_araddr_o,m_axi_mean_arlen_o);
    if(m_axi_attr_arvalid_o&&m_axi_attr_arready_i)ddr_offer(2,0,m_axi_attr_araddr_o,m_axi_attr_arlen_o);
    if(m_axi_qsu_arvalid_o&&m_axi_qsu_arready_i)ddr_offer(3,0,m_axi_qsu_araddr_o,m_axi_qsu_arlen_o);
    if(m_axi_qsu_awvalid_o&&m_axi_qsu_awready_i)ddr_offer(4,0,m_axi_qsu_awaddr_o,m_axi_qsu_awlen_o);
    if(m_axi_state_arvalid_o&&m_axi_state_arready_i)ddr_offer(5,int'(m_axi_state_arid_o),m_axi_state_araddr_o,m_axi_state_arlen_o);
    if(m_axi_out_awvalid_o&&m_axi_out_awready_i)ddr_offer(6,0,m_axi_out_awaddr_o,m_axi_out_awlen_o);
    if(m_axi_qsu_wvalid_o&&m_axi_qsu_wready_i&&m_axi_qsu_wlast_o)t08_shared_wlast(4);
    if(m_axi_out_wvalid_o&&m_axi_out_wready_i&&m_axi_out_wlast_o)t08_shared_wlast(6);
    t08_shared_step(mask_done,qsu_done,out_done);
    ddr_read_done<=mask_done[7:0];ddr_qsu_done<=qsu_done;ddr_out_done<=out_done;
end
task automatic report_shared_memory;
    longint unsigned lines,tail;
    if(ddr_timed)begin
        t08_shared_finish(lines,tail);
        if(lines!=ddr_expected_lines || ddr_qsu_done!=qsu_b_get || ddr_out_done!=b_get)
            $fatal(1,"DDR line or write completion accounting mismatch");
        $display("REAL_LPDDR lines=%0d dram_tail_cycles=%0d qsu_b=%0d out_b=%0d",lines,tail,qsu_b_get,b_get);
    end
endtask
