// Four-entry experimental ordered image-state transaction window. State
// lookups and one shared blend core may complete out of order, while only the
// ring head may update architected pixel state and retire.
module blend_state_commit_4 #(
    parameter int unsigned META_W=104,parameter int unsigned PIXEL_W=12,
    parameter int unsigned EPOCH_W=16,
    parameter bit ENABLE_RESPONSE_BLEND_BYPASS=1'b0,
    parameter bit ENABLE_BLEND_COMMIT_BYPASS=1'b0,
    parameter bit USE_SHARED_RASTER_PE=1'b0
) (
    input logic clk_i,input logic rst_ni,
    input logic s_valid_i,output logic s_ready_o,input logic[META_W-1:0]s_meta_i,
    input logic[PIXEL_W-1:0]s_pixel_id_i,input logic[EPOCH_W-1:0]s_epoch_id_i,
    input logic[12:0]s_color_r_q12_i,s_color_g_q12_i,s_color_b_q12_i,s_alpha_q12_i,
    output logic m_valid_o,input logic m_ready_i,output logic[META_W-1:0]m_meta_o,
    output logic[PIXEL_W-1:0]m_pixel_id_o,output logic[EPOCH_W-1:0]m_epoch_id_o,
    output logic[12:0]m_r_q12_o,m_g_q12_o,m_b_q12_o,output logic[15:0]m_t_q16_o,
    output logic m_newly_terminated_o,output logic[2:0]occupancy_o,
    output logic state_query_valid_o,input logic state_query_ready_i,
    output logic[PIXEL_W-1:0]state_query_pixel_id_o,
    output logic[EPOCH_W-1:0]state_query_epoch_id_o,output logic[1:0]state_query_tag_o,
    input logic state_response_valid_i,output logic state_response_ready_o,
    input logic[1:0]state_response_tag_i,input logic[12:0]state_response_r_q12_i,
    input logic[12:0]state_response_g_q12_i,state_response_b_q12_i,
    input logic[15:0]state_response_t_q16_i,
    output logic state_update_valid_o,output logic[PIXEL_W-1:0]state_update_pixel_id_o,
    output logic[EPOCH_W-1:0]state_update_epoch_id_o,
    output logic[12:0]state_update_r_q12_o,state_update_g_q12_o,state_update_b_q12_o,
    output logic[15:0]state_update_t_q16_o,
    output logic r_pe_req_valid_o,input logic r_pe_req_ready_i,
    output logic signed[31:0]r_pe_lhs_o,r_pe_rhs_o,
    input logic r_pe_rsp_valid_i,output logic r_pe_rsp_ready_o,
    input logic signed[64:0]r_pe_result_i
);
    typedef enum logic[2:0]{EMPTY,NEED_QUERY,WAIT_RESPONSE,NEED_BLEND,WAIT_BLEND,DONE}slot_state_t;
    slot_state_t slot_state_q[0:3];
    logic[1:0]head_q,tail_q;logic[2:0]count_q;
    logic[META_W-1:0]meta_q[0:3];logic[PIXEL_W-1:0]pixel_q[0:3];
    logic[EPOCH_W-1:0]epoch_q[0:3];logic[12:0]color_r_q[0:3],color_g_q[0:3],color_b_q[0:3],alpha_q[0:3];
    logic[12:0]old_r_q[0:3],old_g_q[0:3],old_b_q[0:3];logic[15:0]old_t_q[0:3];
    logic[12:0]new_r_q[0:3],new_g_q[0:3],new_b_q[0:3];logic[15:0]new_t_q[0:3];
    logic newly_terminated_q[0:3];
    logic[META_W-1:0]last_meta_q;logic[PIXEL_W-1:0]last_pixel_q;logic[EPOCH_W-1:0]last_epoch_q;
    logic[12:0]last_r_q,last_g_q,last_b_q;logic[15:0]last_t_q;logic last_newly_terminated_q;
    logic alloc_fire,commit_fire,query_fire,response_fire,blend_fire,response_bypass_fire;
    logic blend_commit_bypass_candidate,blend_commit_bypass_fire,stored_head_done;
    logic[1:0]query_slot,blend_slot,blend_input_slot,blend_out_tag;logic query_found,blend_found;
    logic blend_in_valid,blend_in_ready,blend_out_valid,blend_out_ready,response_bypass_candidate;
    logic[12:0]blend_old_r,blend_old_g,blend_old_b;logic[15:0]blend_old_t;
    logic[META_W-1:0]blend_out_meta;logic[12:0]blend_new_r,blend_new_g,blend_new_b;
    logic[15:0]blend_new_t;logic blend_newly_terminated;

    assign occupancy_o=count_q;
    assign stored_head_done=count_q!=0&&slot_state_q[head_q]==DONE;
    // The blend result is already registered by blend_fixed_core.  If it is
    // the ring head, expose that registered payload directly to ordered
    // commit instead of first copying it into the slot and waiting one more
    // cycle.  A stalled downstream still causes the result to be captured in
    // the slot, preserving the original decoupling and stable-output contract.
    assign blend_commit_bypass_candidate=ENABLE_BLEND_COMMIT_BYPASS&&count_q!=0&&
      blend_out_valid&&blend_out_tag==head_q&&slot_state_q[head_q]==WAIT_BLEND;
    assign m_valid_o=stored_head_done||blend_commit_bypass_candidate;
    assign m_meta_o=blend_commit_bypass_candidate?blend_out_meta:
      (stored_head_done?meta_q[head_q]:last_meta_q);
    assign m_pixel_id_o=m_valid_o?pixel_q[head_q]:last_pixel_q;
    assign m_epoch_id_o=m_valid_o?epoch_q[head_q]:last_epoch_q;
    assign m_r_q12_o=blend_commit_bypass_candidate?blend_new_r:
      (stored_head_done?new_r_q[head_q]:last_r_q);
    assign m_g_q12_o=blend_commit_bypass_candidate?blend_new_g:
      (stored_head_done?new_g_q[head_q]:last_g_q);
    assign m_b_q12_o=blend_commit_bypass_candidate?blend_new_b:
      (stored_head_done?new_b_q[head_q]:last_b_q);
    assign m_t_q16_o=blend_commit_bypass_candidate?blend_new_t:
      (stored_head_done?new_t_q[head_q]:last_t_q);
    assign m_newly_terminated_o=blend_commit_bypass_candidate?blend_newly_terminated:
      (stored_head_done?newly_terminated_q[head_q]:last_newly_terminated_q);
    assign commit_fire=m_valid_o&&m_ready_i;
    assign blend_commit_bypass_fire=blend_commit_bypass_candidate&&m_ready_i;
    assign s_ready_o=count_q<4||(commit_fire&&count_q==4);
    assign alloc_fire=s_valid_i&&s_ready_o;

    // Oldest query candidate without a complete-key hazard against any older
    // live slot wins. Ring arithmetic naturally wraps in two bits.
    always_comb begin
      query_found=0;query_slot=head_q;
      for(int off=0;off<4;off++)begin
        logic[1:0]candidate,older;logic hazard;
        candidate=head_q+2'(off);older=head_q;hazard=0;
        if(off<count_q&&slot_state_q[candidate]==NEED_QUERY)begin
          for(int prior=0;prior<4;prior++)begin
            older=head_q+2'(prior);
            if(prior<off&&prior<count_q&&
               {epoch_q[older],pixel_q[older]}=={epoch_q[candidate],pixel_q[candidate]})hazard=1;
          end
          if(!query_found&&!hazard)begin query_found=1;query_slot=candidate;end
        end
      end
    end
    assign state_query_valid_o=query_found;assign state_query_tag_o=query_slot;
    assign state_query_pixel_id_o=pixel_q[query_slot];assign state_query_epoch_id_o=epoch_q[query_slot];
    assign query_fire=state_query_valid_o&&state_query_ready_i;
    assign state_response_ready_o=slot_state_q[state_response_tag_i]==WAIT_RESPONSE;
    assign response_fire=state_response_valid_i&&state_response_ready_o;

    always_comb begin
      blend_found=0;blend_slot=head_q;
      for(int off=0;off<4;off++)begin
        logic[1:0]candidate;candidate=head_q+2'(off);
        if(!blend_found&&off<count_q&&slot_state_q[candidate]==NEED_BLEND)begin
          blend_found=1;blend_slot=candidate;
        end
      end
    end
    // A newly returned state may enter the existing shared blend core in the
    // same cycle. Older NEED_BLEND work retains priority; when the core cannot
    // accept, the response is still captured in its slot exactly as before.
    // Thus the bypass removes only an avoidable hand-off bubble and never adds
    // an arithmetic unit, state port, MSHR, or response-side backpressure.
    assign response_bypass_candidate=ENABLE_RESPONSE_BLEND_BYPASS&&!blend_found&&
      state_response_valid_i&&state_response_ready_o;
    assign blend_input_slot=blend_found?blend_slot:state_response_tag_i;
    assign blend_in_valid=blend_found||response_bypass_candidate;
    assign blend_fire=blend_in_valid&&blend_in_ready;
    assign response_bypass_fire=response_bypass_candidate&&blend_in_ready;
    assign blend_old_r=response_bypass_candidate?state_response_r_q12_i:old_r_q[blend_slot];
    assign blend_old_g=response_bypass_candidate?state_response_g_q12_i:old_g_q[blend_slot];
    assign blend_old_b=response_bypass_candidate?state_response_b_q12_i:old_b_q[blend_slot];
    assign blend_old_t=response_bypass_candidate?state_response_t_q16_i:old_t_q[blend_slot];
    assign blend_out_ready=slot_state_q[blend_out_tag]==WAIT_BLEND;
    blend_fixed_core #(.META_W(META_W+2),.USE_SHARED_RASTER_PE(USE_SHARED_RASTER_PE))u_blend(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(blend_in_valid),.s_ready_o(blend_in_ready),
      .s_meta_i({blend_input_slot,meta_q[blend_input_slot]}),.s_old_r_q12_i(blend_old_r),
      .s_old_g_q12_i(blend_old_g),.s_old_b_q12_i(blend_old_b),
      .s_old_t_q16_i(blend_old_t),.s_color_r_q12_i(color_r_q[blend_input_slot]),
      .s_color_g_q12_i(color_g_q[blend_input_slot]),.s_color_b_q12_i(color_b_q[blend_input_slot]),
      .s_alpha_q12_i(alpha_q[blend_input_slot]),.m_valid_o(blend_out_valid),.m_ready_i(blend_out_ready),
      .m_meta_o({blend_out_tag,blend_out_meta}),.m_new_r_q12_o(blend_new_r),
      .m_new_g_q12_o(blend_new_g),.m_new_b_q12_o(blend_new_b),.m_new_t_q16_o(blend_new_t),
      .m_newly_terminated_o(blend_newly_terminated),
      .r_pe_req_valid_o(r_pe_req_valid_o),.r_pe_req_ready_i(r_pe_req_ready_i),
      .r_pe_lhs_o(r_pe_lhs_o),.r_pe_rhs_o(r_pe_rhs_o),
      .r_pe_rsp_valid_i(r_pe_rsp_valid_i),.r_pe_rsp_ready_o(r_pe_rsp_ready_o),.r_pe_result_i(r_pe_result_i));
    assign state_update_valid_o=commit_fire;assign state_update_pixel_id_o=pixel_q[head_q];
    assign state_update_epoch_id_o=epoch_q[head_q];assign state_update_r_q12_o=m_r_q12_o;
    assign state_update_g_q12_o=m_g_q12_o;assign state_update_b_q12_o=m_b_q12_o;
    assign state_update_t_q16_o=m_t_q16_o;

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        head_q<=0;tail_q<=0;count_q<=0;last_meta_q<=0;last_pixel_q<=0;last_epoch_q<=0;
        last_r_q<=0;last_g_q<=0;last_b_q<=0;last_t_q<=16'hffff;last_newly_terminated_q<=0;
        for(int reset_index=0;reset_index<4;reset_index++)slot_state_q[reset_index]<=EMPTY;
      end else begin
        if(query_fire)slot_state_q[query_slot]<=WAIT_RESPONSE;
        if(response_fire)begin
          if(response_bypass_fire)slot_state_q[state_response_tag_i]<=WAIT_BLEND;
          else begin
            // The bypass consumes response state directly, so these 55 state
            // bits need not toggle on its common fast path.
            old_r_q[state_response_tag_i]<=state_response_r_q12_i;
            old_g_q[state_response_tag_i]<=state_response_g_q12_i;
            old_b_q[state_response_tag_i]<=state_response_b_q12_i;
            old_t_q[state_response_tag_i]<=state_response_t_q16_i;
            slot_state_q[state_response_tag_i]<=NEED_BLEND;
          end
        end
        if(blend_fire)slot_state_q[blend_input_slot]<=WAIT_BLEND;
        if(blend_out_valid&&blend_out_ready)begin
          new_r_q[blend_out_tag]<=blend_new_r;new_g_q[blend_out_tag]<=blend_new_g;
          new_b_q[blend_out_tag]<=blend_new_b;new_t_q[blend_out_tag]<=blend_new_t;
          newly_terminated_q[blend_out_tag]<=blend_newly_terminated;slot_state_q[blend_out_tag]<=DONE;
        end
        if(commit_fire)begin
          last_meta_q<=m_meta_o;last_pixel_q<=m_pixel_id_o;last_epoch_q<=m_epoch_id_o;
          last_r_q<=m_r_q12_o;last_g_q<=m_g_q12_o;last_b_q<=m_b_q12_o;
          last_t_q<=m_t_q16_o;last_newly_terminated_q<=m_newly_terminated_o;
          slot_state_q[head_q]<=EMPTY;head_q<=head_q+1'b1;
        end
        if(alloc_fire)begin
          meta_q[tail_q]<=s_meta_i;pixel_q[tail_q]<=s_pixel_id_i;epoch_q[tail_q]<=s_epoch_id_i;
          color_r_q[tail_q]<=s_color_r_q12_i;color_g_q[tail_q]<=s_color_g_q12_i;
          color_b_q[tail_q]<=s_color_b_q12_i;alpha_q[tail_q]<=s_alpha_q12_i;
          slot_state_q[tail_q]<=NEED_QUERY;tail_q<=tail_q+1'b1;
        end
        case({alloc_fire,commit_fire})
          2'b10:count_q<=count_q+1'b1;2'b01:count_q<=count_q-1'b1;default:count_q<=count_q;
        endcase
      end
    end
`ifndef SYNTHESIS
    assert property(@(posedge clk_i)disable iff(!rst_ni)count_q<=4);
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_valid_o&&!m_ready_i
      |=>m_valid_o&&$stable({m_meta_o,m_pixel_id_o,m_epoch_id_o,m_r_q12_o,m_g_q12_o,
      m_b_q12_o,m_t_q16_o,m_newly_terminated_o}));
    assert property(@(posedge clk_i)disable iff(!rst_ni)state_update_valid_o|->m_valid_o&&m_ready_i);
    assert property(@(posedge clk_i)disable iff(!rst_ni)response_bypass_fire|->response_fire&&!blend_found);
    assert property(@(posedge clk_i)disable iff(!rst_ni)blend_found&&response_fire&&blend_in_ready
      |->blend_input_slot==blend_slot&&!response_bypass_fire);
    assert property(@(posedge clk_i)disable iff(!rst_ni)blend_commit_bypass_fire
      |->commit_fire&&blend_out_valid&&blend_out_ready&&blend_out_tag==head_q);
    assert property(@(posedge clk_i)disable iff(!rst_ni)blend_commit_bypass_candidate&&!m_ready_i
      |=>stored_head_done);
`endif
endmodule
