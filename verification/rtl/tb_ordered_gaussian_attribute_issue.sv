`timescale 1ns/1ps
module tb_ordered_gaussian_attribute_issue;
  localparam GID_W=4,SEQ_W=8,DEPTH=8,COEFF_W=18,FLAT_W=3*16*COEFF_W;
  logic clk_i=0,rst_ni=0,clear_errors_i=0,clear_valid_i=0,write_en_i=0;
  logic[GID_W-1:0]write_gid_i=0;logic signed[26:0]write_world_x_q16_i=0,write_world_y_q16_i=0,write_world_z_q16_i=0;
  logic signed[21:0]write_qw_q20_i=0,write_qx_q20_i=0,write_qy_q20_i=0,write_qz_q20_i=0;
  logic[23:0]write_scale_x_q20_i=0,write_scale_y_q20_i=0,write_scale_z_q20_i=0;logic[12:0]write_opacity_q12_i=0;logic[FLAT_W-1:0]write_coeff_q12_flat_i=0;
  logic s_valid_i=0,s_ready_o;logic signed[26:0]s_depth_i=0;logic[GID_W-1:0]s_gid_i=0;logic[SEQ_W-1:0]s_seq_i=0;logic[1:0]s_group_i=0;
  localparam ATTR_W=3*27+4*22+3*24+13+FLAT_W;
  logic s_group_first_i=0,s_group_last_i=0,attr_req_valid_o,attr_req_ready_i=1;
  logic[GID_W-1:0]attr_req_gid_o;logic attr_response,attr_in_range,attr_loaded,attr_rsp_ready_o;
  logic[ATTR_W-1:0]attr_rsp_data_i,m_attr_data_o;
  logic signed[26:0]attr_wx,attr_wy,attr_wz;logic signed[21:0]attr_qw,attr_qx,attr_qy,attr_qz;logic[23:0]attr_sx,attr_sy,attr_sz;
  logic[12:0]attr_opacity;logic[FLAT_W-1:0]attr_coeff;logic store_iw,store_ir,store_unloaded;
  logic m_valid_o,m_ready_i=1;logic signed[26:0]m_depth_o;logic[GID_W-1:0]m_gid_o;logic[SEQ_W-1:0]m_seq_o;logic[1:0]m_group_o;
  logic m_group_first_o,m_group_last_o;logic signed[26:0]m_world_x_q16_o,m_world_y_q16_o,m_world_z_q16_o;
  logic signed[21:0]m_qw_q20_o,m_qx_q20_o,m_qy_q20_o,m_qz_q20_o;logic[23:0]m_scale_x_q20_o,m_scale_y_q20_o,m_scale_z_q20_o;
  logic[12:0]m_opacity_q12_o;logic[FLAT_W-1:0]m_coeff_q12_flat_o;logic invalid_gid_sticky_o,unloaded_gid_sticky_o,read_pulse_o,idle_o;
  always#5 clk_i=~clk_i;
  gaussian_attribute_store #(.DEPTH(DEPTH),.GID_W(GID_W))store(
    .clk_i(clk_i),.rst_ni(rst_ni),.clear_valid_i(clear_valid_i),.clear_errors_i(clear_errors_i),.write_en_i(write_en_i),.write_gid_i(write_gid_i),
    .write_world_x_q16_i(write_world_x_q16_i),.write_world_y_q16_i(write_world_y_q16_i),.write_world_z_q16_i(write_world_z_q16_i),
    .write_qw_q20_i(write_qw_q20_i),.write_qx_q20_i(write_qx_q20_i),.write_qy_q20_i(write_qy_q20_i),.write_qz_q20_i(write_qz_q20_i),
    .write_scale_x_q20_i(write_scale_x_q20_i),.write_scale_y_q20_i(write_scale_y_q20_i),.write_scale_z_q20_i(write_scale_z_q20_i),
    .write_opacity_q12_i(write_opacity_q12_i),.write_coeff_q12_flat_i(write_coeff_q12_flat_i),
    .read_en_i(attr_req_valid_o&&attr_req_ready_i),.read_gid_i(attr_req_gid_o),
    .read_response_valid_o(attr_response),.read_in_range_o(attr_in_range),.read_loaded_o(attr_loaded),
    .read_world_x_q16_o(attr_wx),.read_world_y_q16_o(attr_wy),.read_world_z_q16_o(attr_wz),.read_qw_q20_o(attr_qw),.read_qx_q20_o(attr_qx),
    .read_qy_q20_o(attr_qy),.read_qz_q20_o(attr_qz),.read_scale_x_q20_o(attr_sx),.read_scale_y_q20_o(attr_sy),.read_scale_z_q20_o(attr_sz),
    .read_opacity_q12_o(attr_opacity),.read_coeff_q12_flat_o(attr_coeff),.invalid_write_sticky_o(store_iw),.invalid_read_sticky_o(store_ir),.unloaded_read_sticky_o(store_unloaded));
  ordered_gaussian_attribute_issue #(.GID_W(GID_W),.SEQ_W(SEQ_W))dut(
    .clk_i(clk_i),.rst_ni(rst_ni),.clear_errors_i(clear_errors_i),.s_valid_i(s_valid_i),.s_ready_o(s_ready_o),.s_depth_i(s_depth_i),.s_gid_i(s_gid_i),
    .s_seq_i(s_seq_i),.s_group_i(s_group_i),.s_group_first_i(s_group_first_i),.s_group_last_i(s_group_last_i),
    .attr_req_valid_o(attr_req_valid_o),.attr_req_ready_i(attr_req_ready_i),.attr_req_gid_o(attr_req_gid_o),
    .attr_rsp_valid_i(attr_response),.attr_rsp_ready_o(attr_rsp_ready_o),.attr_rsp_in_range_i(attr_in_range),
    .attr_rsp_loaded_i(attr_loaded),.attr_rsp_error_i(1'b0),.attr_rsp_data_i(attr_rsp_data_i),
    .m_valid_o(m_valid_o),.m_ready_i(m_ready_i),.m_depth_o(m_depth_o),.m_gid_o(m_gid_o),.m_seq_o(m_seq_o),.m_group_o(m_group_o),
    .m_group_first_o(m_group_first_o),.m_group_last_o(m_group_last_o),.m_attr_data_o(m_attr_data_o),
    .invalid_gid_sticky_o(invalid_gid_sticky_o),.unloaded_gid_sticky_o(unloaded_gid_sticky_o),
    .backend_error_sticky_o(),.read_pulse_o(read_pulse_o),.idle_o(idle_o));
  assign attr_rsp_data_i={attr_wx,attr_wy,attr_wz,attr_qw,attr_qx,attr_qy,attr_qz,
    attr_sx,attr_sy,attr_sz,attr_opacity,attr_coeff};
  assign {m_world_x_q16_o,m_world_y_q16_o,m_world_z_q16_o,m_qw_q20_o,m_qx_q20_o,m_qy_q20_o,m_qz_q20_o,
    m_scale_x_q20_o,m_scale_y_q20_o,m_scale_z_q20_o,m_opacity_q12_o,m_coeff_q12_flat_o}=m_attr_data_o;
  task automatic tick;begin@(posedge clk_i);#1;end endtask
  task automatic load(input integer gid);begin write_gid_i=gid;write_world_x_q16_i=gid*100;write_coeff_q12_flat_i='0;write_coeff_q12_flat_i[0+:COEFF_W]=gid*10;write_en_i=1;tick();write_en_i=0;end endtask
  task automatic send(input integer gid,input integer seq,input integer first,input integer last);begin
    while(!s_ready_o)tick();s_gid_i=gid;s_seq_i=seq;s_depth_i=seq*3;s_group_i=2;s_group_first_i=first;s_group_last_i=last;s_valid_i=1;tick();s_valid_i=0;
  end endtask
  task automatic expect_one(input integer gid,input integer seq);begin integer timeout;timeout=0;while(!m_valid_o&&timeout<10)begin tick();timeout=timeout+1;end
    if(!m_valid_o||m_gid_o!==gid||m_seq_o!==seq||m_world_x_q16_o!==gid*100||m_coeff_q12_flat_o[0+:COEFF_W]!==gid*10)$fatal(1,"ordered issue mismatch");tick();end endtask
  initial begin integer timeout;repeat(2)tick();rst_ni=1;tick();load(1);load(3);load(7);
    send(3,10,1,0);m_ready_i=0;tick();if(!m_valid_o)$fatal(1,"response missing");repeat(3)begin
      if(m_gid_o!==3||m_seq_o!==10||m_world_x_q16_o!==300)$fatal(1,"backpressure changed response");tick();end
    m_ready_i=1;tick();send(1,11,0,0);expect_one(1,11);send(7,12,0,1);expect_one(7,12);
    send(2,13,1,1);timeout=0;while(!unloaded_gid_sticky_o&&timeout<5)begin tick();timeout=timeout+1;end
    if(!unloaded_gid_sticky_o||m_valid_o)$fatal(1,"unloaded issue not rejected");
    send(9,14,1,1);timeout=0;while(!invalid_gid_sticky_o&&timeout<5)begin tick();timeout=timeout+1;end
    if(!invalid_gid_sticky_o||m_valid_o||!idle_o)$fatal(1,"invalid issue not rejected");
    $display("PASS: tb_ordered_gaussian_attribute_issue");$finish;
  end
endmodule
