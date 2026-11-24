// Conservative one-axis lower-bound test.  The omitted axis0 square is
// non-negative, so passing this test proves the complete block is below the
// alpha threshold; failing the test simply preserves the normal pixel path.
module gaussian_shape_block_reject #(
    parameter int unsigned TILE_W=12,parameter int unsigned PIXEL_W=16,parameter int unsigned SCREEN_W=27
) (
    input logic[TILE_W-1:0]block_x_i,block_y_i,
    input logic[PIXEL_W-1:0]bbox_x0_i,bbox_x1_i,bbox_y0_i,bbox_y1_i,
    input logic[PIXEL_W-1:0]image_width_i,image_height_i,
    input logic signed[SCREEN_W-1:0]mean_y_q8_i,
    input logic signed[5:0]coordinate_shift_i,factor_shift_i,
    input logic[14:0]l11_q12_i,input logic[12:0]opacity_q12_i,
    output logic reject_o
);
    localparam int unsigned POS_W=PIXEL_W+1;
    logic[POS_W-1:0]base_x,base_y,x0,x1_bbox,x1,y0,y1_bbox,y1;
    logic signed[63:0]y0_q8,y_last_q8,mean_wide;
    logic[POS_W-1:0]closest_y;logic signed[15:0]min_dy;
    logic signed[31:0]axis_product;logic signed[6:0]result_shift;
    logic signed[14:0]min_axis;logic[14:0]axis_magnitude,axis_threshold;

    function automatic logic signed[15:0]encode_delta(
      input logic[POS_W-1:0]pixel,input logic signed[SCREEN_W-1:0]mean_q8,
      input logic signed[5:0]coordinate_shift);
      logic signed[63:0]pixel_wide,pixel_q8,mean_ext,delta_q8,scaled,magnitude,rounding;integer shift;begin
        pixel_wide=$signed({1'b0,pixel});pixel_q8=pixel_wide<<<8;
        mean_ext={{(64-SCREEN_W){mean_q8[SCREEN_W-1]}},mean_q8};delta_q8=pixel_q8-mean_ext;
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

    function automatic logic signed[14:0]scale_axis(
      input logic signed[31:0]value,input logic signed[6:0]shift);
      logic signed[63:0]extended,shifted,rounding;integer right_shift;begin
        extended={{32{value[31]}},value};
        if(shift>=7'sd12)begin
          if((shift-7'sd12)>=7'sd31)shifted=value[31]?-64'sd16384:64'sd16383;
          else shifted=extended<<<(shift-7'sd12);
        end else begin right_shift=12-shift;
          if(right_shift>=63)shifted='0;
          else if(right_shift==0)shifted=extended;
          else begin rounding=64'sd1<<<(right_shift-1);
            shifted=extended>=0?(extended+rounding)>>>right_shift:
              -(((-extended)+rounding)>>>right_shift);end
        end
        if(shifted>16383)scale_axis=15'sd16383;
        else if(shifted< -16384)scale_axis=-15'sd16384;
        else scale_axis=shifted[14:0];
      end
    endfunction

    assign base_x={{(POS_W-TILE_W){1'b0}},block_x_i}<<3;
    assign base_y={{(POS_W-TILE_W){1'b0}},block_y_i}<<3;
    assign x0=base_x>{1'b0,bbox_x0_i}?base_x:{1'b0,bbox_x0_i};
    assign x1_bbox=(base_x+8)<{1'b0,bbox_x1_i}?(base_x+8):{1'b0,bbox_x1_i};
    assign x1=x1_bbox>{1'b0,image_width_i}?{1'b0,image_width_i}:x1_bbox;
    assign y0=base_y>{1'b0,bbox_y0_i}?base_y:{1'b0,bbox_y0_i};
    assign y1_bbox=(base_y+8)<{1'b0,bbox_y1_i}?(base_y+8):{1'b0,bbox_y1_i};
    assign y1=y1_bbox>{1'b0,image_height_i}?{1'b0,image_height_i}:y1_bbox;
    assign y0_q8=$signed({{(64-POS_W){1'b0}},y0})<<<8;
    assign y_last_q8=$signed({{(64-POS_W){1'b0}},(y1-1'b1)})<<<8;
    assign mean_wide={{(64-SCREEN_W){mean_y_q8_i[SCREEN_W-1]}},mean_y_q8_i};
    assign closest_y=mean_wide<y0_q8?y0:(y1-1'b1);
    assign min_dy=(mean_wide>=y0_q8&&mean_wide<=y_last_q8)?'0:
      encode_delta(closest_y,mean_y_q8_i,coordinate_shift_i);
    assign axis_product=$signed(min_dy)*$signed({1'b0,l11_q12_i});
    assign result_shift=$signed(coordinate_shift_i)+$signed(factor_shift_i);
    assign min_axis=scale_axis(axis_product,result_shift);
    assign axis_magnitude=min_axis<0?-min_axis:min_axis;
    assign axis_threshold=opacity_q12_i<=13'd512 ? 15'd2703 :
      opacity_q12_i<=13'd1024 ? 15'd2959 : opacity_q12_i<=13'd2048 ? 15'd3214 :
      opacity_q12_i<=13'd4096 ? 15'd3413 : 15'd3637;
    // Geometrically empty inputs belong to the ordinary empty/culled path,
    // not the shape-reject accounting class.
    assign reject_o=x0<x1&&y0<y1&&(opacity_q12_i==0||axis_magnitude>=axis_threshold);
endmodule
