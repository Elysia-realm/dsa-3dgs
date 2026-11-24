// Decode the frozen projection block descriptor at the boundary to raster.
// Keeping all bit positions here prevents system wrappers from duplicating
// fragile slices. Descriptor layout follows camera_projection_tile_lane.
module ordered_gaussian_block_decoder #(
    parameter int unsigned EPOCH_W=16,parameter int unsigned GID_W=32,
    parameter int unsigned SEQ_W=16,parameter int unsigned COORD_W=27,
    parameter int unsigned COV2_W=35,parameter int unsigned SCREEN_W=27,
    parameter int unsigned PIXEL_W=16,parameter int unsigned META_W=EPOCH_W+GID_W+SEQ_W,
    parameter int unsigned RAW_DESC_W=META_W+13+COORD_W+3*COV2_W+2*SCREEN_W+4*PIXEL_W+1,
    parameter int unsigned DESC_W=RAW_DESC_W+15+16+15+6+6+1
) (
    input logic[DESC_W-1:0]desc_i,
    output logic[EPOCH_W-1:0]epoch_o,output logic[GID_W-1:0]gid_o,output logic[SEQ_W-1:0]seq_o,
    output logic[12:0]opacity_q12_o,output logic signed[SCREEN_W-1:0]mean_x_q8_o,mean_y_q8_o,
    output logic[PIXEL_W-1:0]bbox_x0_o,bbox_y0_o,bbox_x1_o,bbox_y1_o,
    output logic[14:0]l00_q12_o,output logic signed[15:0]l10_q12_o,output logic[14:0]l11_q12_o,
    output logic signed[5:0]coordinate_shift_o,factor_shift_o,output logic keep_o,numeric_overflow_o
);
    localparam int unsigned ENCODED_TAIL_W=15+16+15+6+6+1;
    localparam int unsigned RAW_KEEP_LSB=ENCODED_TAIL_W;
    localparam int unsigned RAW_Y1_LSB=RAW_KEEP_LSB+1;
    localparam int unsigned RAW_X1_LSB=RAW_Y1_LSB+PIXEL_W;
    localparam int unsigned RAW_Y0_LSB=RAW_X1_LSB+PIXEL_W;
    localparam int unsigned RAW_X0_LSB=RAW_Y0_LSB+PIXEL_W;
    localparam int unsigned RAW_MEAN_Y_LSB=RAW_X0_LSB+PIXEL_W;
    localparam int unsigned RAW_MEAN_X_LSB=RAW_MEAN_Y_LSB+SCREEN_W;
    logic[META_W-1:0]meta;
    assign meta=desc_i[DESC_W-1-:META_W];assign {epoch_o,gid_o,seq_o}=meta;
    assign opacity_q12_o=desc_i[DESC_W-META_W-1-:13];
    assign mean_x_q8_o=desc_i[RAW_MEAN_X_LSB+:SCREEN_W];assign mean_y_q8_o=desc_i[RAW_MEAN_Y_LSB+:SCREEN_W];
    assign bbox_x0_o=desc_i[RAW_X0_LSB+:PIXEL_W];assign bbox_y0_o=desc_i[RAW_Y0_LSB+:PIXEL_W];
    assign bbox_x1_o=desc_i[RAW_X1_LSB+:PIXEL_W];assign bbox_y1_o=desc_i[RAW_Y1_LSB+:PIXEL_W];
    assign keep_o=desc_i[RAW_KEEP_LSB];assign l00_q12_o=desc_i[58:44];assign l10_q12_o=desc_i[43:28];
    assign l11_q12_o=desc_i[27:13];assign coordinate_shift_o=desc_i[12:7];assign factor_shift_o=desc_i[6:1];
    assign numeric_overflow_o=desc_i[0];
endmodule
