// One ordered XYZ transform before projection-lane dispatch. Independent
// axes are interleaved through the shared P-client MAC, with per-axis
// dependency tracking. No local multiplier or arithmetic response reordering.
module world_to_camera_shared_mac #(
    parameter int unsigned META_W=64,
    parameter int unsigned COORD_W=27,
    parameter int unsigned ROT_W=22,
    parameter int unsigned ROT_FRAC=20,
    parameter int unsigned PE_DATA_W=32,
    parameter bit USE_DOT3=1'b0,
    parameter int unsigned PE_RESULT_W=2*PE_DATA_W+1,
    parameter bit ENABLE_OUTPUT_TURNOVER=1'b1,
    parameter bit ENABLE_FIRST_REQUEST_BYPASS=1'b1
) (
    input logic clk_i,rst_ni,
    input logic s_valid_i,output logic s_ready_o,input logic[META_W-1:0]s_meta_i,
    input logic signed[COORD_W-1:0]s_world_x_q16_i,s_world_y_q16_i,s_world_z_q16_i,
    input logic signed[ROT_W-1:0]cfg_r00_q20_i,cfg_r01_q20_i,cfg_r02_q20_i,
    input logic signed[ROT_W-1:0]cfg_r10_q20_i,cfg_r11_q20_i,cfg_r12_q20_i,
    input logic signed[ROT_W-1:0]cfg_r20_q20_i,cfg_r21_q20_i,cfg_r22_q20_i,
    input logic signed[COORD_W-1:0]cfg_tx_q16_i,cfg_ty_q16_i,cfg_tz_q16_i,
    output logic m_valid_o,input logic m_ready_i,output logic[META_W-1:0]m_meta_o,
    output logic signed[COORD_W-1:0]m_camera_x_q16_o,m_camera_y_q16_o,m_camera_z_q16_o,
    output logic m_overflow_o,output logic busy_o,
    output logic pe_req_valid_o,input logic pe_req_ready_i,
    output logic signed[PE_DATA_W-1:0]pe_lhs_o,pe_rhs_o,
    output logic signed[PE_RESULT_W-1:0]pe_acc_o,
    input logic pe_rsp_valid_i,output logic pe_rsp_ready_o,
    input logic signed[PE_RESULT_W-1:0]pe_result_i
);
    typedef enum logic[1:0]{IDLE,RUN,OUT}state_t;
    state_t state_q;
    logic[META_W-1:0]meta_q;
    logic signed[COORD_W-1:0]world_q[0:2],camera_q[0:2];
    logic signed[ROT_W-1:0]rotation_q[0:2][0:2];
    logic signed[PE_RESULT_W-1:0]acc_q[0:2];
    logic[2:0]acc_valid_q;
    logic[1:0]issue_axis_q,issue_col_q,response_axis_q,response_col_q;
    logic[3:0]issued_q,received_q;
    logic overflow_q;
    logic request_fire,response_fire;
    logic first_launch,first_request_fire;
    localparam int REQUESTS=USE_DOT3?3:9;

    function automatic logic signed[PE_RESULT_W:0]rounded_shift(
      input logic signed[PE_RESULT_W-1:0]value);
      logic signed[PE_RESULT_W:0]v,mag,bias;
      begin
        v={value[PE_RESULT_W-1],value};
        bias={{PE_RESULT_W{1'b0}},1'b1}<<<(ROT_FRAC-1);
        if(v>=0)rounded_shift=(v+bias)>>>ROT_FRAC;
        else begin mag=-v;rounded_shift=-((mag+bias)>>>ROT_FRAC);end
      end
    endfunction
    function automatic logic overflow(input logic signed[PE_RESULT_W:0]v);
      logic signed[PE_RESULT_W:0]hi,lo;
      begin
        hi=({{PE_RESULT_W{1'b0}},1'b1}<<<(COORD_W-1))-1;
        lo=-({{PE_RESULT_W{1'b0}},1'b1}<<<(COORD_W-1));
        overflow=v>hi||v<lo;
      end
    endfunction
    function automatic logic signed[COORD_W-1:0]saturate(input logic signed[PE_RESULT_W:0]v);
      begin
        if(overflow(v))saturate=v<0?{1'b1,{(COORD_W-1){1'b0}}}:{1'b0,{(COORD_W-1){1'b1}}};
        else saturate=v[COORD_W-1:0];
      end
    endfunction
    function automatic logic signed[PE_RESULT_W-1:0]translation(
      input logic signed[COORD_W-1:0]v);
      translation={{(PE_RESULT_W-COORD_W){v[COORD_W-1]}},v}<<<ROT_FRAC;
    endfunction

    // A retiring result can release its single context on this same edge.
    // No overwrite while output is stalled, and no same-edge MAC issuance.
    assign s_ready_o=state_q==IDLE||(ENABLE_OUTPUT_TURNOVER&&state_q==OUT&&m_ready_i);
    assign m_valid_o=state_q==OUT;
    assign busy_o=state_q!=IDLE;
    assign m_meta_o=meta_q;
    assign m_camera_x_q16_o=camera_q[0];
    assign m_camera_y_q16_o=camera_q[1];
    assign m_camera_z_q16_o=camera_q[2];
    assign m_overflow_o=overflow_q;
    assign first_launch=ENABLE_FIRST_REQUEST_BYPASS&&s_valid_i&&s_ready_o;
    assign first_request_fire=first_launch&&pe_req_ready_i;
    assign pe_req_valid_o=(state_q==RUN&&issued_q<REQUESTS&&acc_valid_q[issue_axis_q])||first_launch;
    assign pe_rsp_ready_o=state_q==RUN&&received_q<issued_q;
    generate if(USE_DOT3)begin:g_dot3_operands
      assign pe_lhs_o=first_launch?
        {32'($signed(s_world_z_q16_i)),32'($signed(s_world_y_q16_i)),32'($signed(s_world_x_q16_i))}:
        {32'($signed(world_q[2])),32'($signed(world_q[1])),32'($signed(world_q[0]))};
      assign pe_rhs_o=first_launch?
        {32'($signed(cfg_r02_q20_i)),32'($signed(cfg_r01_q20_i)),32'($signed(cfg_r00_q20_i))}:
        {32'($signed(rotation_q[issue_axis_q][2])),32'($signed(rotation_q[issue_axis_q][1])),32'($signed(rotation_q[issue_axis_q][0]))};
    end else begin:g_scalar_operands
    assign pe_lhs_o=first_launch?{{(PE_DATA_W-COORD_W){s_world_x_q16_i[COORD_W-1]}},s_world_x_q16_i}:
      {{(PE_DATA_W-COORD_W){world_q[issue_col_q][COORD_W-1]}},world_q[issue_col_q]};
    assign pe_rhs_o=first_launch?{{(PE_DATA_W-ROT_W){cfg_r00_q20_i[ROT_W-1]}},cfg_r00_q20_i}:
      {{(PE_DATA_W-ROT_W){rotation_q[issue_axis_q][issue_col_q][ROT_W-1]}},rotation_q[issue_axis_q][issue_col_q]};
    end endgenerate
    assign pe_acc_o=first_launch?translation(cfg_tx_q16_i):acc_q[issue_axis_q];
    assign request_fire=pe_req_valid_o&&pe_req_ready_i;
    assign response_fire=pe_rsp_valid_i&&pe_rsp_ready_o;

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        state_q<=IDLE;meta_q<='0;acc_valid_q<='0;issued_q<='0;received_q<='0;
        issue_axis_q<='0;issue_col_q<='0;response_axis_q<='0;response_col_q<='0;overflow_q<=0;
        for(int a=0;a<3;a++)begin
          world_q[a]<='0;camera_q[a]<='0;acc_q[a]<='0;
          for(int c=0;c<3;c++)rotation_q[a][c]<='0;
        end
      end else begin
        case(state_q)
          IDLE:begin end
          RUN:begin
            if(request_fire)begin
              issued_q<=issued_q+1'b1;acc_valid_q[issue_axis_q]<=0;
              if(issue_axis_q==2)begin issue_axis_q<=0;if(issue_col_q<2)issue_col_q<=issue_col_q+1'b1;end
              else issue_axis_q<=issue_axis_q+1'b1;
            end
            if(response_fire)begin
              received_q<=received_q+1'b1;acc_q[response_axis_q]<=pe_result_i;acc_valid_q[response_axis_q]<=1;
              if(USE_DOT3||response_col_q==2)begin
                camera_q[response_axis_q]<=saturate(rounded_shift(pe_result_i));
                overflow_q<=overflow_q||overflow(rounded_shift(pe_result_i));
              end
              if(response_axis_q==2)begin response_axis_q<=0;if(response_col_q<2)response_col_q<=response_col_q+1'b1;end
              else response_axis_q<=response_axis_q+1'b1;
              if(received_q==REQUESTS-1)state_q<=OUT;
            end
          end
          OUT:if(m_valid_o&&m_ready_i)state_q<=IDLE;
          default:state_q<=IDLE;
        endcase
        if(s_valid_i&&s_ready_o)begin
            meta_q<=s_meta_i;
            world_q[0]<=s_world_x_q16_i;world_q[1]<=s_world_y_q16_i;world_q[2]<=s_world_z_q16_i;
            rotation_q[0][0]<=cfg_r00_q20_i;rotation_q[0][1]<=cfg_r01_q20_i;rotation_q[0][2]<=cfg_r02_q20_i;
            rotation_q[1][0]<=cfg_r10_q20_i;rotation_q[1][1]<=cfg_r11_q20_i;rotation_q[1][2]<=cfg_r12_q20_i;
            rotation_q[2][0]<=cfg_r20_q20_i;rotation_q[2][1]<=cfg_r21_q20_i;rotation_q[2][2]<=cfg_r22_q20_i;
            acc_q[0]<=translation(cfg_tx_q16_i);acc_q[1]<=translation(cfg_ty_q16_i);acc_q[2]<=translation(cfg_tz_q16_i);
            // Capture unconditionally, even if first request loses arbitration.
            // That unaccepted request retries with identical latched operands.
            issued_q<=first_request_fire?4'd1:4'd0;received_q<=0;
            issue_axis_q<=first_request_fire?2'd1:2'd0;issue_col_q<=0;response_axis_q<=0;response_col_q<=0;
            acc_valid_q<=first_request_fire?3'b110:3'b111;overflow_q<=0;state_q<=RUN;
        end
      end
    end
`ifndef SYNTHESIS
    initial begin
      assert(PE_DATA_W>=COORD_W&&PE_DATA_W>=ROT_W);
      assert(PE_RESULT_W>=COORD_W+ROT_W+2);
    end
    assert property(@(posedge clk_i)disable iff(!rst_ni)received_q<=issued_q&&issued_q<=9);
    assert property(@(posedge clk_i)disable iff(!rst_ni)request_fire&&response_fire|->issue_axis_q!=response_axis_q);
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_valid_o&&!m_ready_i
      |=>$stable({m_meta_o,m_camera_x_q16_o,m_camera_y_q16_o,m_camera_z_q16_o,m_overflow_o}));
`endif
endmodule
