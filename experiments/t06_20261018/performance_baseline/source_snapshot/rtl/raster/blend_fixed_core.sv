// Front-to-back blend core. RGB/color/alpha use Q1.12; transmittance uses
// Q0.16 so the 1e-4 termination threshold is representable as code 7.
module blend_fixed_core #(
    parameter int unsigned META_W = 128,
    parameter int unsigned TERMINATION_Q16 = 7,
    parameter bit USE_SHARED_RASTER_PE = 1'b0
) (
    input  logic                 clk_i,
    input  logic                 rst_ni,
    input  logic                 s_valid_i,
    output logic                 s_ready_o,
    input  logic [META_W-1:0]    s_meta_i,
    input  logic [12:0]          s_old_r_q12_i,
    input  logic [12:0]          s_old_g_q12_i,
    input  logic [12:0]          s_old_b_q12_i,
    input  logic [15:0]          s_old_t_q16_i,
    input  logic [12:0]          s_color_r_q12_i,
    input  logic [12:0]          s_color_g_q12_i,
    input  logic [12:0]          s_color_b_q12_i,
    input  logic [12:0]          s_alpha_q12_i,
    output logic                 m_valid_o,
    input  logic                 m_ready_i,
    output logic [META_W-1:0]    m_meta_o,
    output logic [12:0]          m_new_r_q12_o,
    output logic [12:0]          m_new_g_q12_o,
    output logic [12:0]          m_new_b_q12_o,
    output logic [15:0]          m_new_t_q16_o,
    output logic                 m_newly_terminated_o,
    output logic                 r_pe_req_valid_o,
    input  logic                 r_pe_req_ready_i,
    output logic signed [31:0]   r_pe_lhs_o,
    output logic signed [31:0]   r_pe_rhs_o,
    input  logic                 r_pe_rsp_valid_i,
    output logic                 r_pe_rsp_ready_o,
    input  logic signed [64:0]   r_pe_result_i
);
    localparam int unsigned DATA_W = META_W + 3*13 + 16 + 1;
    localparam logic [16:0] TERMINATION_CODE = 17'(TERMINATION_Q16);
    logic [28:0] weight_product;
    logic [16:0] weight_q16;
    logic [29:0] contribution_r, contribution_g, contribution_b;
    logic [13:0] contribution_r_q12, contribution_g_q12;
    logic [13:0] contribution_b_q12;
    logic [14:0] new_r, new_g, new_b;
    logic [28:0] t_unity_product;
    logic [28:0] t_product;
    logic [16:0] new_t;
    logic old_terminated, new_terminated;
    logic [DATA_W-1:0] result_data;
    logic [META_W-1:0] calc_meta;
    logic [12:0] calc_old_r,calc_old_g,calc_old_b,calc_color_r,calc_color_g,calc_color_b;
    logic [15:0] calc_old_t;
    logic result_valid,result_ready;

    generate if (USE_SHARED_RASTER_PE) begin:g_shared_raster_pe
        // Four ordered contexts match the largest state window. Requests can
        // issue every cycle, while G/P arbitration may delay any grant. R
        // responses remain in request order, so no extra response tag is needed.
        logic [META_W-1:0] meta_q[0:3];
        logic [12:0] old_r_q[0:3],old_g_q[0:3],old_b_q[0:3];
        logic [12:0] color_r_q[0:3],color_g_q[0:3],color_b_q[0:3],alpha_q[0:3];
        logic [15:0] old_t_q[0:3];
        logic [1:0] write_ptr_q,issue_ptr_q,response_ptr_q;
        logic [2:0] used_q,unissued_q;
        logic accept_fire,request_fire,response_fire;
        // Forward a newly accepted blend straight to the PE when the request
        // queue is empty; a denied grant is retained in the context ring.
        assign r_pe_req_valid_o=(unissued_q!=0)||accept_fire;
        assign r_pe_lhs_o=$signed({16'b0,(unissued_q!=0?old_t_q[issue_ptr_q]:s_old_t_q16_i)});
        assign r_pe_rhs_o=$signed({19'b0,(unissued_q!=0?alpha_q[issue_ptr_q]:s_alpha_q12_i)});
        assign r_pe_rsp_ready_o=(used_q>unissued_q)&&result_ready;
        assign result_valid=(used_q>unissued_q)&&r_pe_rsp_valid_i;
        assign response_fire=result_valid&&result_ready;
        assign s_ready_o=(used_q<4)||response_fire;
        assign accept_fire=s_valid_i&&s_ready_o;
        assign request_fire=r_pe_req_valid_o&&r_pe_req_ready_i;
        assign weight_product=r_pe_result_i[28:0];
        assign calc_meta=meta_q[response_ptr_q];
        assign calc_old_r=old_r_q[response_ptr_q];
        assign calc_old_g=old_g_q[response_ptr_q];
        assign calc_old_b=old_b_q[response_ptr_q];
        assign calc_old_t=old_t_q[response_ptr_q];
        assign calc_color_r=color_r_q[response_ptr_q];
        assign calc_color_g=color_g_q[response_ptr_q];
        assign calc_color_b=color_b_q[response_ptr_q];
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                write_ptr_q<='0;issue_ptr_q<='0;response_ptr_q<='0;
                used_q<='0;unissued_q<='0;
            end else begin
                if (accept_fire) begin
                    meta_q[write_ptr_q]<=s_meta_i;
                    old_r_q[write_ptr_q]<=s_old_r_q12_i;old_g_q[write_ptr_q]<=s_old_g_q12_i;
                    old_b_q[write_ptr_q]<=s_old_b_q12_i;old_t_q[write_ptr_q]<=s_old_t_q16_i;
                    color_r_q[write_ptr_q]<=s_color_r_q12_i;color_g_q[write_ptr_q]<=s_color_g_q12_i;
                    color_b_q[write_ptr_q]<=s_color_b_q12_i;alpha_q[write_ptr_q]<=s_alpha_q12_i;
                    write_ptr_q<=write_ptr_q+2'd1;
                end
                if (request_fire)issue_ptr_q<=issue_ptr_q+2'd1;
                if (response_fire)response_ptr_q<=response_ptr_q+2'd1;
                case ({accept_fire,response_fire})
                    2'b10:used_q<=used_q+3'd1;
                    2'b01:used_q<=used_q-3'd1;
                    default:used_q<=used_q;
                endcase
                case ({accept_fire,request_fire})
                    2'b10:unissued_q<=unissued_q+3'd1;
                    2'b01:unissued_q<=unissued_q-3'd1;
                    default:unissued_q<=unissued_q;
                endcase
            end
        end
`ifndef SYNTHESIS
        assert property (@(posedge clk_i) disable iff (!rst_ni) used_q<=4&&unissued_q<=used_q);
        assert property (@(posedge clk_i) disable iff (!rst_ni)
            r_pe_rsp_valid_i && r_pe_rsp_ready_o |-> r_pe_result_i[64:29]=='0);
`endif
    end else begin:g_local_weight
        assign r_pe_req_valid_o=1'b0;
        assign r_pe_lhs_o='0;
        assign r_pe_rhs_o='0;
        assign r_pe_rsp_ready_o=1'b1;
        assign result_valid=s_valid_i;
        assign s_ready_o=result_ready;
        assign weight_product=s_old_t_q16_i*s_alpha_q12_i;
        assign calc_meta=s_meta_i;
        assign calc_old_r=s_old_r_q12_i;
        assign calc_old_g=s_old_g_q12_i;
        assign calc_old_b=s_old_b_q12_i;
        assign calc_old_t=s_old_t_q16_i;
        assign calc_color_r=s_color_r_q12_i;
        assign calc_color_g=s_color_g_q12_i;
        assign calc_color_b=s_color_b_q12_i;
    end endgenerate

    assign weight_q16 = 17'((weight_product + 29'd2048) >> 12);
    assign contribution_r = weight_q16 * calc_color_r;
    assign contribution_g = weight_q16 * calc_color_g;
    assign contribution_b = weight_q16 * calc_color_b;
    assign contribution_r_q12 = 14'((contribution_r + 30'd32768) >> 16);
    assign contribution_g_q12 = 14'((contribution_g + 30'd32768) >> 16);
    assign contribution_b_q12 = 14'((contribution_b + 30'd32768) >> 16);
    assign new_r = {2'b00, calc_old_r} + {1'b0, contribution_r_q12};
    assign new_g = {2'b00, calc_old_g} + {1'b0, contribution_g_q12};
    assign new_b = {2'b00, calc_old_b} + {1'b0, contribution_b_q12};

    // Reuse old_t*alpha for transmittance.  Arithmetic is modulo 2^29, so
    // this is bit-equivalent to old_t*(4096-alpha) for every 13-bit alpha,
    // while removing a second 16x13 multiplier from every blend lane.
    assign t_unity_product = {1'b0, calc_old_t, 12'b0};
    assign t_product = t_unity_product - weight_product;
    assign new_t = 17'((t_product + 29'd2048) >> 12);
    assign old_terminated = {1'b0, calc_old_t} <= TERMINATION_CODE;
    assign new_terminated = new_t <= TERMINATION_CODE;
    assign result_data = {
        calc_meta,
        new_r > 15'd4096 ? 13'd4096 : new_r[12:0],
        new_g > 15'd4096 ? 13'd4096 : new_g[12:0],
        new_b > 15'd4096 ? 13'd4096 : new_b[12:0],
        new_t > 17'd65535 ? 16'hffff : new_t[15:0],
        !old_terminated && new_terminated
    };

    // Shared mode already has an elastic result register in the PE. Consume
    // that response directly: holding it also holds its context and every
    // derived color/T bit. A second result register added a needless cycle to
    // the same-pixel recurrence, and duplicated storage for all metadata.
    generate if(USE_SHARED_RASTER_PE)begin:g_pe_result
      assign m_valid_o=result_valid;
      assign result_ready=m_ready_i;
      assign {m_meta_o,m_new_r_q12_o,m_new_g_q12_o,m_new_b_q12_o,
        m_new_t_q16_o,m_newly_terminated_o}=result_data;
    end else begin:g_local_result
    rv_reg_slice #(.DATA_W(DATA_W)) u_result (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .s_valid_i(result_valid), .s_ready_o(result_ready), .s_data_i(result_data),
        .m_valid_o(m_valid_o), .m_ready_i(m_ready_i),
        .m_data_o({m_meta_o, m_new_r_q12_o, m_new_g_q12_o,
                   m_new_b_q12_o, m_new_t_q16_o, m_newly_terminated_o})
    );
    end endgenerate

`ifndef SYNTHESIS
    initial assert (TERMINATION_Q16 < 65536);
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        m_valid_o && !m_ready_i
        |=> m_valid_o && $stable({m_meta_o, m_new_r_q12_o, m_new_g_q12_o,
                                  m_new_b_q12_o, m_new_t_q16_o,
                                  m_newly_terminated_o}));
`endif
endmodule
