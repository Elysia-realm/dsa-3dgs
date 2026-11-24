// Phase-A direct-mapped write-through image-state cache with one physical
// miss-status holding register. The saved slot tag routes the eventual fill
// back to either entry of the ordered blend window.
module image_state_cache_backend_single #(
    parameter int unsigned PIXEL_W=32,parameter int unsigned EPOCH_W=16,
    parameter int unsigned ENTRIES=4096,parameter int unsigned TAG_W=1,
    parameter int unsigned INDEX_W=(ENTRIES<=1)?1:$clog2(ENTRIES)
) (
    input logic clk_i,input logic rst_ni,
    input logic query_valid_i,output logic query_ready_o,
    input logic[PIXEL_W-1:0]query_pixel_id_i,input logic[EPOCH_W-1:0]query_epoch_id_i,
    input logic[TAG_W-1:0]query_tag_i,
    output logic response_valid_o,input logic response_ready_i,
    output logic[TAG_W-1:0]response_tag_o,
    output logic[12:0]response_r_q12_o,response_g_q12_o,response_b_q12_o,
    output logic[15:0]response_t_q16_o,
    input logic update_valid_i,input logic[PIXEL_W-1:0]update_pixel_id_i,
    input logic[EPOCH_W-1:0]update_epoch_id_i,input logic[12:0]update_r_q12_i,
    input logic[12:0]update_g_q12_i,update_b_q12_i,input logic[15:0]update_t_q16_i,
    output logic miss_req_valid_o,input logic miss_req_ready_i,
    output logic[TAG_W-1:0]miss_req_tag_o,output logic[PIXEL_W-1:0]miss_req_pixel_id_o,
    input logic miss_rsp_valid_i,output logic miss_rsp_ready_o,
    input logic[TAG_W-1:0]miss_rsp_tag_i,input logic miss_rsp_error_i,
    input logic[127:0]miss_rsp_data_i,output logic error_sticky_o,output logic idle_o
);
    logic[PIXEL_W-1:0]tag_mem[0:ENTRIES-1],mshr_pixel_q;
    logic[EPOCH_W-1:0]epoch_mem[0:ENTRIES-1],mshr_epoch_q;
    logic[12:0]r_mem[0:ENTRIES-1],g_mem[0:ENTRIES-1],b_mem[0:ENTRIES-1];
    logic[15:0]t_mem[0:ENTRIES-1];logic valid_mem[0:ENTRIES-1];
    logic mshr_valid_q,mshr_issued_q;logic[TAG_W-1:0]mshr_tag_q;
    logic[INDEX_W-1:0]query_index,update_index,mshr_index;
    logic query_hit,response_space,query_fire,miss_rsp_fire;

    assign query_index=query_pixel_id_i[INDEX_W-1:0];
    assign update_index=update_pixel_id_i[INDEX_W-1:0];
    assign mshr_index=mshr_pixel_q[INDEX_W-1:0];
    assign query_hit=valid_mem[query_index]&&tag_mem[query_index]==query_pixel_id_i&&
      epoch_mem[query_index]==query_epoch_id_i;
    assign response_space=!response_valid_o||response_ready_i;
    assign miss_rsp_ready_o=mshr_valid_q&&mshr_issued_q&&miss_rsp_tag_i==mshr_tag_q&&response_space;
    assign miss_rsp_fire=miss_rsp_valid_i&&miss_rsp_ready_o;
    assign query_ready_o=query_hit?(response_space&&!miss_rsp_fire):!mshr_valid_q;
    assign query_fire=query_valid_i&&query_ready_o;
    assign miss_req_valid_o=mshr_valid_q&&!mshr_issued_q;
    assign miss_req_tag_o=mshr_tag_q;assign miss_req_pixel_id_o=mshr_pixel_q;
    assign idle_o=!mshr_valid_q&&!response_valid_o;

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        response_valid_o<=0;response_tag_o<='0;response_r_q12_o<=0;
        response_g_q12_o<=0;response_b_q12_o<=0;response_t_q16_o<=16'hffff;
        mshr_valid_q<=0;mshr_issued_q<=0;mshr_tag_q<=0;mshr_pixel_q<=0;mshr_epoch_q<=0;
        error_sticky_o<=0;
        for(int reset_index=0;reset_index<ENTRIES;reset_index=reset_index+1)
          valid_mem[reset_index]<=0;
      end else begin
        if(response_valid_o&&response_ready_i)response_valid_o<=0;
        if(query_fire)begin
          if(query_hit)begin
            response_valid_o<=1;response_tag_o<=query_tag_i;
            response_r_q12_o<=r_mem[query_index];response_g_q12_o<=g_mem[query_index];
            response_b_q12_o<=b_mem[query_index];response_t_q16_o<=t_mem[query_index];
          end else begin
            mshr_valid_q<=1;mshr_issued_q<=0;mshr_tag_q<=query_tag_i;
            mshr_pixel_q<=query_pixel_id_i;mshr_epoch_q<=query_epoch_id_i;
          end
        end
        if(miss_req_valid_o&&miss_req_ready_i)mshr_issued_q<=1;
        if(miss_rsp_fire)begin
          response_valid_o<=1;response_tag_o<=mshr_tag_q;
          if(miss_rsp_error_i)begin
            error_sticky_o<=1;response_r_q12_o<=0;response_g_q12_o<=0;
            response_b_q12_o<=0;response_t_q16_o<=16'hffff;
          end else if(miss_rsp_data_i[70:55]==mshr_epoch_q)begin
            response_r_q12_o<=miss_rsp_data_i[12:0];response_g_q12_o<=miss_rsp_data_i[25:13];
            response_b_q12_o<=miss_rsp_data_i[38:26];response_t_q16_o<=miss_rsp_data_i[54:39];
          end else begin
            response_r_q12_o<=0;response_g_q12_o<=0;response_b_q12_o<=0;response_t_q16_o<=16'hffff;
          end
          valid_mem[mshr_index]<=1;tag_mem[mshr_index]<=mshr_pixel_q;epoch_mem[mshr_index]<=mshr_epoch_q;
          if(!miss_rsp_error_i&&miss_rsp_data_i[70:55]==mshr_epoch_q)begin
            r_mem[mshr_index]<=miss_rsp_data_i[12:0];g_mem[mshr_index]<=miss_rsp_data_i[25:13];
            b_mem[mshr_index]<=miss_rsp_data_i[38:26];t_mem[mshr_index]<=miss_rsp_data_i[54:39];
          end else begin
            r_mem[mshr_index]<=0;g_mem[mshr_index]<=0;b_mem[mshr_index]<=0;t_mem[mshr_index]<=16'hffff;
          end
          mshr_valid_q<=0;mshr_issued_q<=0;
        end
        // Ordered architected update is newer than a same-cycle backing fill.
        if(update_valid_i)begin
          valid_mem[update_index]<=1;tag_mem[update_index]<=update_pixel_id_i;epoch_mem[update_index]<=update_epoch_id_i;
          r_mem[update_index]<=update_r_q12_i;g_mem[update_index]<=update_g_q12_i;
          b_mem[update_index]<=update_b_q12_i;t_mem[update_index]<=update_t_q16_i;
        end
      end
    end
`ifndef SYNTHESIS
    initial begin assert(ENTRIES>0&&(ENTRIES&(ENTRIES-1))==0);assert(PIXEL_W>=INDEX_W);assert(TAG_W==1);end
    assert property(@(posedge clk_i)disable iff(!rst_ni)response_valid_o&&!response_ready_i
      |=>response_valid_o&&$stable({response_tag_o,response_r_q12_o,response_g_q12_o,
      response_b_q12_o,response_t_q16_o}));
    assert property(@(posedge clk_i)disable iff(!rst_ni)mshr_valid_q&&query_valid_i&&!query_hit
      |->!query_ready_o);
`endif
endmodule
