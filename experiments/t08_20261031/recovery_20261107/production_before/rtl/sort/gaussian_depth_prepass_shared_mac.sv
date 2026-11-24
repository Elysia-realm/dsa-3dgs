// Depth-prepass adapter that evaluates camera-space Z through the P client of
// shared_reconfigurable_pe_slice.  Three serialized full-precision MACs replace
// the three local multipliers while preserving the original Q16 rounding,
// saturation, visibility and sequence contracts. An ordered context ring
// decouples input/output backpressure from the three-MAC issue stream.
module gaussian_depth_prepass_shared_mac #(
    parameter int unsigned GID_W=32,
    parameter int unsigned SEQ_W=32,
    parameter int unsigned PAYLOAD_W=32,
    parameter int unsigned COORD_W=27,
    parameter int unsigned ROT_W=22,
    parameter int unsigned ROT_FRAC=20,
    parameter int unsigned PE_DATA_W=32,
    parameter bit USE_DOT3=1'b0,
    parameter int unsigned PE_RESULT_W=2*PE_DATA_W+1,
    parameter int unsigned CONTEXTS=4
) (
    input logic clk_i,input logic rst_ni,input logic frame_start_i,
    input logic s_valid_i,output logic s_ready_o,input logic[GID_W-1:0]s_gid_i,
    input logic[PAYLOAD_W-1:0]s_payload_i,
    input logic signed[COORD_W-1:0]s_world_x_q16_i,s_world_y_q16_i,s_world_z_q16_i,
    input logic signed[ROT_W-1:0]cfg_r20_q20_i,cfg_r21_q20_i,cfg_r22_q20_i,
    input logic signed[COORD_W-1:0]cfg_tz_q16_i,
    input logic signed[COORD_W-1:0]cfg_near_q16_i,cfg_far_q16_i,
    output logic m_valid_o,input logic m_ready_i,
    output logic signed[COORD_W-1:0]m_depth_q16_o,
    output logic[GID_W-1:0]m_gid_o,output logic[SEQ_W-1:0]m_seq_o,
    output logic[PAYLOAD_W-1:0]m_payload_o,output logic m_visible_o,
    output logic m_numeric_overflow_o,
    output logic pe_req_valid_o,input logic pe_req_ready_i,
    output logic signed[PE_DATA_W-1:0]pe_lhs_o,pe_rhs_o,
    output logic signed[PE_RESULT_W-1:0]pe_acc_o,
    input logic pe_rsp_valid_i,output logic pe_rsp_ready_o,
    input logic signed[PE_RESULT_W-1:0]pe_result_i
);
    localparam int unsigned SLOT_W=CONTEXTS<=1?1:$clog2(CONTEXTS);
    localparam int unsigned USED_W=$clog2(CONTEXTS+1);
    logic[SLOT_W-1:0]write_q,issue_q,retire_q,rsp_slot_q;
    logic[USED_W-1:0]used_q;
    logic[1:0]col_q,rsp_col_q;
    logic outstanding_q;
    logic[CONTEXTS-1:0]pending_q,done_q;
    logic signed[COORD_W-1:0]xyz_q[CONTEXTS][3],tz_q[CONTEXTS],near_q[CONTEXTS],far_q[CONTEXTS];
    logic signed[ROT_W-1:0]rot_q[CONTEXTS][3];
    logic[GID_W-1:0]gid_q[CONTEXTS];logic[SEQ_W-1:0]seq_q[CONTEXTS],sequence_q;
    logic[PAYLOAD_W-1:0]payload_q[CONTEXTS];
    logic signed[PE_RESULT_W-1:0]acc_q,tz_scaled;
    logic signed[COORD_W-1:0]depth_q[CONTEXTS];
    logic[CONTEXTS-1:0]overflow_q;
    logic input_fire,output_fire,request_fire,response_fire;

    function automatic logic[SLOT_W-1:0]next_slot(input logic[SLOT_W-1:0]slot);
      next_slot=slot==SLOT_W'(CONTEXTS-1)?'0:slot+1'b1;
    endfunction

    function automatic logic signed[PE_RESULT_W-1:0]round_shift(
      input logic signed[PE_RESULT_W-1:0]v);
      logic signed[PE_RESULT_W-1:0]mag,bias;begin
        bias={{(PE_RESULT_W-1){1'b0}},1'b1}<<<(ROT_FRAC-1);
        if(v>=0)round_shift=(v+bias)>>>ROT_FRAC;
        else begin mag=-v;round_shift=-((mag+bias)>>>ROT_FRAC);end
      end
    endfunction
    function automatic logic is_overflow(input logic signed[PE_RESULT_W-1:0]v);
      logic signed[PE_RESULT_W-1:0]maxv,minv;begin
        maxv=({{(PE_RESULT_W-1){1'b0}},1'b1}<<<(COORD_W-1))-1;
        minv=-({{(PE_RESULT_W-1){1'b0}},1'b1}<<<(COORD_W-1));
        is_overflow=v>maxv||v<minv;
      end
    endfunction
    function automatic logic signed[COORD_W-1:0]saturate(
      input logic signed[PE_RESULT_W-1:0]v);
      logic signed[PE_RESULT_W-1:0]maxv,minv;begin
        maxv=({{(PE_RESULT_W-1){1'b0}},1'b1}<<<(COORD_W-1))-1;
        minv=-({{(PE_RESULT_W-1){1'b0}},1'b1}<<<(COORD_W-1));
        if(v>maxv)saturate={1'b0,{(COORD_W-1){1'b1}}};
        else if(v<minv)saturate={1'b1,{(COORD_W-1){1'b0}}};
        else saturate=v[COORD_W-1:0];
      end
    endfunction

    assign s_ready_o=used_q<USED_W'(CONTEXTS);
    assign m_valid_o=used_q!=0&&done_q[retire_q];
    assign m_depth_q16_o=depth_q[retire_q];assign m_gid_o=gid_q[retire_q];assign m_seq_o=seq_q[retire_q];
    assign m_payload_o=payload_q[retire_q];assign m_numeric_overflow_o=overflow_q[retire_q];
    assign m_visible_o=!overflow_q[retire_q]&&depth_q[retire_q]>=near_q[retire_q]&&depth_q[retire_q]<=far_q[retire_q];
    assign pe_rsp_ready_o=outstanding_q;
    assign response_fire=pe_rsp_valid_i&&pe_rsp_ready_o;
    // One outstanding tagged response. A consumed response can feed the next
    // dependent MAC, or start the next Gaussian without an OUT/IDLE bubble.
    assign pe_req_valid_o=pending_q[issue_q]&&(!outstanding_q||response_fire);
    generate if(USE_DOT3)begin:g_dot3_operands
      assign pe_lhs_o={32'($signed(xyz_q[issue_q][2])),32'($signed(xyz_q[issue_q][1])),32'($signed(xyz_q[issue_q][0]))};
      assign pe_rhs_o={32'($signed(rot_q[issue_q][2])),32'($signed(rot_q[issue_q][1])),32'($signed(rot_q[issue_q][0]))};
    end else begin:g_scalar_operands
      assign pe_lhs_o={{(PE_DATA_W-COORD_W){xyz_q[issue_q][col_q][COORD_W-1]}},xyz_q[issue_q][col_q]};
      assign pe_rhs_o={{(PE_DATA_W-ROT_W){rot_q[issue_q][col_q][ROT_W-1]}},rot_q[issue_q][col_q]};
    end endgenerate
    assign tz_scaled={{(PE_RESULT_W-COORD_W){tz_q[issue_q][COORD_W-1]}},tz_q[issue_q]}<<<ROT_FRAC;
    assign pe_acc_o=USE_DOT3?tz_scaled:(col_q==0?'0:(response_fire?pe_result_i:acc_q)+(col_q==2?tz_scaled:'0));
    assign input_fire=s_valid_i&&s_ready_o;
    assign output_fire=m_valid_o&&m_ready_i;
    assign request_fire=pe_req_valid_o&&pe_req_ready_i;

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        sequence_q<='0;write_q<='0;issue_q<='0;retire_q<='0;used_q<='0;
        col_q<='0;rsp_col_q<='0;rsp_slot_q<='0;outstanding_q<=0;
        pending_q<='0;done_q<='0;overflow_q<='0;acc_q<='0;
      end else begin
        if(frame_start_i)sequence_q<=(s_valid_i&&s_ready_o)?{{(SEQ_W-1){1'b0}},1'b1}:'0;
        else if(s_valid_i&&s_ready_o)sequence_q<=sequence_q+1'b1;
        case({input_fire,output_fire})
          2'b10:used_q<=used_q+1'b1;
          2'b01:used_q<=used_q-1'b1;
          default:begin end
        endcase
        if(output_fire)begin done_q[retire_q]<=0;retire_q<=next_slot(retire_q);end
        if(input_fire)begin
          xyz_q[write_q][0]<=s_world_x_q16_i;xyz_q[write_q][1]<=s_world_y_q16_i;xyz_q[write_q][2]<=s_world_z_q16_i;
          rot_q[write_q][0]<=cfg_r20_q20_i;rot_q[write_q][1]<=cfg_r21_q20_i;rot_q[write_q][2]<=cfg_r22_q20_i;
          tz_q[write_q]<=cfg_tz_q16_i;near_q[write_q]<=cfg_near_q16_i;far_q[write_q]<=cfg_far_q16_i;
          gid_q[write_q]<=s_gid_i;seq_q[write_q]<=frame_start_i?'0:sequence_q;payload_q[write_q]<=s_payload_i;
          pending_q[write_q]<=1;done_q[write_q]<=0;write_q<=next_slot(write_q);
        end
        if(response_fire)begin
          outstanding_q<=0;acc_q<=pe_result_i;
          if(USE_DOT3||rsp_col_q==2)begin
            depth_q[rsp_slot_q]<=saturate(round_shift(pe_result_i));
            overflow_q[rsp_slot_q]<=is_overflow(round_shift(pe_result_i));done_q[rsp_slot_q]<=1;
          end
        end
        if(request_fire)begin
          outstanding_q<=1;rsp_slot_q<=issue_q;rsp_col_q<=col_q;
          if(USE_DOT3||col_q==2)begin pending_q[issue_q]<=0;issue_q<=next_slot(issue_q);col_q<=0;end
          else col_q<=col_q+1'b1;
        end
      end
    end

`ifndef SYNTHESIS
    initial begin
      assert(PE_DATA_W>=COORD_W&&PE_DATA_W>=ROT_W);
      assert(PE_RESULT_W>=COORD_W+ROT_W+2);
      assert(CONTEXTS>=1);
    end
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_valid_o&&!m_ready_i
      |=>$stable({m_depth_q16_o,m_gid_o,m_seq_o,m_payload_o,m_visible_o,m_numeric_overflow_o}));
`endif
endmodule
