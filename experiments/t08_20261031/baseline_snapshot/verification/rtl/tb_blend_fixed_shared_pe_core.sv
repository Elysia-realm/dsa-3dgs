`timescale 1ns/1ps
// Ordered, backpressured A/B against the local blend arithmetic. The PE
// emulator periodically denies requests and holds a response until accepted.
module tb_blend_fixed_shared_pe_core;
    logic clk_i=0,rst_ni=0;
    integer cycle_count=0,send_index=0,receive_index=0;
    logic s_valid_i,s_ready_o,local_s_ready,m_valid_o,m_ready_i,local_m_valid;
    logic [7:0] s_meta_i,m_meta_o,local_meta;
    logic [12:0] s_old_r_q12_i,s_old_g_q12_i,s_old_b_q12_i;
    logic [15:0] s_old_t_q16_i;
    logic [12:0] s_color_r_q12_i,s_color_g_q12_i,s_color_b_q12_i,s_alpha_q12_i;
    logic [12:0] m_new_r_q12_o,m_new_g_q12_o,m_new_b_q12_o;
    logic [12:0] local_r,local_g,local_b;
    logic [15:0] m_new_t_q16_o,local_t;
    logic m_newly_terminated_o,local_term;
    logic r_pe_req_valid_o,r_pe_req_ready_i,r_pe_rsp_valid_i,r_pe_rsp_ready_o;
    logic signed[31:0]r_pe_lhs_o,r_pe_rhs_o;
    logic signed[64:0]r_pe_result_i;
    logic [55:0] expected[0:255];
    logic expected_valid[0:255];
    logic local_s_valid;

    always #5 clk_i=~clk_i;
    assign s_valid_i=send_index<256;
    assign s_meta_i=8'(send_index);
    assign s_old_r_q12_i=13'((send_index*17)%4097);
    assign s_old_g_q12_i=13'((send_index*43)%4097);
    assign s_old_b_q12_i=13'((send_index*71)%4097);
    assign s_old_t_q16_i=16'((send_index*137+1234)%65536);
    assign s_color_r_q12_i=13'((send_index*113)%4097);
    assign s_color_g_q12_i=13'((send_index*59)%4097);
    assign s_color_b_q12_i=13'((send_index*23)%4097);
    assign s_alpha_q12_i=13'((send_index*89)%4097);
    assign m_ready_i=(cycle_count%7)<4;
    assign local_s_valid=s_valid_i&&s_ready_o;
    assign r_pe_req_ready_i=(cycle_count%5)!=0&&(!r_pe_rsp_valid_i||r_pe_rsp_ready_o);

    blend_fixed_core #(.META_W(8),.USE_SHARED_RASTER_PE(1'b1))dut(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(s_valid_i),.s_ready_o(s_ready_o),
      .s_meta_i(s_meta_i),.s_old_r_q12_i(s_old_r_q12_i),.s_old_g_q12_i(s_old_g_q12_i),
      .s_old_b_q12_i(s_old_b_q12_i),.s_old_t_q16_i(s_old_t_q16_i),
      .s_color_r_q12_i(s_color_r_q12_i),.s_color_g_q12_i(s_color_g_q12_i),
      .s_color_b_q12_i(s_color_b_q12_i),.s_alpha_q12_i(s_alpha_q12_i),
      .m_valid_o(m_valid_o),.m_ready_i(m_ready_i),.m_meta_o(m_meta_o),
      .m_new_r_q12_o(m_new_r_q12_o),.m_new_g_q12_o(m_new_g_q12_o),
      .m_new_b_q12_o(m_new_b_q12_o),.m_new_t_q16_o(m_new_t_q16_o),
      .m_newly_terminated_o(m_newly_terminated_o),
      .r_pe_req_valid_o(r_pe_req_valid_o),.r_pe_req_ready_i(r_pe_req_ready_i),
      .r_pe_lhs_o(r_pe_lhs_o),.r_pe_rhs_o(r_pe_rhs_o),
      .r_pe_rsp_valid_i(r_pe_rsp_valid_i),.r_pe_rsp_ready_o(r_pe_rsp_ready_o),
      .r_pe_result_i(r_pe_result_i));
    blend_fixed_core #(.META_W(8))reference_core(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(local_s_valid),.s_ready_o(local_s_ready),
      .s_meta_i(s_meta_i),.s_old_r_q12_i(s_old_r_q12_i),.s_old_g_q12_i(s_old_g_q12_i),
      .s_old_b_q12_i(s_old_b_q12_i),.s_old_t_q16_i(s_old_t_q16_i),
      .s_color_r_q12_i(s_color_r_q12_i),.s_color_g_q12_i(s_color_g_q12_i),
      .s_color_b_q12_i(s_color_b_q12_i),.s_alpha_q12_i(s_alpha_q12_i),
      .m_valid_o(local_m_valid),.m_ready_i(1'b1),.m_meta_o(local_meta),
      .m_new_r_q12_o(local_r),.m_new_g_q12_o(local_g),.m_new_b_q12_o(local_b),
      .m_new_t_q16_o(local_t),.m_newly_terminated_o(local_term),
      .r_pe_req_valid_o(),.r_pe_req_ready_i(1'b0),.r_pe_lhs_o(),.r_pe_rhs_o(),
      .r_pe_rsp_valid_i(1'b0),.r_pe_rsp_ready_o(),.r_pe_result_i(65'b0));

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cycle_count<=0;send_index<=0;receive_index<=0;
            r_pe_rsp_valid_i<=0;r_pe_result_i<=0;
        end else begin
            cycle_count<=cycle_count+1;
            if (s_valid_i&&s_ready_o)send_index<=send_index+1;
            if (r_pe_req_valid_o&&r_pe_req_ready_i) begin
                r_pe_result_i<=$signed(r_pe_lhs_o)*$signed(r_pe_rhs_o);
                r_pe_rsp_valid_i<=1;
            end else if (r_pe_rsp_valid_i&&r_pe_rsp_ready_o)r_pe_rsp_valid_i<=0;
            if (local_s_valid&&!local_s_ready)$fatal(1,"local reference not ready");
            if (local_m_valid) begin
                expected[local_meta]<={local_r,local_g,local_b,local_t,local_term};
                expected_valid[local_meta]<=1;
            end
            if (m_valid_o&&m_ready_i) begin
                if (m_meta_o!==8'(receive_index)||!expected_valid[m_meta_o]||
                    {m_new_r_q12_o,m_new_g_q12_o,m_new_b_q12_o,m_new_t_q16_o,m_newly_terminated_o}
                    !==expected[m_meta_o])$fatal(1,"shared blend mismatch at %0d",receive_index);
                expected_valid[m_meta_o]<=0;
                receive_index<=receive_index+1;
            end
            if (cycle_count>10000)$fatal(1,"shared blend timeout sent=%0d received=%0d",send_index,receive_index);
            if (receive_index==256)begin
                $display("PASS: tb_blend_fixed_shared_pe_core 256 ordered vectors with PE/backpressure stalls");
                $finish;
            end
        end
    end
    initial begin
        for(integer i=0;i<256;i=i+1)expected_valid[i]=0;
        #17 rst_ni=1;
    end
endmodule
