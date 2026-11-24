// Ready/valid adapter around the frame-local attribute SRAM. The SRAM has a
// fixed one-cycle response and the adapter holds that response until consumed.
module gaussian_attribute_sram_backend #(
    parameter int unsigned DEPTH=1024,parameter int unsigned GID_W=32,
    parameter int unsigned COORD_W=27,parameter int unsigned QUAT_W=22,
    parameter int unsigned SCALE_W=24,parameter int unsigned COEFF_W=18,
    parameter int unsigned COEFFS=16,parameter int unsigned COEFF_FLAT_W=3*COEFFS*COEFF_W,
    parameter int unsigned ATTR_W=3*COORD_W+4*QUAT_W+3*SCALE_W+13+COEFF_FLAT_W
) (
    input logic clk_i,input logic rst_ni,input logic clear_valid_i,clear_errors_i,
    input logic write_en_i,input logic[GID_W-1:0]write_gid_i,
    input logic signed[COORD_W-1:0]write_world_x_q16_i,write_world_y_q16_i,write_world_z_q16_i,
    input logic signed[QUAT_W-1:0]write_qw_q20_i,write_qx_q20_i,write_qy_q20_i,write_qz_q20_i,
    input logic[SCALE_W-1:0]write_scale_x_q20_i,write_scale_y_q20_i,write_scale_z_q20_i,
    input logic[12:0]write_opacity_q12_i,input logic[COEFF_FLAT_W-1:0]write_coeff_q12_flat_i,
    input logic req_valid_i,output logic req_ready_o,input logic[GID_W-1:0]req_gid_i,
    output logic rsp_valid_o,input logic rsp_ready_i,output logic rsp_in_range_o,rsp_loaded_o,rsp_error_o,
    output logic[ATTR_W-1:0]rsp_data_o,
    output logic invalid_write_sticky_o,invalid_read_sticky_o,unloaded_read_sticky_o
);
    logic read_response,read_in_range,read_loaded,hold_valid_q;
    logic signed[COORD_W-1:0]wx,wy,wz;logic signed[QUAT_W-1:0]qw,qx,qy,qz;
    logic[SCALE_W-1:0]sx,sy,sz;logic[12:0]opacity;logic[COEFF_FLAT_W-1:0]coeff;
    logic[ATTR_W-1:0]read_data,hold_data_q;logic hold_in_range_q,hold_loaded_q;
    logic request_fire;

    assign req_ready_o=!hold_valid_q;
    assign request_fire=req_valid_i&&req_ready_o;
    assign read_data={wx,wy,wz,qw,qx,qy,qz,sx,sy,sz,opacity,coeff};
    assign rsp_valid_o=hold_valid_q;assign rsp_data_o=hold_data_q;
    assign rsp_in_range_o=hold_in_range_q;assign rsp_loaded_o=hold_loaded_q;assign rsp_error_o=1'b0;

    gaussian_attribute_store #(.DEPTH(DEPTH),.GID_W(GID_W),.COORD_W(COORD_W),.QUAT_W(QUAT_W),
      .SCALE_W(SCALE_W),.COEFF_W(COEFF_W),.COEFFS(COEFFS))u_store(
      .clk_i(clk_i),.rst_ni(rst_ni),.clear_valid_i(clear_valid_i),.clear_errors_i(clear_errors_i),
      .write_en_i(write_en_i),.write_gid_i(write_gid_i),.write_world_x_q16_i(write_world_x_q16_i),
      .write_world_y_q16_i(write_world_y_q16_i),.write_world_z_q16_i(write_world_z_q16_i),
      .write_qw_q20_i(write_qw_q20_i),.write_qx_q20_i(write_qx_q20_i),.write_qy_q20_i(write_qy_q20_i),
      .write_qz_q20_i(write_qz_q20_i),.write_scale_x_q20_i(write_scale_x_q20_i),
      .write_scale_y_q20_i(write_scale_y_q20_i),.write_scale_z_q20_i(write_scale_z_q20_i),
      .write_opacity_q12_i(write_opacity_q12_i),.write_coeff_q12_flat_i(write_coeff_q12_flat_i),
      .read_en_i(request_fire),.read_gid_i(req_gid_i),.read_response_valid_o(read_response),
      .read_in_range_o(read_in_range),.read_loaded_o(read_loaded),.read_world_x_q16_o(wx),
      .read_world_y_q16_o(wy),.read_world_z_q16_o(wz),.read_qw_q20_o(qw),.read_qx_q20_o(qx),
      .read_qy_q20_o(qy),.read_qz_q20_o(qz),.read_scale_x_q20_o(sx),.read_scale_y_q20_o(sy),
      .read_scale_z_q20_o(sz),.read_opacity_q12_o(opacity),.read_coeff_q12_flat_o(coeff),
      .invalid_write_sticky_o(invalid_write_sticky_o),.invalid_read_sticky_o(invalid_read_sticky_o),
      .unloaded_read_sticky_o(unloaded_read_sticky_o));

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin hold_valid_q<=0;hold_data_q<='0;hold_in_range_q<=0;hold_loaded_q<=0;end
      else begin
        if(hold_valid_q&&rsp_ready_i)hold_valid_q<=0;
        if(read_response)begin
          hold_valid_q<=1;hold_data_q<=read_data;
          hold_in_range_q<=read_in_range;hold_loaded_q<=read_loaded;
        end
      end
    end
endmodule
