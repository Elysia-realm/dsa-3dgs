// Convert sorted metadata into an ordered full-attribute stream through a
// replaceable request/response backend. Exactly one request may be outstanding.
// Both metadata and the complete attribute response are captured locally, so
// neither an SRAM nor an AXI backend must hold payload after response handshake.
module ordered_gaussian_attribute_issue #(
    parameter int unsigned GID_W=32,parameter int unsigned SEQ_W=16,
    parameter int unsigned DEPTH_W=27,parameter int unsigned GROUP_W=2,
    parameter int unsigned COORD_W=27,parameter int unsigned QUAT_W=22,
    parameter int unsigned SCALE_W=24,parameter int unsigned COEFF_W=18,
    parameter int unsigned COEFFS=16,
    parameter int unsigned COEFF_FLAT_W=3*COEFFS*COEFF_W,
    parameter int unsigned ATTR_W=3*COORD_W+4*QUAT_W+3*SCALE_W+13+COEFF_FLAT_W,
    parameter bit ENABLE_OUTPUT_TURNOVER=1'b1,
    parameter bit ENABLE_RESPONSE_BYPASS=1'b1
) (
    input logic clk_i,input logic rst_ni,input logic clear_errors_i,
    input logic s_valid_i,output logic s_ready_o,input logic signed[DEPTH_W-1:0]s_depth_i,
    input logic[GID_W-1:0]s_gid_i,input logic[SEQ_W-1:0]s_seq_i,
    input logic[GROUP_W-1:0]s_group_i,input logic s_group_first_i,s_group_last_i,

    output logic attr_req_valid_o,input logic attr_req_ready_i,
    output logic[GID_W-1:0]attr_req_gid_o,
    input logic attr_rsp_valid_i,output logic attr_rsp_ready_o,
    input logic attr_rsp_in_range_i,attr_rsp_loaded_i,attr_rsp_error_i,
    input logic[ATTR_W-1:0]attr_rsp_data_i,

    output logic m_valid_o,input logic m_ready_i,
    output logic signed[DEPTH_W-1:0]m_depth_o,
    output logic[GID_W-1:0]m_gid_o,output logic[SEQ_W-1:0]m_seq_o,
    output logic[GROUP_W-1:0]m_group_o,output logic m_group_first_o,m_group_last_o,
    output logic[ATTR_W-1:0]m_attr_data_o,
    output logic invalid_gid_sticky_o,unloaded_gid_sticky_o,backend_error_sticky_o,
    output logic read_pulse_o,idle_o
);
    logic pending_q,response_available_q,request_fire,response_fire,m_fire;
    logic[ATTR_W-1:0]attr_data_q;
    logic response_good,response_bypass;

    // Response has already been captured; retiring it can launch the next
    // ordered backend request on the same edge, still one request outstanding.
    assign attr_req_valid_o=s_valid_i&&(!pending_q||(ENABLE_OUTPUT_TURNOVER&&m_fire));
    assign attr_req_gid_o=s_gid_i;
    assign s_ready_o=(!pending_q||(ENABLE_OUTPUT_TURNOVER&&m_fire))&&attr_req_ready_i;
    assign request_fire=attr_req_valid_o&&attr_req_ready_i;
    assign attr_rsp_ready_o=pending_q&&!response_available_q;
    assign response_fire=attr_rsp_valid_i&&attr_rsp_ready_o;
    assign response_good=attr_rsp_in_range_i&&attr_rsp_loaded_i&&!attr_rsp_error_i;
    assign response_bypass=ENABLE_RESPONSE_BYPASS&&pending_q&&!response_available_q&&attr_rsp_valid_i&&response_good;
    // A good live response can be consumed directly. When downstream stalls,
    // capture the exact same data and keep valid asserted from the register.
    assign m_valid_o=pending_q&&(response_available_q||response_bypass);
    assign m_fire=m_valid_o&&m_ready_i;
    assign m_attr_data_o=response_available_q?attr_data_q:
      response_bypass?attr_rsp_data_i:attr_data_q;
    assign read_pulse_o=request_fire;
    assign idle_o=!pending_q;

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        pending_q<=0;response_available_q<=0;attr_data_q<='0;
        m_depth_o<='0;m_gid_o<='0;m_seq_o<='0;m_group_o<='0;
        m_group_first_o<=0;m_group_last_o<=0;
        invalid_gid_sticky_o<=0;unloaded_gid_sticky_o<=0;backend_error_sticky_o<=0;
      end else begin
        if(request_fire)begin
          pending_q<=1;response_available_q<=0;
          m_depth_o<=s_depth_i;m_gid_o<=s_gid_i;m_seq_o<=s_seq_i;m_group_o<=s_group_i;
          m_group_first_o<=s_group_first_i;m_group_last_o<=s_group_last_i;
        end
        if(response_fire)begin
          if(attr_rsp_error_i||!attr_rsp_in_range_i||!attr_rsp_loaded_i)begin
            pending_q<=0;response_available_q<=0;
            if(attr_rsp_error_i)backend_error_sticky_o<=1;
            else if(!attr_rsp_in_range_i)invalid_gid_sticky_o<=1;
            else unloaded_gid_sticky_o<=1;
          end else begin
            attr_data_q<=attr_rsp_data_i;
            response_available_q<=1;
          end
        end
        // Last priority: simultaneous bypass-retire/new-request leaves only
        // the NEW request pending, never marks the OLD response available.
        if(m_fire)begin pending_q<=request_fire;response_available_q<=0;end
        if(clear_errors_i)begin
          invalid_gid_sticky_o<=0;unloaded_gid_sticky_o<=0;backend_error_sticky_o<=0;
        end
      end
    end
`ifndef SYNTHESIS
    assert property(@(posedge clk_i)disable iff(!rst_ni)attr_req_valid_o&&!attr_req_ready_i
      |=>attr_req_valid_o&&$stable(attr_req_gid_o));
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_valid_o&&!m_ready_i
      |=>m_valid_o&&$stable({m_depth_o,m_gid_o,m_seq_o,m_group_o,m_group_first_o,
        m_group_last_o,m_attr_data_o}));
`endif
endmodule
