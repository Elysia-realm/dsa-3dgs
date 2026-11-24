"""One-shot reviewed integration from the frozen T07 production baseline."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,read,save,sha

def main():
    out=BASE/'integration_20261107';assert not (out/'edit_manifest.json').exists(),'already integrated'
    baseline=read(BASE/'recovery_20261107/production_before/manifest.json')
    edits={}
    def get(name):
        assert sha(ROOT/name)==baseline[name],('unexpected source',name)
        return (ROOT/name).read_text()
    def once(s,a,b):
        assert s.count(a)==1,(a,s.count(a));return s.replace(a,b,1)
    param="    parameter bit ENABLE_COMPRESSED_ATTRIBUTES=1'b0,\n"
    modules=['rtl/gs_accel_system_top.sv','rtl/gaussian_frame_render_pipeline.sv',
      'rtl/gaussian_sorted_render_pipeline.sv','rtl/gaussian_ordered_render_frontend.sv',
      'rtl/projection/gaussian_projection_sh_array.sv','rtl/projection/raw_gaussian_projection_array.sv',
      'rtl/projection/raw_gaussian_projection_lane.sv']
    for f in modules:
        s=get(f);needle=' #(\n';assert needle in s
        s=once(s,needle,needle+param);edits[f]=s
    # Sideband always shares the same FIFO/issue/meta packet as its Gaussian.
    for f in modules[3:]:
        s=edits[f];pos=s.index(') (')+4
        s=s[:pos]+"\n    input logic [248:0] s_attr_aux_i,\n"+s[pos:];edits[f]=s
    # Propagate compile-time capability on the production nesting chain.
    children=['gaussian_frame_render_pipeline','gaussian_sorted_render_pipeline','gaussian_ordered_render_frontend',
              'gaussian_projection_sh_array','raw_gaussian_projection_array','raw_gaussian_projection_lane']
    for f,child in zip(modules,children):
        edits[f]=once(edits[f],child+' #(',child+' #(.ENABLE_COMPRESSED_ATTRIBUTES(ENABLE_COMPRESSED_ATTRIBUTES),')
    f=modules[1];s=edits[f]
    s=once(s,'3*COORD_W+4*QUAT_W+3*SCALE_W+13+COEFF_FLAT_W-1:0]attr_rsp_data_i',
             '3*COORD_W+4*QUAT_W+3*SCALE_W+13+COEFF_FLAT_W+(ENABLE_COMPRESSED_ATTRIBUTES?249:0)-1:0]attr_rsp_data_i');edits[f]=s
    f=modules[2];s=edits[f]
    s=once(s,'parameter int unsigned ATTR_W=3*COORD_W+4*QUAT_W+3*SCALE_W+13+COEFF_FLAT_W',
             'parameter int unsigned ATTR_W=3*COORD_W+4*QUAT_W+3*SCALE_W+13+COEFF_FLAT_W+(ENABLE_COMPRESSED_ATTRIBUTES?249:0)')
    s=once(s,'logic[GID_W-1:0]backend_req_gid;',
             'localparam int LEGACY_ATTR_W=3*COORD_W+4*QUAT_W+3*SCALE_W+13+COEFF_FLAT_W;\n    logic[LEGACY_ATTR_W-1:0]local_backend_data;\n    logic[248:0]issue_aux;\n    logic[GID_W-1:0]backend_req_gid;')
    s=once(s,'.rsp_data_o(backend_rsp_data)', '.rsp_data_o(local_backend_data)')
    s=once(s,"assign attr_req_valid_o=1'b0;", "assign backend_rsp_data=ATTR_W'(local_backend_data);\n        assign attr_req_valid_o=1'b0;")
    s=once(s,'ordered_gaussian_attribute_issue #(', 'ordered_gaussian_attribute_issue #(.ATTR_W(ATTR_W),')
    s=once(s,'attr_sx,attr_sy,attr_sz,attr_opacity,attr_coeff}=issue_attr_data;',
             'attr_sx,attr_sy,attr_sz,attr_opacity,attr_coeff}=issue_attr_data[LEGACY_ATTR_W-1:0];\n    assign issue_aux=ENABLE_COMPRESSED_ATTRIBUTES?249\'(issue_attr_data>>LEGACY_ATTR_W):249\'d0;')
    s=once(s,'.s_opacity_q12_i(attr_opacity),', '.s_attr_aux_i(issue_aux),.s_opacity_q12_i(attr_opacity),');edits[f]=s
    f=modules[3];edits[f]=once(edits[f],'.s_opacity_q12_i(s_opacity_q12_i),',
                              '.s_attr_aux_i(s_attr_aux_i),.s_opacity_q12_i(s_opacity_q12_i),')
    f=modules[4];s=edits[f]
    s=once(s,'parameter int unsigned PROJ_W=META_W+3*COORD_W+4*QUAT_W+3*SCALE_W+13,',
             'parameter int unsigned PROJ_W=META_W+3*COORD_W+4*QUAT_W+3*SCALE_W+13+(ENABLE_COMPRESSED_ATTRIBUTES?249:0),')
    s=once(s,'logic[META_W-1:0]source_meta;', 'logic[248:0]projection_aux;\n    logic[META_W-1:0]source_meta;')
    a='assign fork_projection_in={source_meta,s_world_x_q16_i,s_world_y_q16_i,s_world_z_q16_i,\n      s_qw_q20_i,s_qx_q20_i,s_qy_q20_i,s_qz_q20_i,s_scale_x_q20_i,s_scale_y_q20_i,s_scale_z_q20_i,s_opacity_q12_i};'
    original=a[len('assign fork_projection_in='):-1]
    s=once(s,a,"assign fork_projection_in=ENABLE_COMPRESSED_ATTRIBUTES?PROJ_W'({"+original[1:-1]+",s_attr_aux_i}):PROJ_W'("+original+");")
    s=once(s,'projection_sx,projection_sy,projection_sz,projection_opacity}=fork_projection_out;',
             "projection_sx,projection_sy,projection_sz,projection_opacity}=fork_projection_out>>(ENABLE_COMPRESSED_ATTRIBUTES?249:0);\n    assign projection_aux=ENABLE_COMPRESSED_ATTRIBUTES?249'(fork_projection_out):249'd0;")
    s=once(s,'.s_opacity_q12_i(projection_opacity),', '.s_attr_aux_i(projection_aux),.s_opacity_q12_i(projection_opacity),');edits[f]=s
    f=modules[5];s=edits[f]
    s=once(s,'parameter int unsigned INPUT_W  = META_W+3*COORD_W+4*QUAT_W+3*SCALE_W+13+1,',
             'parameter int unsigned INPUT_W  = META_W+3*COORD_W+4*QUAT_W+3*SCALE_W+13+1+(ENABLE_COMPRESSED_ATTRIBUTES?249:0),')
    s=once(s,'MEAN_META_W=META_W+4*QUAT_W+3*SCALE_W+13;',
             'MEAN_META_W=META_W+4*QUAT_W+3*SCALE_W+13+(ENABLE_COMPRESSED_ATTRIBUTES?249:0);\n    logic[MEAN_META_W-1:0]source_mean_meta;\n    assign source_mean_meta=ENABLE_COMPRESSED_ATTRIBUTES?MEAN_META_W\'({s_meta_i,s_qw_q20_i,s_qx_q20_i,s_qy_q20_i,s_qz_q20_i,s_scale_x_q20_i,s_scale_y_q20_i,s_scale_z_q20_i,s_opacity_q12_i,s_attr_aux_i}):MEAN_META_W\'({s_meta_i,s_qw_q20_i,s_qx_q20_i,s_qy_q20_i,s_qz_q20_i,s_scale_x_q20_i,s_scale_y_q20_i,s_scale_z_q20_i,s_opacity_q12_i});')
    s=once(s,'.s_meta_i({s_meta_i,s_qw_q20_i,s_qx_q20_i,s_qy_q20_i,s_qz_q20_i,\n          s_scale_x_q20_i,s_scale_y_q20_i,s_scale_z_q20_i,s_opacity_q12_i})','.s_meta_i(source_mean_meta)')
    s=once(s,'assign mean_meta={s_meta_i,s_qw_q20_i,s_qx_q20_i,s_qy_q20_i,s_qz_q20_i,\n        s_scale_x_q20_i,s_scale_y_q20_i,s_scale_z_q20_i,s_opacity_q12_i};','assign mean_meta=source_mean_meta;')
    s=once(s,'logic[META_W-1:0]lane_meta;', 'logic[248:0]lane_aux;\n      logic[META_W-1:0]lane_meta;')
    s=once(s,'lane_sx,lane_sy,lane_sz,lane_opacity,lane_mean_overflow}=lane_s_data[lane];',
             "lane_sx,lane_sy,lane_sz,lane_opacity}=lane_s_data[lane]>>(1+(ENABLE_COMPRESSED_ATTRIBUTES?249:0));\n      assign lane_mean_overflow=lane_s_data[lane][0];\n      assign lane_aux=ENABLE_COMPRESSED_ATTRIBUTES?249'(lane_s_data[lane]>>1):249'd0;")
    s=once(s,'.s_opacity_q12_i(lane_opacity),', '.s_attr_aux_i(lane_aux),.s_opacity_q12_i(lane_opacity),');edits[f]=s
    f=modules[6];s=edits[f]
    s=once(s,'localparam int unsigned PIPE_META_W = META_W + 13;',
             'localparam int unsigned PIPE_META_W = META_W + 13;\n    localparam int WORLD_META_W=PIPE_META_W+(ENABLE_COMPRESSED_ATTRIBUTES?249:0);\n    logic[WORLD_META_W-1:0]world_input_meta,world_result_meta;\n    logic[248:0]world_aux;\n    logic signed[COV3_W-1:0]computed_xx,computed_xy,computed_xz,computed_yy,computed_yz,computed_zz;\n    logic computed_overflow;\n    assign world_input_meta=ENABLE_COMPRESSED_ATTRIBUTES?WORLD_META_W\'({s_meta_i,s_opacity_q12_i,s_attr_aux_i}):WORLD_META_W\'({s_meta_i,s_opacity_q12_i});\n    assign world_aux=ENABLE_COMPRESSED_ATTRIBUTES?249\'(world_result_meta):249\'d0;\n    assign world_cov_meta=world_result_meta>>(ENABLE_COMPRESSED_ATTRIBUTES?249:0);\n    assign world_cov_overflow=world_aux[246]?1\'b0:computed_overflow;')
    s=once(s,'quaternion_scale_covariance_core #(.META_W(PIPE_META_W)', 'quaternion_scale_covariance_core #(.META_W(WORLD_META_W)')
    start=s.index('quaternion_scale_covariance_core #');end=s.index('    covariance_view_rotate_core #',start)
    block=s[start:end]
    block=once(block,'.s_meta_i({s_meta_i,s_opacity_q12_i})','.s_meta_i(world_input_meta)')
    block=once(block,'.m_meta_o(world_cov_meta)','.m_meta_o(world_result_meta)')
    for i,key in enumerate(['xx','xy','xz','yy','yz','zz']):
        block=once(block,f'.m_cov_{key}_q16_o(world_{key})',f'.m_cov_{key}_q16_o(computed_{key})')
    block=once(block,'.m_numeric_overflow_o(world_cov_overflow)','.m_numeric_overflow_o(computed_overflow)')
    block+='    // Same elastic stages/tag ordering for raw and precomputed records.\n'
    for i,key in enumerate(['xx','xy','xz','yy','yz','zz']):
        block+=f"    assign world_{key}=world_aux[246]?$signed(world_aux[{245-i*41}-:41]):computed_{key};\n"
    s=s[:start]+block+s[end:];edits[f]=s
    # New APB shadow format, reset-compatible legacy format zero.
    f='rtl/control/apb_regfile.sv';s=get(f)
    s=once(s,'output logic [63:0]          attribute_base_o,','output logic [63:0]          attribute_base_o,\n    output logic [1:0]           attribute_format_o,')
    s=once(s,'&& !qsu_address;',"&& !qsu_address && paddr_i!=12'h0f0;")
    s=once(s,"12'h0c0: prdata_o=", "12'h0f0: prdata_o={30'd0,attribute_format_o};\n            12'h0c0: prdata_o=")
    s=once(s,'qsu_enable_o<=0;', 'attribute_format_o<=0;qsu_enable_o<=0;')
    s=once(s,"12'h0c0: if(pstrb_i[0])", "12'h0f0: if(pstrb_i[0])attribute_format_o<=pwdata_i[1:0];\n                    12'h0c0: if(pstrb_i[0])");edits[f]=s
    f=modules[0];s=edits[f]
    s=once(s,'logic attr_req_valid,', 'logic[1:0]attribute_format,cmd_attribute_format_q,logical_attribute_format_q;\n    logic attribute_format_ok;\n    logic[1117:0]compressed_legacy;logic[245:0]compressed_cov;\n    logic compressed_precomputed;logic[1:0]compressed_degree;\n    logic attr_req_valid,')
    s=once(s,'logic[ATTR_W-1:0]attr_rsp_data;', 'logic[ATTR_W+(ENABLE_COMPRESSED_ATTRIBUTES?249:0)-1:0]attr_rsp_data;')
    s=once(s,'.attribute_base_o(attribute_base),', '.attribute_base_o(attribute_base),.attribute_format_o(attribute_format),')
    s=once(s,'image_width==logical_image_width_q&&image_height==logical_image_height_q;',
             'image_width==logical_image_width_q&&image_height==logical_image_height_q&&attribute_format==logical_attribute_format_q;')
    s=once(s,'assign batch_sequence_valid=qsu_config_ok&&',
             "assign attribute_format_ok=attribute_format==0||(ENABLE_COMPRESSED_ATTRIBUTES&&USE_AXI_ATTR_DMA&&attribute_format==1);\n    assign batch_sequence_valid=attribute_format_ok&&qsu_config_ok&&")
    s=once(s,'cmd_qsu_enable_q<=0;', 'cmd_attribute_format_q<=0;logical_attribute_format_q<=0;cmd_qsu_enable_q<=0;')
    s=once(s,'cmd_output_base_q<=output_base;cmd_attribute_base_q<=attribute_base;',
             'cmd_output_base_q<=output_base;cmd_attribute_base_q<=attribute_base;cmd_attribute_format_q<=attribute_format;\n          if(!continue_pulse)logical_attribute_format_q<=attribute_format;')
    start=s.index('      if(USE_AXI_ATTR_DMA)begin:g_axi_attr');end=s.index('      end else begin:g_local_attr',start)
    original=s[start:end]
    new=original.replace('if(USE_AXI_ATTR_DMA)begin:g_axi_attr','if(USE_AXI_ATTR_DMA&&ENABLE_COMPRESSED_ATTRIBUTES)begin:g_t08_attr')
    new=once(new,'axi4_gaussian_attribute_read_engine #(', 'axi4_t08_attribute_read_engine #(')
    new=once(new,'.GID_W(GID_W),.ATTR_W(ATTR_W))','.GID_W(GID_W))')
    new=once(new,'.base_addr_i(cmd_attribute_base_q),','.base_addr_i(cmd_attribute_base_q),.format_i(cmd_attribute_format_q),')
    new=once(new,'.rsp_data_o(attr_rsp_data)', '.rsp_data_o(compressed_legacy),.rsp_covariance_q20_o(compressed_cov),\n          .rsp_precomputed_o(compressed_precomputed),.rsp_degree_o(compressed_degree)')
    new+='        assign attr_rsp_data={compressed_degree,compressed_precomputed,compressed_cov,compressed_legacy};\n'
    s=s[:start]+new+'      end else '+original.lstrip()+s[end:];edits[f]=s
    f='verification/rtl/system_top_sources.f';s=get(f)
    s+='\nrtl/dma/t08_attribute_decoder.sv\nrtl/dma/axi4_t08_attribute_read_engine.sv\n';edits[f]=s
    # Validate all edits before writing any production source.
    for f,s in edits.items():assert s!=(ROOT/f).read_text()
    for f,s in edits.items():(ROOT/f).write_text(s)
    save(out/'edit_manifest.json',dict(before={f:baseline[f] for f in edits},after={f:sha(ROOT/f) for f in edits},
         script_sha256=sha(Path(__file__)),signed_off=False))
    print('Integrated candidate in',len(edits),'files')

if __name__=='__main__':main()
