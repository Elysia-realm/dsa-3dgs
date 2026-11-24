// Frame-front Gaussian depth prepass. Only view-space Z is evaluated from the
// mean, minimizing first-pass attribute traffic. Every accepted source record
// receives a monotonically increasing sequence ID; (depth,GID,sequence) is the
// deterministic grouping/sorting key. Coordinates are Q10.16, rotation Q2.20.
module gaussian_depth_prepass_core #(
    parameter int unsigned GID_W=32,
    parameter int unsigned SEQ_W=32,
    parameter int unsigned PAYLOAD_W=32,
    parameter int unsigned COORD_W=27,
    parameter int unsigned ROT_W=22,
    parameter int unsigned ROT_FRAC=20
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
    output logic m_numeric_overflow_o
);
    localparam int unsigned PRODUCT_W=COORD_W+ROT_W;
    localparam int unsigned ACC_W=PRODUCT_W+2;
    localparam int unsigned DATA_W=COORD_W+GID_W+SEQ_W+PAYLOAD_W+2;
    logic signed[PRODUCT_W-1:0]p0,p1,p2;logic signed[ACC_W-1:0]acc,tz_scaled;
    logic signed[ACC_W:0]shifted;logic signed[COORD_W-1:0]depth;
    logic overflow,visible;logic[SEQ_W-1:0]sequence_q,accepted_sequence;logic[DATA_W-1:0]data;
    function automatic logic signed[ACC_W:0]round_shift(input logic signed[ACC_W-1:0]v);
      logic signed[ACC_W:0]ex,mag;begin ex=$signed({v[ACC_W-1],v});
      if(ex>=0)round_shift=(ex+({{ACC_W{1'b0}},1'b1}<<<(ROT_FRAC-1)))>>>ROT_FRAC;
      else begin mag=-ex;round_shift=-((mag+({{ACC_W{1'b0}},1'b1}<<<(ROT_FRAC-1)))>>>ROT_FRAC);end end
    endfunction
    function automatic logic is_overflow(input logic signed[ACC_W:0]v);
      logic signed[ACC_W:0]maxv,minv;begin
      maxv=({{ACC_W{1'b0}},1'b1}<<<(COORD_W-1))-1;minv=-({{ACC_W{1'b0}},1'b1}<<<(COORD_W-1));
      is_overflow=v>maxv||v<minv;end
    endfunction
    function automatic logic signed[COORD_W-1:0]saturate(input logic signed[ACC_W:0]v);
      logic signed[ACC_W:0]maxv,minv;begin
      maxv=({{ACC_W{1'b0}},1'b1}<<<(COORD_W-1))-1;minv=-({{ACC_W{1'b0}},1'b1}<<<(COORD_W-1));
      if(v>maxv)saturate={1'b0,{(COORD_W-1){1'b1}}};
      else if(v<minv)saturate={1'b1,{(COORD_W-1){1'b0}}};else saturate=v[COORD_W-1:0];end
    endfunction
    assign p0=s_world_x_q16_i*cfg_r20_q20_i;assign p1=s_world_y_q16_i*cfg_r21_q20_i;
    assign p2=s_world_z_q16_i*cfg_r22_q20_i;
    assign tz_scaled=$signed({{(ACC_W-COORD_W){cfg_tz_q16_i[COORD_W-1]}},cfg_tz_q16_i})<<<ROT_FRAC;
    assign acc=p0+p1+p2+tz_scaled;assign shifted=round_shift(acc);assign overflow=is_overflow(shifted);
    assign depth=saturate(shifted);assign visible=!overflow&&depth>=cfg_near_q16_i&&depth<=cfg_far_q16_i;
    // frame_start_i may coincide with the first accepted record.  Giving that
    // record sequence zero here avoids an undocumented setup-cycle contract.
    assign accepted_sequence=frame_start_i?'0:sequence_q;
    assign data={depth,s_gid_i,accepted_sequence,s_payload_i,visible,overflow};
    rv_reg_slice #(.DATA_W(DATA_W))u_result(.clk_i(clk_i),.rst_ni(rst_ni),
      .s_valid_i(s_valid_i),.s_ready_o(s_ready_o),.s_data_i(data),
      .m_valid_o(m_valid_o),.m_ready_i(m_ready_i),
      .m_data_o({m_depth_q16_o,m_gid_o,m_seq_o,m_payload_o,m_visible_o,m_numeric_overflow_o}));
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)sequence_q<='0;
      else if(frame_start_i)sequence_q<=(s_valid_i&&s_ready_o)?{{(SEQ_W-1){1'b0}},1'b1}:'0;
      else if(s_valid_i&&s_ready_o)sequence_q<=sequence_q+1'b1;
    end
endmodule
