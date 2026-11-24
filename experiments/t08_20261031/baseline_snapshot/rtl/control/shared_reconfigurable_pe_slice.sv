// One physically shared compare/MAC datapath for the G/P/R clients.
//
// OP_COMPARE implements the stable sorter key predicate
//   (signed depth, unsigned gid, unsigned sequence) lhs < rhs.
// OP_MAC implements a signed full-precision lhs*rhs+acc operation.
//
// A weighted credit round controls access to the single result register.
// shared_owner_i is the first preference while that client's credit remains;
// round-robin order prevents the other active clients from starving after the
// preferred credit is exhausted.  The result register is an elastic boundary:
// a stalled response is held bit-exact and blocks every requester.
//
// This is the first standalone physical PE slice.  It intentionally is not yet
// inserted into the production sorter/projection/raster paths; that integration
// requires stage-specific context adapters and ordered-drain verification.
module shared_reconfigurable_pe_slice #(
    parameter int unsigned DATA_W=32,
    parameter bit P_DOT3=1'b0,
    parameter int unsigned GID_W=32,
    parameter int unsigned SEQ_W=16,
    parameter int unsigned RESULT_W=2*DATA_W+1
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [2:0] group_weight_i,
    input  logic [2:0] projection_weight_i,
    input  logic [2:0] raster_weight_i,
    input  logic [1:0] shared_owner_i,
    input  logic aggressive_clock_gate_i,
    input  logic reconfigure_i,

    input  logic g_valid_i,
    output logic g_ready_o,
    input  logic g_op_mac_i,
    input  logic signed [DATA_W-1:0] g_lhs_i,
    input  logic signed [DATA_W-1:0] g_rhs_i,
    input  logic signed [RESULT_W-1:0] g_acc_i,
    input  logic [GID_W-1:0] g_lhs_gid_i,
    input  logic [GID_W-1:0] g_rhs_gid_i,
    input  logic [SEQ_W-1:0] g_lhs_seq_i,
    input  logic [SEQ_W-1:0] g_rhs_seq_i,
    output logic g_rsp_valid_o,
    input  logic g_rsp_ready_i,
    output logic signed [RESULT_W-1:0] g_result_o,
    output logic g_less_o,

    input  logic p_valid_i,
    output logic p_ready_o,
    input  logic p_op_mac_i,
    input  logic signed [DATA_W-1:0] p_lhs_i,
    input  logic signed [DATA_W-1:0] p_rhs_i,
    input  logic signed [RESULT_W-1:0] p_acc_i,
    input  logic [GID_W-1:0] p_lhs_gid_i,
    input  logic [GID_W-1:0] p_rhs_gid_i,
    input  logic [SEQ_W-1:0] p_lhs_seq_i,
    input  logic [SEQ_W-1:0] p_rhs_seq_i,
    output logic p_rsp_valid_o,
    input  logic p_rsp_ready_i,
    output logic signed [RESULT_W-1:0] p_result_o,
    output logic p_less_o,

    input  logic r_valid_i,
    output logic r_ready_o,
    input  logic r_op_mac_i,
    input  logic signed [DATA_W-1:0] r_lhs_i,
    input  logic signed [DATA_W-1:0] r_rhs_i,
    input  logic signed [RESULT_W-1:0] r_acc_i,
    input  logic [GID_W-1:0] r_lhs_gid_i,
    input  logic [GID_W-1:0] r_rhs_gid_i,
    input  logic [SEQ_W-1:0] r_lhs_seq_i,
    input  logic [SEQ_W-1:0] r_rhs_seq_i,
    output logic r_rsp_valid_o,
    input  logic r_rsp_ready_i,
    output logic signed [RESULT_W-1:0] r_result_o,
    output logic r_less_o,

    output logic group_grant_pulse_o,
    output logic projection_grant_pulse_o,
    output logic raster_grant_pulse_o,
    output logic group_stall_o,
    output logic projection_stall_o,
    output logic raster_stall_o,
    output logic utilization_pulse_o,
    output logic clock_enable_o,
    output logic busy_o
);
    localparam logic [1:0] CLIENT_G=2'd0,CLIENT_P=2'd1,CLIENT_R=2'd2;
    logic [2:0] g_credit_q,p_credit_q,r_credit_q;
    logic [1:0] rr_q,selected_client;
    logic selected_valid,reload_credits;
    logic selected_op_mac;
    logic signed [DATA_W-1:0] selected_lhs,selected_rhs;
    logic signed [RESULT_W-1:0] selected_acc;
    logic [GID_W-1:0] selected_lhs_gid,selected_rhs_gid;
    logic [SEQ_W-1:0] selected_lhs_seq,selected_rhs_seq;
    logic out_valid_q,out_ready,accept;
    logic [1:0] out_client_q;
    logic signed [RESULT_W-1:0] out_result_q;
    logic out_less_q;
    localparam int ARITH_W=P_DOT3?32:DATA_W;
    logic signed [2*ARITH_W-1:0] selected_product;
    logic signed [RESULT_W-1:0] selected_product_extended;
    logic selected_less;
    logic g_eligible,p_eligible,r_eligible;

    function automatic logic key_less(
      input logic signed [DATA_W-1:0] lhs_depth,
      input logic [GID_W-1:0] lhs_gid,input logic [SEQ_W-1:0] lhs_seq,
      input logic signed [DATA_W-1:0] rhs_depth,
      input logic [GID_W-1:0] rhs_gid,input logic [SEQ_W-1:0] rhs_seq);
      begin
        key_less=(lhs_depth<rhs_depth)||
          ((lhs_depth==rhs_depth)&&((lhs_gid<rhs_gid)||
          ((lhs_gid==rhs_gid)&&(lhs_seq<rhs_seq))));
      end
    endfunction

    always_comb begin
      reload_credits=!(g_valid_i&&g_credit_q!=0)&&
        !(p_valid_i&&p_credit_q!=0)&&!(r_valid_i&&r_credit_q!=0)&&
        (g_valid_i||p_valid_i||r_valid_i);
      g_eligible=g_valid_i&&(reload_credits?(group_weight_i!=0):(g_credit_q!=0));
      p_eligible=p_valid_i&&(reload_credits?(projection_weight_i!=0):(p_credit_q!=0));
      r_eligible=r_valid_i&&(reload_credits?(raster_weight_i!=0):(r_credit_q!=0));
      selected_valid=1'b0;selected_client=CLIENT_G;
      // Owner preference consumes only its finite credit.  E (2'b11) falls
      // through to round-robin because there is no fourth arithmetic client.
      case(shared_owner_i)
        CLIENT_G:if(g_eligible)begin selected_valid=1'b1;selected_client=CLIENT_G;end
        CLIENT_P:if(p_eligible)begin selected_valid=1'b1;selected_client=CLIENT_P;end
        CLIENT_R:if(r_eligible)begin selected_valid=1'b1;selected_client=CLIENT_R;end
        default:begin end
      endcase
      if(!selected_valid)begin
        case(rr_q)
          CLIENT_G:begin
            if(g_eligible)begin selected_valid=1;selected_client=CLIENT_G;end
            else if(p_eligible)begin selected_valid=1;selected_client=CLIENT_P;end
            else if(r_eligible)begin selected_valid=1;selected_client=CLIENT_R;end
          end
          CLIENT_P:begin
            if(p_eligible)begin selected_valid=1;selected_client=CLIENT_P;end
            else if(r_eligible)begin selected_valid=1;selected_client=CLIENT_R;end
            else if(g_eligible)begin selected_valid=1;selected_client=CLIENT_G;end
          end
          default:begin
            if(r_eligible)begin selected_valid=1;selected_client=CLIENT_R;end
            else if(g_eligible)begin selected_valid=1;selected_client=CLIENT_G;end
            else if(p_eligible)begin selected_valid=1;selected_client=CLIENT_P;end
          end
        endcase
      end
      if(reconfigure_i)selected_valid=1'b0;
    end

    always_comb begin
      selected_op_mac=g_op_mac_i;selected_lhs=g_lhs_i;selected_rhs=g_rhs_i;
      selected_acc=g_acc_i;selected_lhs_gid=g_lhs_gid_i;selected_rhs_gid=g_rhs_gid_i;
      selected_lhs_seq=g_lhs_seq_i;selected_rhs_seq=g_rhs_seq_i;
      case(selected_client)
        CLIENT_P:begin
          selected_op_mac=p_op_mac_i;selected_lhs=p_lhs_i;selected_rhs=p_rhs_i;
          selected_acc=p_acc_i;selected_lhs_gid=p_lhs_gid_i;selected_rhs_gid=p_rhs_gid_i;
          selected_lhs_seq=p_lhs_seq_i;selected_rhs_seq=p_rhs_seq_i;
        end
        CLIENT_R:begin
          selected_op_mac=r_op_mac_i;selected_lhs=r_lhs_i;selected_rhs=r_rhs_i;
          selected_acc=r_acc_i;selected_lhs_gid=r_lhs_gid_i;selected_rhs_gid=r_rhs_gid_i;
          selected_lhs_seq=r_lhs_seq_i;selected_rhs_seq=r_rhs_seq_i;
        end
        default:begin end
      endcase
    end

    assign g_rsp_valid_o=out_valid_q&&out_client_q==CLIENT_G;
    assign p_rsp_valid_o=out_valid_q&&out_client_q==CLIENT_P;
    assign r_rsp_valid_o=out_valid_q&&out_client_q==CLIENT_R;
    assign g_result_o=out_result_q;assign p_result_o=out_result_q;assign r_result_o=out_result_q;
    assign g_less_o=out_less_q;assign p_less_o=out_less_q;assign r_less_o=out_less_q;
    assign out_ready=!out_valid_q||
      (out_client_q==CLIENT_G&&g_rsp_ready_i)||
      (out_client_q==CLIENT_P&&p_rsp_ready_i)||
      (out_client_q==CLIENT_R&&r_rsp_ready_i);
    assign g_ready_o=out_ready&&selected_valid&&selected_client==CLIENT_G;
    assign p_ready_o=out_ready&&selected_valid&&selected_client==CLIENT_P;
    assign r_ready_o=out_ready&&selected_valid&&selected_client==CLIENT_R;
    assign accept=selected_valid&&out_ready&&
      ((selected_client==CLIENT_G&&g_valid_i)||
       (selected_client==CLIENT_P&&p_valid_i)||
       (selected_client==CLIENT_R&&r_valid_i));

    assign selected_product=$signed(selected_lhs[ARITH_W-1:0])*$signed(selected_rhs[ARITH_W-1:0]);
    generate if(P_DOT3)begin:g_dot3
      logic signed[63:0]product1,product2;
      logic signed[RESULT_W-1:0]term0,term1,term2;
      assign product1=$signed(p_lhs_i[63:32])*$signed(p_rhs_i[63:32]);
      assign product2=$signed(p_lhs_i[95:64])*$signed(p_rhs_i[95:64]);
      assign term0={{(RESULT_W-64){selected_product[63]}},selected_product};
      assign term1={{(RESULT_W-64){product1[63]}},product1};
      assign term2={{(RESULT_W-64){product2[63]}},product2};
      assign selected_product_extended=term0+((selected_client==CLIENT_P&&selected_op_mac)?term1+term2:RESULT_W'(0));
`ifndef SYNTHESIS
      initial begin assert(DATA_W==96);assert(RESULT_W>=65);end
`endif
    end else begin:g_scalar
      assign selected_product_extended={{(RESULT_W-2*DATA_W){selected_product[2*DATA_W-1]}},selected_product};
    end endgenerate
    assign selected_less=key_less(selected_lhs,selected_lhs_gid,selected_lhs_seq,
                                  selected_rhs,selected_rhs_gid,selected_rhs_seq);
    assign group_grant_pulse_o=accept&&selected_client==CLIENT_G;
    assign projection_grant_pulse_o=accept&&selected_client==CLIENT_P;
    assign raster_grant_pulse_o=accept&&selected_client==CLIENT_R;
    assign group_stall_o=g_valid_i&&!g_ready_o;
    assign projection_stall_o=p_valid_i&&!p_ready_o;
    assign raster_stall_o=r_valid_i&&!r_ready_o;
    assign utilization_pulse_o=accept;
    assign clock_enable_o=!aggressive_clock_gate_i||reconfigure_i||g_valid_i||p_valid_i||r_valid_i||out_valid_q;
    assign busy_o=out_valid_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if(!rst_ni)begin
        g_credit_q<='0;p_credit_q<='0;r_credit_q<='0;rr_q<=CLIENT_G;
        out_valid_q<=1'b0;out_client_q<=CLIENT_G;out_result_q<='0;out_less_q<=1'b0;
      end else begin
        if(reconfigure_i)begin
          g_credit_q<='0;p_credit_q<='0;r_credit_q<='0;
          rr_q<=shared_owner_i==2'd3 ? CLIENT_G : shared_owner_i;
        end
        if(out_ready)out_valid_q<=accept;
        if(accept)begin
          out_client_q<=selected_client;
          out_result_q<=selected_op_mac?(selected_product_extended+selected_acc):'0;
          out_less_q<=!selected_op_mac&&selected_less;
          rr_q<=selected_client==CLIENT_R?CLIENT_G:selected_client+1'b1;
          if(reload_credits)begin
            g_credit_q<=group_weight_i-(selected_client==CLIENT_G);
            p_credit_q<=projection_weight_i-(selected_client==CLIENT_P);
            r_credit_q<=raster_weight_i-(selected_client==CLIENT_R);
          end else begin
            if(selected_client==CLIENT_G)g_credit_q<=g_credit_q-1'b1;
            if(selected_client==CLIENT_P)p_credit_q<=p_credit_q-1'b1;
            if(selected_client==CLIENT_R)r_credit_q<=r_credit_q-1'b1;
          end
        end
      end
    end

`ifndef SYNTHESIS
    initial assert(RESULT_W>=2*ARITH_W+1) else $fatal(1,"RESULT_W cannot hold full MAC result");
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      out_valid_q&&!out_ready|=>out_valid_q&&$stable({out_client_q,out_result_q,out_less_q}));
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      $onehot0({group_grant_pulse_o,projection_grant_pulse_o,raster_grant_pulse_o}));
    assert property(@(posedge clk_i)disable iff(!rst_ni)reconfigure_i|->!out_valid_q)
      else $error("shared PE may only reconfigure after its response is drained");
`endif
endmodule
