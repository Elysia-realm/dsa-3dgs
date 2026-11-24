// T01 synthesis abstraction for the image-state cache boundary.
//
// The production implementation mixes cache control with inferred arrays that
// Yosys expands to registers.  T01 excludes this whole boundary from standard
// cell area and reports its storage separately.  T11 must split/map the arrays
// and restore the cache-control area before final PPA sign-off.
(* blackbox *)
module image_state_cache_backend #(
    parameter int unsigned PIXEL_W=32,parameter int unsigned EPOCH_W=16,
    parameter int unsigned ENTRIES=4096,parameter int unsigned TAG_W=1,
    parameter int unsigned ACTIVE_MSHRS=2,
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
endmodule
