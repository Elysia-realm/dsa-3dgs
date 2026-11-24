`timescale 1ns/1ps
module tb_t08_qsu_window_changes;
`ifndef TB_QSU_PRECOUNT
`define TB_QSU_PRECOUNT 0
`endif
`ifndef T06_MAX_COUNT
`define T06_MAX_COUNT 65536
`endif
    localparam D=27,G=32,S=32,K=16,W=D+G+S;
    logic clk=0,rst=0,start=0,ending=0,sv=0,sr;
    always #5 clk=~clk;
    logic [W-1:0] input_word;
    logic qv,qr,qfirst,qlast,busy,done,error;
    logic signed [D-1:0] qdepth,odepth;
    logic [G-1:0] qgid,ogid;logic [S-1:0] qseq,oseq;logic [2:0] qgroup;
    logic rv,rr,rbank,rvalid,rready,rlast,rb;
    logic [31:0] roffset,rcount;logic [127:0] rdata;
    logic wv,wr,wbank,wb;logic [31:0] woffset;logic [127:0] wdata;
    logic [31:0] inputs,partitions,leaves,reads,writes,stalls,peak;
    logic ov,ordy,overflow,sortbusy;
    logic gv,gr,g_rsp,g_rsp_ready,g_less;
    logic signed [31:0] lhs,rhs;logic [31:0] lgid,rgid,lseq,rseq;
    logic [31:0] overlap,parallel_cycles;
    logic [127:0] mem[0:1][0:`T06_MAX_COUNT-1];
    logic [W-1:0] vectors[0:`T06_MAX_COUNT-1],expected[0:`T06_MAX_COUNT-1];
    integer n,received,tick,idx,left,latency,write_tail,seed,fail_after;
    integer output_group_count;
    logic bank,mem_error=0;
    string input_path,expected_path;
    autonomous_qsu #(.DEPTH_W(D),.GID_W(G),.SEQ_W(S),.CAPACITY(K),.PRECOUNT_CHILDREN(`TB_QSU_PRECOUNT))qsu(
        .clk_i(clk),.rst_ni(rst),.start_i(start),.capacity_i(32'(n)),
        .s_valid_i(sv),.s_ready_o(sr),.s_depth_i(input_word[S+G+:D]),.s_gid_i(input_word[S+:G]),.s_seq_i(input_word[S-1:0]),.end_i(ending),
        .m_valid_o(qv),.m_ready_i(qr),.m_depth_o(qdepth),.m_gid_o(qgid),.m_seq_o(qseq),.m_group_o(qgroup),
        .m_first_o(qfirst),.m_last_o(qlast),.busy_o(busy),.done_o(done),.error_o(error),
        .rd_valid_o(rv),.rd_ready_i(rr),.rd_bank_o(rbank),.rd_offset_o(roffset),.rd_count_o(rcount),
        .r_valid_i(rvalid),.r_ready_o(rready),.r_data_i(rdata),.r_last_i(rlast),.rd_busy_i(rb),
        .wr_valid_o(wv),.wr_ready_i(wr),.wr_bank_o(wbank),.wr_offset_o(woffset),.wr_data_o(wdata),.wr_busy_i(wb),.mem_error_i(mem_error),
        .perf_input_o(inputs),.perf_partitions_o(partitions),.perf_leaves_o(leaves),.perf_read_o(reads),.perf_write_o(writes),.perf_stall_o(stalls),.perf_peak_stack_o(peak));
    bitonic_group_sorter_pipelined_shared #(.CAPACITY(K),.DEPTH_W(D),.GID_W(G),.SEQ_W(S),.GROUP_W(3),.PAYLOAD_W(1))bsu(
        .clk_i(clk),.rst_ni(rst),.clear_overflow_i(start),.cfg_active_lanes_i(3'd4),
        .s_valid_i(qv),.s_ready_o(qr),.s_empty_i(1'b0),.s_depth_i(qdepth),.s_gid_i(qgid),.s_seq_i(qseq),.s_group_i(qgroup),.s_payload_i(1'b0),.s_group_last_i(qlast),
        .m_valid_o(ov),.m_ready_i(ordy),.m_depth_o(odepth),.m_gid_o(ogid),.m_seq_o(oseq),.m_group_o(),.m_payload_o(),.m_group_first_o(),.m_group_last_o(),
        .overflow_o(overflow),.busy_o(sortbusy),.subset_done_o(),
        .pe_req_valid_o(gv),.pe_req_ready_i(gr),.pe_lhs_o(lhs),.pe_rhs_o(rhs),.pe_lhs_gid_o(lgid),.pe_rhs_gid_o(rgid),.pe_lhs_seq_o(lseq),.pe_rhs_seq_o(rseq),
        .pe_rsp_valid_i(g_rsp),.pe_rsp_ready_o(g_rsp_ready),.pe_less_i(g_less),
        .perf_shared_compares_o(),.perf_local_compares_o(),.perf_swaps_o(),.perf_phases_o(),.perf_groups_o(),.perf_stalls_o(),
        .perf_collect_emit_overlap_o(overlap),.perf_parallel_stage_cycles_o(parallel_cycles));
    // Real shared G/P/R slice; recurring independent P/R requests compete.
    shared_reconfigurable_pe_slice #(.DATA_W(32),.GID_W(G),.SEQ_W(S),.RESULT_W(65))pe(
        .clk_i(clk),.rst_ni(rst),.group_weight_i(3'd4),.projection_weight_i(3'd2),.raster_weight_i(3'd2),.shared_owner_i(2'd0),.aggressive_clock_gate_i(1'b0),.reconfigure_i(1'b0),
        .g_valid_i(gv),.g_ready_o(gr),.g_op_mac_i(1'b0),.g_lhs_i(lhs),.g_rhs_i(rhs),.g_acc_i(65'd0),.g_lhs_gid_i(lgid),.g_rhs_gid_i(rgid),.g_lhs_seq_i(lseq),.g_rhs_seq_i(rseq),
        .g_rsp_valid_o(g_rsp),.g_rsp_ready_i(g_rsp_ready),.g_result_o(),.g_less_o(g_less),
        .p_valid_i(tick%7==0),.p_ready_o(),.p_op_mac_i(1'b1),.p_lhs_i(32'd2),.p_rhs_i(32'd3),.p_acc_i(65'd1),.p_lhs_gid_i(32'd0),.p_rhs_gid_i(32'd0),.p_lhs_seq_i(32'd0),.p_rhs_seq_i(32'd0),.p_rsp_valid_o(),.p_rsp_ready_i(1'b1),.p_result_o(),.p_less_o(),
        .r_valid_i(tick%11==0),.r_ready_o(),.r_op_mac_i(1'b1),.r_lhs_i(32'd3),.r_rhs_i(32'd4),.r_acc_i(65'd1),.r_lhs_gid_i(32'd0),.r_rhs_gid_i(32'd0),.r_lhs_seq_i(32'd0),.r_rhs_seq_i(32'd0),.r_rsp_valid_o(),.r_rsp_ready_i(1'b1),.r_result_o(),.r_less_o(),
        .group_grant_pulse_o(),.projection_grant_pulse_o(),.raster_grant_pulse_o(),.group_stall_o(),.projection_stall_o(),.raster_stall_o(),.utilization_pulse_o(),.clock_enable_o(),.busy_o());
    assign rr=left==0&&(tick%7!=1);
    assign rb=left!=0;
    assign rvalid=left!=0&&latency==0;
    assign rdata=mem[bank][idx];assign rlast=left==1;
    assign wr=tick%5!=2;assign wb=write_tail!=0;
    assign ordy=tick%101<65;
    always @(posedge clk)if(rst)begin
        tick<=tick+1;
        if(latency>0)latency<=latency-1;
        if(write_tail>0)write_tail<=write_tail-1;
        if(rv&&rr)begin
            if(rcount==0||roffset+rcount>n)$fatal(1,"read bounds");
            idx<=roffset;left<=rcount;bank<=rbank;latency<=3;
        end
        if(rvalid&&rready)begin idx<=idx+1;left<=left-1;end
        if(wv&&wr)begin
            if(woffset>=n)$fatal(1,"write bounds");
            mem[wbank][woffset]<=wdata;write_tail<=4;
        end
        if(qv&&qr)begin
            output_group_count<=qlast?0:output_group_count+1;
            if(output_group_count>=K)$fatal(1,"oversized BSU subset");
        end
        if(ov&&ordy)begin
            if({odepth,ogid,oseq}!==expected[received])$fatal(1,"sort mismatch at %0d got %h expected %h",received,{odepth,ogid,oseq},expected[received]);
            received<=received+1;
        end
        if(error||overflow)$fatal(1,"error qsu=%b bsu=%b",error,overflow);
        if(tick>2000000000)$fatal(1,"timeout state %d received %0d",qsu.state_q,received);
    end
    integer hit_count=0;
    always @(posedge clk) if(rst&&ending&&qsu.total_q>K&&qsu.root_match)hit_count++;
    initial begin
        n=0;received=0;tick=0;idx=0;left=0;latency=0;write_tail=0;bank=0;output_group_count=0;input_word=0;
        if(!$value$plusargs("N=%d",n))$fatal;
        if(!$value$plusargs("INPUT=%s",input_path))$fatal;
        if(!$value$plusargs("EXPECTED=%s",expected_path))$fatal;
        if(n>0)begin $readmemh(input_path,vectors,0,n-1);$readmemh(expected_path,expected,0,n-1);end
        repeat(4)@(negedge clk);rst=1;for(integer frame=0;frame<9;frame++)begin
        case(frame)
0:n=97;
1:n=97;
2:n=97;
3:n=97;
4:n=97;
5:n=0;
6:n=97;
7:n=97;
8:n=98;
endcase
if(n>0)begin
            $readmemh($sformatf("%s/%0d_input.memh",input_path,frame),vectors,0,n-1);
            $readmemh($sformatf("%s/%0d_expected.memh",input_path,frame),expected,0,n-1);
        end
        received=0;@(negedge clk);start=1;@(negedge clk);start=0;
        for(integer j=0;j<n;j=j+1)begin
            sv=1;input_word=vectors[j];@(posedge clk);while(!sr)@(posedge clk);@(negedge clk);
        end
        sv=0;ending=1;@(negedge clk);ending=0;
        wait(done);@(negedge clk);wait(!sortbusy);repeat(4)@(negedge clk);
        if(received!=n||inputs!=n||rb||wb)$fatal(1,"count/drain mismatch");
        $display("PASS T06 n=%0d cycles=%0d partitions=%0d leaves=%0d reads=%0d writes=%0d peak=%0d overlap=%0d parallel=%0d",n,tick,partitions,leaves,reads,writes,peak,overlap,parallel_cycles);$display("WINDOW_FRAME %0d %0d",frame,hit_count);end
        $display("ROOT_HITS %0d",hit_count);$finish;
    end
endmodule
