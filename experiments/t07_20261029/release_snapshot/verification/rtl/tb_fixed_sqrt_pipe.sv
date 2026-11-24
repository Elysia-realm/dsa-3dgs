`timescale 1ns/1ps
module tb_fixed_sqrt_pipe;
    localparam integer TESTS=256;
    logic clk_i=0,rst_ni=0,s_valid_i=0,s_ready_o;
    logic [31:0] s_radicand_i='0;
    logic [7:0] s_meta_i='0;
    logic m_valid_o,m_ready_i=1;
    logic [15:0] m_root_o;
    logic [7:0] m_meta_o;
    logic m_exact_o;
    integer accepted=0,received=0,cycles=0;
    logic [15:0] expected_root [0:TESTS-1];
    logic [7:0] expected_meta [0:TESTS-1];
    logic expected_exact [0:TESTS-1];
    logic [31:0] lfsr=32'h1ace_b00c;
    logic [31:0] next_value;
    integer test_index;

    always #5 clk_i=~clk_i;
    fixed_sqrt_pipe #(.RAD_W(32),.META_W(8)) dut(.*);
    task automatic tick;begin @(posedge clk_i);#1;end endtask

    function automatic logic [15:0] reference_sqrt(input logic [31:0] value);
        logic [33:0] remainder;
        logic [15:0] root;
        logic [33:0] trial;
        integer bit_index;
        begin
            remainder='0;root='0;
            for(bit_index=15;bit_index>=0;bit_index=bit_index-1)begin
                remainder={remainder[31:0],value[2*bit_index+:2]};
                trial={16'b0,root,2'b01};
                if(remainder>=trial)begin
                    remainder=remainder-trial;
                    root={root[14:0],1'b1};
                end else root={root[14:0],1'b0};
            end
            reference_sqrt=root;
        end
    endfunction

    always @(posedge clk_i) begin
        if(rst_ni && m_valid_o && m_ready_i) begin
            if(m_root_o!==expected_root[received]
               ||m_exact_o!==expected_exact[received]
               ||m_meta_o!==expected_meta[received])
                $fatal(1,"sqrt[%0d] got root=%0d exact=%b meta=%h expected=%0d/%b/%h",
                       received,m_root_o,m_exact_o,m_meta_o,
                       expected_root[received],expected_exact[received],expected_meta[received]);
            received<=received+1;
        end
    end

    task automatic send(input logic [31:0] value,input logic [7:0] meta);
        begin
            #1; // allow ready to settle after the caller changes m_ready_i
            while(!s_ready_o)begin
                lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
                m_ready_i=lfsr[0]||lfsr[2];#1;tick();
            end
            expected_root[accepted]=reference_sqrt(value);
            expected_exact[accepted]=expected_root[accepted]*expected_root[accepted]==value;
            expected_meta[accepted]=meta;
            s_radicand_i=value;s_meta_i=meta;s_valid_i=1;
            accepted=accepted+1;tick();s_valid_i=0;
        end
    endtask

    initial begin
        repeat(2)tick();rst_ni=1;tick();
        send(0,8'h10);send(1,8'h11);send(15,8'h12);send(16,8'h13);
        // Deliberately stall before the oldest result exits.
        repeat(4)tick();m_ready_i=0;repeat(5)tick();m_ready_i=1;
        send(32'hffff_ffff,8'h14);
        // Exercise exact-square boundaries and deterministic pseudo-random
        // values while independently varying output backpressure.
        for(test_index=5;test_index<TESTS;test_index=test_index+1)begin
            case(test_index)
              5:next_value=32'd2;
              6:next_value=32'd3;
              7:next_value=32'd4;
              8:next_value=32'd65535;
              9:next_value=32'd65536;
              10:next_value=32'd65537;
              11:next_value=32'hfffe_0001; // 65535 squared
              default:begin
                lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
                next_value=lfsr;
              end
            endcase
            m_ready_i=lfsr[0]||lfsr[3];
            send(next_value,test_index[7:0]);
        end
        s_valid_i=0;
        while(received<TESTS&&cycles<2000)begin
            lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
            m_ready_i=lfsr[0]||lfsr[2];tick();cycles=cycles+1;
        end
        if(received!=TESTS)$fatal(1,"timeout received=%0d accepted=%0d",received,accepted);
        m_ready_i=1;tick();
        $display("PASS: tb_fixed_sqrt_pipe transactions=%0d",received);$finish;
    end
endmodule
