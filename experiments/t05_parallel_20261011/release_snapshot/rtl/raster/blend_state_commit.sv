// Two-entry ordered image-state transaction window. Different pixel keys may
// overlap state lookup and blend work, but only the oldest slot may commit.
// Equal {epoch,pixel} keys are held until the older slot retires, preserving
// exact front-to-back read-after-write semantics.
module blend_state_commit #(
    parameter int unsigned META_W=104,parameter int unsigned PIXEL_W=12,
    parameter int unsigned EPOCH_W=16,parameter int unsigned STATE_ENTRIES=4096,
    parameter bit USE_EXTERNAL_STATE_BACKEND=1'b0,
    parameter bit USE_SHARED_RASTER_PE=1'b0
) (
    input logic clk_i,input logic rst_ni,
    input logic enable_two_entries_i,
    input logic s_valid_i,output logic s_ready_o,input logic[META_W-1:0]s_meta_i,
    input logic[PIXEL_W-1:0]s_pixel_id_i,input logic[EPOCH_W-1:0]s_epoch_id_i,
    input logic[12:0]s_color_r_q12_i,s_color_g_q12_i,s_color_b_q12_i,s_alpha_q12_i,
    output logic m_valid_o,input logic m_ready_i,output logic[META_W-1:0]m_meta_o,
    output logic[PIXEL_W-1:0]m_pixel_id_o,output logic[EPOCH_W-1:0]m_epoch_id_o,
    output logic[12:0]m_r_q12_o,m_g_q12_o,m_b_q12_o,output logic[15:0]m_t_q16_o,
    output logic m_newly_terminated_o,output logic[1:0]occupancy_o,
    output logic state_query_valid_o,input logic state_query_ready_i,
    output logic[PIXEL_W-1:0]state_query_pixel_id_o,
    output logic[EPOCH_W-1:0]state_query_epoch_id_o,output logic state_query_tag_o,
    input logic state_response_valid_i,output logic state_response_ready_o,
    input logic state_response_tag_i,input logic[12:0]state_response_r_q12_i,
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
    slot_state_t slot_state_q[0:1];
    logic head_q,tail_q;logic[1:0]count_q;
    logic[META_W-1:0]meta_q[0:1];logic[PIXEL_W-1:0]pixel_q[0:1];
    logic[EPOCH_W-1:0]epoch_q[0:1];
    logic[12:0]color_r_q[0:1],color_g_q[0:1],color_b_q[0:1],alpha_q[0:1];
    logic[12:0]old_r_q[0:1],old_g_q[0:1],old_b_q[0:1];logic[15:0]old_t_q[0:1];
    logic[12:0]new_r_q[0:1],new_g_q[0:1],new_b_q[0:1];logic[15:0]new_t_q[0:1];
    logic newly_terminated_q[0:1];
    logic[META_W-1:0]last_meta_q;logic[PIXEL_W-1:0]last_pixel_q;
    logic[EPOCH_W-1:0]last_epoch_q;logic[12:0]last_r_q,last_g_q,last_b_q;
    logic[15:0]last_t_q;logic last_newly_terminated_q;
    logic alloc_fire,commit_fire,query_slot,query_fire,response_fire,blend_slot,blend_fire;
    logic older_key_hazard;
    logic local_query_ready,local_response_valid,local_response_ready,local_query_tag_q;
    logic[12:0]local_old_r,local_old_g,local_old_b;logic[15:0]local_old_t;
    logic response_valid,response_ready,response_tag;logic[12:0]response_r,response_g,response_b;
    logic[15:0]response_t;
    logic blend_in_valid,blend_in_ready,blend_out_valid,blend_out_ready,blend_out_tag;
    logic[META_W-1:0]blend_out_meta;logic[12:0]blend_new_r,blend_new_g,blend_new_b;
    logic[15:0]blend_new_t;logic blend_newly_terminated;

    assign occupancy_o=count_q;
    assign m_valid_o=count_q!=0&&slot_state_q[head_q]==DONE;
    // Preserve the last accepted commit packet while valid is low. Downstream
    // must ignore data without valid, but retaining it keeps debug/APB-visible
    // behavior deterministic and avoids exposing an unrelated free slot.
    assign m_meta_o=m_valid_o?meta_q[head_q]:last_meta_q;
    assign m_pixel_id_o=m_valid_o?pixel_q[head_q]:last_pixel_q;
    assign m_epoch_id_o=m_valid_o?epoch_q[head_q]:last_epoch_q;
    assign m_r_q12_o=m_valid_o?new_r_q[head_q]:last_r_q;
    assign m_g_q12_o=m_valid_o?new_g_q[head_q]:last_g_q;
    assign m_b_q12_o=m_valid_o?new_b_q[head_q]:last_b_q;
    assign m_t_q16_o=m_valid_o?new_t_q[head_q]:last_t_q;
    assign m_newly_terminated_o=m_valid_o?newly_terminated_q[head_q]:last_newly_terminated_q;
    assign commit_fire=m_valid_o&&m_ready_i;
    assign s_ready_o=(count_q<(enable_two_entries_i?2:1))||
      (commit_fire&&count_q==(enable_two_entries_i?2:1));
    assign alloc_fire=s_valid_i&&s_ready_o;

    // Oldest query-ready slot wins. The younger slot may issue only when its
    // complete key differs from the still-live older slot.
    always_comb begin
      query_slot=head_q;state_query_valid_o=0;
      if(count_q!=0&&slot_state_q[head_q]==NEED_QUERY)begin
        query_slot=head_q;state_query_valid_o=1;
      end else if(count_q==2&&slot_state_q[~head_q]==NEED_QUERY)begin
        query_slot=~head_q;
        if({epoch_q[~head_q],pixel_q[~head_q]}!={epoch_q[head_q],pixel_q[head_q]})
          state_query_valid_o=1;
      end
    end
    assign state_query_pixel_id_o=pixel_q[query_slot];
    assign state_query_epoch_id_o=epoch_q[query_slot];assign state_query_tag_o=query_slot;
    assign query_fire=state_query_valid_o&&(USE_EXTERNAL_STATE_BACKEND?state_query_ready_i:local_query_ready);

    generate if(USE_EXTERNAL_STATE_BACKEND)begin:g_external_state
      assign response_valid=state_response_valid_i;assign state_response_ready_o=response_ready;
      assign response_tag=state_response_tag_i;assign response_r=state_response_r_q12_i;
      assign response_g=state_response_g_q12_i;assign response_b=state_response_b_q12_i;
      assign response_t=state_response_t_q16_i;
      assign local_query_ready=0;assign local_response_ready=0;
    end else begin:g_local_state
      image_state_store #(.PIXEL_W(PIXEL_W),.EPOCH_W(EPOCH_W),.ENTRIES(STATE_ENTRIES))u_state_store(
        .clk_i(clk_i),.rst_ni(rst_ni),.query_valid_i(state_query_valid_o),.query_ready_o(local_query_ready),
        .query_pixel_id_i(state_query_pixel_id_o),.query_epoch_id_i(state_query_epoch_id_o),
        .response_valid_o(local_response_valid),.response_ready_i(local_response_ready),
        .response_r_q12_o(local_old_r),.response_g_q12_o(local_old_g),
        .response_b_q12_o(local_old_b),.response_t_q16_o(local_old_t),
        .update_valid_i(commit_fire),.update_pixel_id_i(pixel_q[head_q]),.update_epoch_id_i(epoch_q[head_q]),
        .update_r_q12_i(new_r_q[head_q]),.update_g_q12_i(new_g_q[head_q]),
        .update_b_q12_i(new_b_q[head_q]),.update_t_q16_i(new_t_q[head_q]));
      assign response_valid=local_response_valid;assign local_response_ready=response_ready;
      assign response_tag=local_query_tag_q;assign response_r=local_old_r;assign response_g=local_old_g;
      assign response_b=local_old_b;assign response_t=local_old_t;assign state_response_ready_o=0;
    end endgenerate
    assign response_ready=slot_state_q[response_tag]==WAIT_RESPONSE;
    assign response_fire=response_valid&&response_ready;

    always_comb begin
      blend_slot=head_q;blend_in_valid=0;
      if(count_q!=0&&slot_state_q[head_q]==NEED_BLEND)begin blend_slot=head_q;blend_in_valid=1;end
      else if(count_q==2&&slot_state_q[~head_q]==NEED_BLEND)begin blend_slot=~head_q;blend_in_valid=1;end
    end
    assign blend_fire=blend_in_valid&&blend_in_ready;
    assign blend_out_ready=slot_state_q[blend_out_tag]==WAIT_BLEND;
    blend_fixed_core #(.META_W(META_W+1),.USE_SHARED_RASTER_PE(USE_SHARED_RASTER_PE))u_blend(
      .clk_i(clk_i),.rst_ni(rst_ni),.s_valid_i(blend_in_valid),.s_ready_o(blend_in_ready),
      .s_meta_i({blend_slot,meta_q[blend_slot]}),.s_old_r_q12_i(old_r_q[blend_slot]),
      .s_old_g_q12_i(old_g_q[blend_slot]),.s_old_b_q12_i(old_b_q[blend_slot]),
      .s_old_t_q16_i(old_t_q[blend_slot]),.s_color_r_q12_i(color_r_q[blend_slot]),
      .s_color_g_q12_i(color_g_q[blend_slot]),.s_color_b_q12_i(color_b_q[blend_slot]),
      .s_alpha_q12_i(alpha_q[blend_slot]),.m_valid_o(blend_out_valid),.m_ready_i(blend_out_ready),
      .m_meta_o({blend_out_tag,blend_out_meta}),.m_new_r_q12_o(blend_new_r),
      .m_new_g_q12_o(blend_new_g),.m_new_b_q12_o(blend_new_b),.m_new_t_q16_o(blend_new_t),
      .m_newly_terminated_o(blend_newly_terminated),
      .r_pe_req_valid_o(r_pe_req_valid_o),.r_pe_req_ready_i(r_pe_req_ready_i),
      .r_pe_lhs_o(r_pe_lhs_o),.r_pe_rhs_o(r_pe_rhs_o),
      .r_pe_rsp_valid_i(r_pe_rsp_valid_i),.r_pe_rsp_ready_o(r_pe_rsp_ready_o),.r_pe_result_i(r_pe_result_i));

    assign state_update_valid_o=commit_fire;assign state_update_pixel_id_o=pixel_q[head_q];
    assign state_update_epoch_id_o=epoch_q[head_q];assign state_update_r_q12_o=new_r_q[head_q];
    assign state_update_g_q12_o=new_g_q[head_q];assign state_update_b_q12_o=new_b_q[head_q];
    assign state_update_t_q16_o=new_t_q[head_q];

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        head_q<=0;tail_q<=0;count_q<=0;slot_state_q[0]<=EMPTY;slot_state_q[1]<=EMPTY;
        local_query_tag_q<=0;
        last_meta_q<='0;last_pixel_q<='0;last_epoch_q<='0;last_r_q<=0;last_g_q<=0;
        last_b_q<=0;last_t_q<=16'hffff;last_newly_terminated_q<=0;
      end else begin
        if(query_fire)begin slot_state_q[query_slot]<=WAIT_RESPONSE;local_query_tag_q<=query_slot;end
        if(response_fire)begin
          old_r_q[response_tag]<=response_r;old_g_q[response_tag]<=response_g;
          old_b_q[response_tag]<=response_b;old_t_q[response_tag]<=response_t;
          slot_state_q[response_tag]<=NEED_BLEND;
        end
        if(blend_fire)slot_state_q[blend_slot]<=WAIT_BLEND;
        if(blend_out_valid&&blend_out_ready)begin
          new_r_q[blend_out_tag]<=blend_new_r;new_g_q[blend_out_tag]<=blend_new_g;
          new_b_q[blend_out_tag]<=blend_new_b;new_t_q[blend_out_tag]<=blend_new_t;
          newly_terminated_q[blend_out_tag]<=blend_newly_terminated;
          slot_state_q[blend_out_tag]<=DONE;
        end
        if(commit_fire)begin
          last_meta_q<=meta_q[head_q];last_pixel_q<=pixel_q[head_q];last_epoch_q<=epoch_q[head_q];
          last_r_q<=new_r_q[head_q];last_g_q<=new_g_q[head_q];last_b_q<=new_b_q[head_q];
          last_t_q<=new_t_q[head_q];last_newly_terminated_q<=newly_terminated_q[head_q];
          slot_state_q[head_q]<=EMPTY;head_q<=~head_q;
        end
        if(alloc_fire)begin
          meta_q[tail_q]<=s_meta_i;pixel_q[tail_q]<=s_pixel_id_i;epoch_q[tail_q]<=s_epoch_id_i;
          color_r_q[tail_q]<=s_color_r_q12_i;color_g_q[tail_q]<=s_color_g_q12_i;
          color_b_q[tail_q]<=s_color_b_q12_i;alpha_q[tail_q]<=s_alpha_q12_i;
          slot_state_q[tail_q]<=NEED_QUERY;tail_q<=~tail_q;
        end
        case({alloc_fire,commit_fire})
          2'b10:count_q<=count_q+1'b1;
          2'b01:count_q<=count_q-1'b1;
          default:count_q<=count_q;
        endcase
      end
    end
`ifndef SYNTHESIS
    assert property(@(posedge clk_i)disable iff(!rst_ni)count_q<=2);
    assert property(@(posedge clk_i)disable iff(!rst_ni)!enable_two_entries_i|->count_q<=1);
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_valid_o&&!m_ready_i
      |=>m_valid_o&&$stable({m_meta_o,m_pixel_id_o,m_epoch_id_o,m_r_q12_o,m_g_q12_o,
      m_b_q12_o,m_t_q16_o,m_newly_terminated_o}));
    assert property(@(posedge clk_i)disable iff(!rst_ni)state_query_valid_o&&count_q==2&&query_slot!=head_q
      |-> {epoch_q[query_slot],pixel_q[query_slot]}!={epoch_q[head_q],pixel_q[head_q]});
    assert property(@(posedge clk_i)disable iff(!rst_ni)state_update_valid_o|->m_valid_o&&m_ready_i);
`endif
endmodule
