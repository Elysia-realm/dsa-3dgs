// Frame-local Gaussian attribute store. The wide logical record is split into
// geometry and appearance banks so an ASIC implementation can map it to a set
// of practical SRAM macros instead of one 1118-bit macro. GIDs are dense,
// frame-local addresses: a GID >= DEPTH is rejected rather than truncated.
module gaussian_attribute_store #(
    parameter int unsigned DEPTH=1024,parameter int unsigned GID_W=32,
    parameter int unsigned COORD_W=27,parameter int unsigned QUAT_W=22,
    parameter int unsigned SCALE_W=24,parameter int unsigned COEFF_W=18,
    parameter int unsigned COEFFS=16,parameter int unsigned ADDR_W=(DEPTH<=1)?1:$clog2(DEPTH),
    parameter int unsigned GEOM_W=3*COORD_W+4*QUAT_W+3*SCALE_W+13,
    parameter int unsigned COEFF_FLAT_W=3*COEFFS*COEFF_W
) (
    input logic clk_i,input logic rst_ni,input logic clear_valid_i,input logic clear_errors_i,
    input logic write_en_i,input logic[GID_W-1:0]write_gid_i,
    input logic signed[COORD_W-1:0]write_world_x_q16_i,write_world_y_q16_i,write_world_z_q16_i,
    input logic signed[QUAT_W-1:0]write_qw_q20_i,write_qx_q20_i,write_qy_q20_i,write_qz_q20_i,
    input logic[SCALE_W-1:0]write_scale_x_q20_i,write_scale_y_q20_i,write_scale_z_q20_i,
    input logic[12:0]write_opacity_q12_i,input logic[COEFF_FLAT_W-1:0]write_coeff_q12_flat_i,
    input logic read_en_i,input logic[GID_W-1:0]read_gid_i,output logic read_response_valid_o,
    output logic read_in_range_o,read_loaded_o,
    output logic signed[COORD_W-1:0]read_world_x_q16_o,read_world_y_q16_o,read_world_z_q16_o,
    output logic signed[QUAT_W-1:0]read_qw_q20_o,read_qx_q20_o,read_qy_q20_o,read_qz_q20_o,
    output logic[SCALE_W-1:0]read_scale_x_q20_o,read_scale_y_q20_o,read_scale_z_q20_o,
    output logic[12:0]read_opacity_q12_o,output logic[COEFF_FLAT_W-1:0]read_coeff_q12_flat_o,
    output logic invalid_write_sticky_o,invalid_read_sticky_o,unloaded_read_sticky_o
);
    logic[GEOM_W-1:0]geometry_write,geometry_read;logic[DEPTH-1:0]valid_q;
    logic write_in_range,read_in_range,write_fire,read_fire,write_same_read;
    logic[ADDR_W-1:0]write_addr,read_addr;integer index;
    assign write_in_range=write_gid_i<DEPTH;assign read_in_range=read_gid_i<DEPTH;
    assign write_addr=write_gid_i[ADDR_W-1:0];assign read_addr=read_gid_i[ADDR_W-1:0];
    assign write_fire=write_en_i&&write_in_range;assign read_fire=read_en_i&&read_in_range;
    assign write_same_read=write_fire&&read_fire&&write_addr==read_addr;
    assign geometry_write={write_world_x_q16_i,write_world_y_q16_i,write_world_z_q16_i,
      write_qw_q20_i,write_qx_q20_i,write_qy_q20_i,write_qz_q20_i,
      write_scale_x_q20_i,write_scale_y_q20_i,write_scale_z_q20_i,write_opacity_q12_i};
    assign {read_world_x_q16_o,read_world_y_q16_o,read_world_z_q16_o,
      read_qw_q20_o,read_qx_q20_o,read_qy_q20_o,read_qz_q20_o,
      read_scale_x_q20_o,read_scale_y_q20_o,read_scale_z_q20_o,read_opacity_q12_o}=geometry_read;
    sram_1r1w_wrapper #(.DATA_W(GEOM_W),.DEPTH(DEPTH),.ADDR_W(ADDR_W))u_geometry(
      .clk_i(clk_i),.read_en_i(read_fire),.read_addr_i(read_addr),.read_data_o(geometry_read),
      .write_en_i(write_fire),.write_addr_i(write_addr),.write_data_i(geometry_write));
    sram_1r1w_wrapper #(.DATA_W(COEFF_FLAT_W),.DEPTH(DEPTH),.ADDR_W(ADDR_W))u_appearance(
      .clk_i(clk_i),.read_en_i(read_fire),.read_addr_i(read_addr),.read_data_o(read_coeff_q12_flat_o),
      .write_en_i(write_fire),.write_addr_i(write_addr),.write_data_i(write_coeff_q12_flat_i));
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        valid_q<='0;read_response_valid_o<=0;read_in_range_o<=0;read_loaded_o<=0;
        invalid_write_sticky_o<=0;invalid_read_sticky_o<=0;unloaded_read_sticky_o<=0;
      end else begin
        read_response_valid_o<=read_en_i;
        if(read_en_i)begin
          read_in_range_o<=read_in_range;
          read_loaded_o<=read_in_range&&(valid_q[read_addr]||write_same_read);
          if(!read_in_range)invalid_read_sticky_o<=1;
          else if(!(valid_q[read_addr]||write_same_read))unloaded_read_sticky_o<=1;
        end
        if(clear_valid_i)for(index=0;index<DEPTH;index=index+1)valid_q[index]<=0;
        if(write_fire)valid_q[write_addr]<=1;
        if(write_en_i&&!write_in_range)invalid_write_sticky_o<=1;
        if(clear_errors_i)begin
          invalid_write_sticky_o<=0;invalid_read_sticky_o<=0;unloaded_read_sticky_o<=0;
        end
      end
    end
`ifndef SYNTHESIS
    initial begin
      assert(DEPTH>0&&(DEPTH&(DEPTH-1))==0);
      assert(GID_W>=ADDR_W);
    end
`endif
endmodule
