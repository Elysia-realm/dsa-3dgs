`timescale 1ns/1ps
module tb_t08_state_line_buffer;
    typedef logic [63:0] address_t;
    logic clk=0,rst=0,sv=0,sr,flush,wr,mv,mr=0,err;
    address_t addr,ma,held_addr;
    logic [127:0] data,out_data,held_response;
    logic [15:0] strb;
    logic cmd,ready,mwrite,ret=0,ret_ready,ret_error=0;
    logic [511:0] md,rd,held_line;
    logic [511:0] backing[address_t];
    logic [127:0] oracle[address_t];
    int tick=0,wait_count=0,accepted=0,read_lines=0,write_lines=0;
    int fault_kind=0,deck_fd,trace_fd,code,op,scanned;
    bit pending=0,pending_write,pending_error,held=0,held_write;
    address_t pending_addr,input_addr;
    logic [511:0] pending_line;
    logic [127:0] input_data;
    logic [15:0] input_mask;
    string deck_path,trace_path;
    always #5 clk=~clk;
    pixel_state_line_buffer dut(.clk_i(clk),.rst_ni(rst),.s_valid_i(sv),.s_ready_o(sr),
        .s_flush_i(flush),.s_write_i(wr),.s_addr_i(addr),.s_data_i(data),.s_strb_i(strb),
        .m_valid_o(mv),.m_ready_i(mr),.m_error_o(err),.m_data_o(out_data),
        .mem_valid_o(cmd),.mem_ready_i(ready),.mem_write_o(mwrite),.mem_addr_o(ma),.mem_data_o(md),
        .ret_valid_i(ret),.ret_ready_o(ret_ready),.ret_error_i(ret_error),.ret_data_i(rd));
    assign ready=!pending&&!ret&&(tick%7!=1)&&(tick%7!=2);
    function automatic logic [127:0] seed(input address_t a);
        return {a^64'hcd70c402cfac1953,(a*64'h4139c8181845f257)^64'h930495e362a8445f};
    endfunction
    function automatic logic [127:0] expected(input address_t a);
        if(oracle.exists(a))return oracle[a];
        return seed(a);
    endfunction
    function automatic logic [511:0] memory_line(input address_t a);
        logic [511:0] v;
        if(backing.exists(a))return backing[a];
        for(int i=0;i<4;i++)v[i*128+:128]=seed(a+16*i);
        return v;
    endfunction
    always @(posedge clk)if(rst)begin
        tick<=tick+1;
        if(tick>5000000)$fatal(1,"timeout");
        if(held && (!cmd || ma!=held_addr || mwrite!=held_write || (mwrite&&md!==held_line)))$fatal(1,"changed stalled memory request");
        held<=cmd&&!ready;held_addr<=ma;held_write<=mwrite;held_line<=md;
        if(cmd&&ready)begin
            if(ma[5:0]!=0)$fatal(1,"unaligned memory request");
            pending<=1;pending_write<=mwrite;pending_addr<=ma;pending_line<=md;wait_count<=1+(tick%4);
            pending_error<=(mwrite&&fault_kind==2)||(!mwrite&&fault_kind==1);
            if((mwrite&&fault_kind==2)||(!mwrite&&fault_kind==1))fault_kind=0;
            if(mwrite)begin write_lines<=write_lines+1;$fdisplay(trace_fd,"0x%016h W",ma);end
            else begin read_lines<=read_lines+1;$fdisplay(trace_fd,"0x%016h R",ma);end
        end
        if(pending)begin
            if(wait_count==0)begin pending<=0;ret<=1;ret_error<=pending_error;rd<=memory_line(pending_addr);end
            else wait_count<=wait_count-1;
        end
        if(ret&&ret_ready)begin
            if(pending_write&&!ret_error)backing[pending_addr]=pending_line;
            ret<=0;
        end
    end
    task automatic issue(input int action,input address_t a,input logic [127:0] value,input logic [15:0] mask);
        logic want_err;
        logic [127:0] v;
        // 0 read, 1 write, 2 flush, 3 inject fill fault, 4 inject eviction fault,
        // 5 inject flush writeback fault, 6 unaligned.
        want_err=action>=3;
        if(action==3)fault_kind=1;
        if(action==4||action==5)fault_kind=2;
        @(negedge clk);while(!sr)@(negedge clk);
        sv=1;flush=action==2||action==5;wr=action==1;addr=a;data=value;strb=mask;
        @(negedge clk);sv=0;
        while(!mv)@(negedge clk);
        if(err!==want_err||fault_kind!=0)$fatal(1,"fault response action=%0d addr=%h",action,a);
        if(!err&&action==0&&out_data!==expected(a))$fatal(1,"read mismatch %h",a);
        held_response=out_data;
        repeat(1+(accepted%3))begin
            @(negedge clk);if(!mv||sr||err!==want_err||out_data!==held_response)$fatal(1,"stalled response changed");
        end
        mr=1;@(negedge clk);mr=0;
        if(!want_err && wr)begin
            v=expected(a);
            for(int i=0;i<16;i++)if(mask[i])v[i*8+:8]=value[i*8+:8];
            oracle[a]=v;
        end
        if(action==2)begin
            if(pending||ret||dut.dirty_q!=0||dut.valid_q!=0)$fatal(1,"flush did not drain/invalidate");
            foreach(backing[k])for(int j=0;j<4;j++)
                if(backing[k][j*128+:128]!==expected(k+16*j))$fatal(1,"corrupted backing sector");
            foreach(oracle[k])begin
                v=128'(memory_line(k&~64'd63)>>(8*(k&63)));
                if(v!==oracle[k])$fatal(1,"lost write");
            end
        end
        accepted++;
    endtask
    initial begin
        if(!$value$plusargs("DECK=%s",deck_path)||!$value$plusargs("TRACE=%s",trace_path))$fatal;
        deck_fd=$fopen(deck_path,"r");trace_fd=$fopen(trace_path,"w");if(!deck_fd||!trace_fd)$fatal;
        repeat(4)@(negedge clk);rst=1;
        while(!$feof(deck_fd))begin
            scanned=$fscanf(deck_fd,"%d %h %h %h\n",op,input_addr,input_data,input_mask);
            if(scanned==4)issue(op,input_addr,input_data,input_mask);
            else if(!$feof(deck_fd))$fatal(1,"bad deck");
        end
        issue(2,0,0,0);
        $fclose(trace_fd);$fclose(deck_fd);
        $display("PASS T08 state line buffer operations=%0d reads=%0d writes=%0d bench_cycles=%0d",accepted,read_lines,write_lines,tick);
        $finish;
    end
endmodule
