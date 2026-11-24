`timescale 1ns/1ps

module tb_fixed_div_pipe2;
    logic clk_i = 1'b0, rst_ni = 1'b0;
    logic s_valid_i = 1'b0, s_ready_o;
    logic signed [15:0] s_num0_i = '0, s_num1_i = '0;
    logic [7:0] s_den_i = '0;
    logic [7:0] s_meta_i = '0;
    logic m_valid_o, m_ready_i = 1'b1;
    logic signed [11:0] m_quot0_o, m_quot1_o;
    logic [7:0] m_meta_o;
    logic m_div_zero_o, m_overflow_o;

    always #5 clk_i = ~clk_i;
    fixed_div_pipe2 #(.NUM_W(16), .DEN_W(8), .QUOT_W(12), .META_W(8)) dut (.*);

    task automatic tick; begin @(posedge clk_i); #1; end endtask
    task automatic send_expect(
        input logic [7:0] meta,
        input integer n0, n1, d, q0, q1,
        input logic div_zero, overflow
    );
        integer timeout;
        begin
            while (!s_ready_o) tick();
            s_meta_i=meta; s_num0_i=n0; s_num1_i=n1; s_den_i=d;
            s_valid_i=1'b1; tick(); s_valid_i=1'b0;
            timeout=0;
            while (!m_valid_o && timeout<30) begin tick(); timeout=timeout+1; end
            if (!m_valid_o || m_meta_o!==meta || m_quot0_o!==q0 || m_quot1_o!==q1
                || m_div_zero_o!==div_zero || m_overflow_o!==overflow)
                $fatal(1,"divider mismatch meta=%h q=%0d,%0d flags=%b,%b",
                       m_meta_o,m_quot0_o,m_quot1_o,m_div_zero_o,m_overflow_o);
            tick();
        end
    endtask

    initial begin
        repeat(2) tick(); rst_ni=1'b1; tick();
        send_expect(8'h01, 1000, -1000, 10, 100, -100, 0, 0);
        send_expect(8'h02, -32768, 32767, 255, -128, 128, 0, 0);
        send_expect(8'h03, 100, -100, 0, 2047, -2048, 1, 1);
        send_expect(8'h04, 32767, 1, 1, 2047, 1, 0, 1);

        m_ready_i=1'b0;
        while(!s_ready_o) tick();
        s_meta_i=8'h55; s_num0_i=16'sd777; s_num1_i=-16'sd333; s_den_i=8'd3;
        s_valid_i=1'b1; tick(); s_valid_i=1'b0;
        while(!m_valid_o) tick();
        repeat(3) begin
            if(m_meta_o!==8'h55 || m_quot0_o!==12'sd259 || m_quot1_o!==-12'sd111)
                $fatal(1,"divider output changed under backpressure");
            tick();
        end
        m_ready_i=1'b1; tick();
        $display("PASS: tb_fixed_div_pipe2"); $finish;
    end
endmodule
