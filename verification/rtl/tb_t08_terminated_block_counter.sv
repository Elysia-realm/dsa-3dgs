`timescale 1ns/1ps
module tb_t08_terminated_block_counter;
    logic clk=0,rst=0,start=0,update=0,full;
    logic [31:0] index=0,query=0;
    integer checks=0;
    always #5 clk=~clk;
    terminated_block_counter #(.ADDRESS_BITS(3)) dut(.clk_i(clk),.rst_ni(rst),.new_frame_i(start),
        .update_i(update),.update_block_i(index),.query_block_i(query),.query_full_o(full));
    task automatic tick;
        @(posedge clk);#1;
    endtask
    task automatic check(input int id,input bit want);
        query=id;#1;
        if(full!==want)$fatal(1,"unexpected block status id=%0d got=%0d expected=%0d",id,full,want);
        checks++;
    endtask
    task automatic crossing(input int id);
        index=id;update=1;tick();
    endtask
    initial begin
        repeat(2)tick();rst=1;repeat(8)tick();
        for(int j=0;j<63;j++)begin crossing(0);check(0,0);end
        crossing(8);check(0,0); // outside the table, same low address
        crossing(0);check(0,0);
        update=0;tick();check(0,1);check(8,0);
        for(int j=0;j<64;j++)begin crossing(3);crossing(7);end
        update=0;tick();check(3,1);check(7,1);
        for(int j=0;j<63;j++)crossing(1);
        crossing(1); // invalidate while the 64th write is in flight
        start=1;check(0,0);tick();start=0;
        for(int j=0;j<8;j++)begin crossing(1);check(1,0);end
        update=0;
        for(int j=0;j<8;j++)check(j,0);
        for(int j=0;j<63;j++)crossing(1);
        update=0;tick();check(1,0); // partial boundary block cannot reach 64
        crossing(1);update=0;tick();check(1,1);
        rst=0;tick();check(1,0);rst=1;repeat(3)tick();
        start=1;tick();start=0;repeat(8)tick();
        for(int j=0;j<8;j++)check(j,0);
        $display("PASS terminated block counter checks=%0d",checks);$finish;
    end
endmodule
