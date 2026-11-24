// Expand one Gaussian-internal 8x8 block into one raster transaction per
// covered pixel. Coverage is clipped by both the Gaussian bbox [x0,x1)x[y0,y1)
// and the image bounds. This module creates no persistent tile list or bin.
module gaussian_block_pixel_expander #(
    parameter int unsigned META_W=128,
    parameter int unsigned TILE_W=12,
    parameter int unsigned PIXEL_W=16,
    parameter int unsigned SCREEN_W=27,
    parameter int unsigned LINEAR_W=32
) (
    input logic clk_i,input logic rst_ni,
    input logic s_valid_i,output logic s_ready_o,input logic[META_W-1:0]s_meta_i,
    input logic[TILE_W-1:0]s_block_x_i,s_block_y_i,
    input logic[PIXEL_W-1:0]s_bbox_x0_i,s_bbox_y0_i,s_bbox_x1_i,s_bbox_y1_i,
    input logic signed[SCREEN_W-1:0]s_mean_x_q8_i,s_mean_y_q8_i,
    input logic signed[5:0]s_coordinate_shift_i,
    input logic s_gaussian_first_block_i,s_gaussian_last_block_i,s_culled_i,
    input logic[PIXEL_W-1:0]cfg_image_width_i,cfg_image_height_i,
    output logic m_valid_o,input logic m_ready_i,output logic[META_W-1:0]m_meta_o,
    output logic[PIXEL_W-1:0]m_pixel_x_o,m_pixel_y_o,
    output logic[LINEAR_W-1:0]m_pixel_id_o,output logic[5:0]m_pixel_in_block_o,
    output logic signed[15:0]m_dx_q10_o,m_dy_q10_o,
    output logic m_first_pixel_o,m_last_pixel_o,
    output logic m_gaussian_first_block_o,m_gaussian_last_block_o,
    output logic empty_or_culled_pulse_o
);
    localparam int unsigned POS_W=PIXEL_W+1;
    logic active_q;logic[META_W-1:0]meta_q;
    logic[POS_W-1:0]x_q,y_q,x0_q,y0_q,x1_q,y1_q,base_x_q,base_y_q;
    logic[PIXEL_W-1:0]image_width_q;logic signed[SCREEN_W-1:0]mean_x_q,mean_y_q;
    logic signed[5:0]coordinate_shift_q;logic gaussian_first_q,gaussian_last_q;
    logic[POS_W-1:0]in_base_x,in_base_y,in_x0,in_y0,in_x1,in_y1,in_x1_bbox,in_y1_bbox;
    logic input_empty,output_fire;logic[2*PIXEL_W-1:0]linear_product;
    logic[POS_W-1:0]local_x,local_y;

    function automatic logic signed[15:0]encode_delta(
      input logic[POS_W-1:0]pixel,input logic signed[SCREEN_W-1:0]mean_q8,
      input logic signed[5:0]coordinate_shift);
      logic signed[63:0]pixel_wide,pixel_q8,mean_wide,delta_q8,scaled,magnitude,rounding;integer shift;begin
        // Extend before shifting so full 16-bit image coordinates retain Q8.
        pixel_wide=$signed({1'b0,pixel});pixel_q8=pixel_wide<<<8;
        mean_wide={{(64-SCREEN_W){mean_q8[SCREEN_W-1]}},mean_q8};
        delta_q8=pixel_q8-mean_wide;
        if(coordinate_shift>=0)begin shift=coordinate_shift;
          if(shift==0)scaled=delta_q8<<<2;
          else if(shift>=63)scaled='0;
          else begin magnitude=delta_q8<0?-delta_q8:delta_q8;rounding=64'sd1<<<(shift-1);
            magnitude=((magnitude<<<2)+rounding)>>>shift;scaled=delta_q8<0?-magnitude:magnitude;end
        end else if(coordinate_shift<=-6'sd30)
          scaled=delta_q8<0?-64'sh7fff_ffff_ffff_ffff:64'sh7fff_ffff_ffff_ffff;
        else scaled=delta_q8<<<(2-coordinate_shift);
        if(scaled>32767)encode_delta=16'sh7fff;
        else if(scaled< -32768)encode_delta=-16'sh8000;
        else encode_delta=scaled[15:0];
      end
    endfunction

    assign in_base_x={{(POS_W-TILE_W){1'b0}},s_block_x_i}<<3;
    assign in_base_y={{(POS_W-TILE_W){1'b0}},s_block_y_i}<<3;
    assign in_x0=in_base_x>{1'b0,s_bbox_x0_i}?in_base_x:{1'b0,s_bbox_x0_i};
    assign in_y0=in_base_y>{1'b0,s_bbox_y0_i}?in_base_y:{1'b0,s_bbox_y0_i};
    assign in_x1_bbox=(in_base_x+8)<{1'b0,s_bbox_x1_i}?(in_base_x+8):{1'b0,s_bbox_x1_i};
    assign in_y1_bbox=(in_base_y+8)<{1'b0,s_bbox_y1_i}?(in_base_y+8):{1'b0,s_bbox_y1_i};
    assign in_x1=in_x1_bbox>{1'b0,cfg_image_width_i}?{1'b0,cfg_image_width_i}:in_x1_bbox;
    assign in_y1=in_y1_bbox>{1'b0,cfg_image_height_i}?{1'b0,cfg_image_height_i}:in_y1_bbox;
    assign input_empty=s_culled_i||in_x0>=in_x1||in_y0>=in_y1;
    assign s_ready_o=!active_q;assign m_valid_o=active_q;assign output_fire=m_valid_o&&m_ready_i;
    assign m_meta_o=meta_q;assign m_pixel_x_o=x_q[PIXEL_W-1:0];assign m_pixel_y_o=y_q[PIXEL_W-1:0];
    assign linear_product=y_q[PIXEL_W-1:0]*image_width_q;
    assign m_pixel_id_o={{(LINEAR_W-PIXEL_W){1'b0}},x_q[PIXEL_W-1:0]}+linear_product;
    assign local_x=x_q-base_x_q;assign local_y=y_q-base_y_q;
    assign m_pixel_in_block_o={local_y[2:0],local_x[2:0]};
    assign m_dx_q10_o=encode_delta(x_q,mean_x_q,coordinate_shift_q);
    assign m_dy_q10_o=encode_delta(y_q,mean_y_q,coordinate_shift_q);
    assign m_first_pixel_o=active_q&&x_q==x0_q&&y_q==y0_q;
    assign m_last_pixel_o=active_q&&x_q==x1_q-1'b1&&y_q==y1_q-1'b1;
    assign m_gaussian_first_block_o=gaussian_first_q;assign m_gaussian_last_block_o=gaussian_last_q;
    always_ff @(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin active_q<=0;meta_q<='0;x_q<='0;y_q<='0;x0_q<='0;y0_q<='0;x1_q<='0;y1_q<='0;
        base_x_q<='0;base_y_q<='0;image_width_q<='0;mean_x_q<='0;mean_y_q<='0;coordinate_shift_q<='0;
        gaussian_first_q<=0;gaussian_last_q<=0;empty_or_culled_pulse_o<=0;end
      else begin empty_or_culled_pulse_o<=0;
        if(s_valid_i&&s_ready_o)begin
          if(input_empty)empty_or_culled_pulse_o<=1;
          else begin active_q<=1;meta_q<=s_meta_i;x_q<=in_x0;y_q<=in_y0;x0_q<=in_x0;y0_q<=in_y0;x1_q<=in_x1;y1_q<=in_y1;
            base_x_q<=in_base_x;base_y_q<=in_base_y;image_width_q<=cfg_image_width_i;
            mean_x_q<=s_mean_x_q8_i;mean_y_q<=s_mean_y_q8_i;coordinate_shift_q<=s_coordinate_shift_i;
            gaussian_first_q<=s_gaussian_first_block_i;gaussian_last_q<=s_gaussian_last_block_i;end
        end
        if(output_fire)begin
          if(m_last_pixel_o)active_q<=0;
          else if(x_q==x1_q-1'b1)begin x_q<=x0_q;y_q<=y_q+1'b1;end
          else x_q<=x_q+1'b1;
        end
      end
    end
`ifndef SYNTHESIS
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_valid_o&&!m_ready_i|=>m_valid_o&&
      $stable({m_meta_o,m_pixel_x_o,m_pixel_y_o,m_pixel_id_o,m_pixel_in_block_o,m_dx_q10_o,m_dy_q10_o,m_first_pixel_o,m_last_pixel_o}));
`endif
endmodule
