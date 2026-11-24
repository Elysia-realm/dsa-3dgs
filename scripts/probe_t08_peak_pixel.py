"""Locate the first failing projection stage for the paired subset's peak pixel."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,WORK,read,save,sha,run_logged
from scripts.check_t08_hot_descriptors import slot

def main():
    extra=sys.argv[1:]==['--precision-probe']
    if sys.argv[1:] and not extra:raise ValueError('unexpected argument')
    folder=BASE/'bbox_pair_native_20261122'
    out=BASE/('peak_precision_probe_20261122' if extra else 'peak_pixel_20261122');out.mkdir(parents=True,exist_ok=True)
    worst=max(read(folder/'semantic/audit.json')['results'],key=lambda r:r['max_error'])
    pixel=worst['peak_pixel'];scene=worst['scene']
    assert len(pixel['reference_terms'])==1
    gid=pixel['reference_terms'][0]['ply_gid']
    ref=read(BASE/'bbox_axis0_probe_packed_20261122/binary.json')
    original=BASE/'bbox_axis0_probe_packed_20261122/tb_t08_bbox_probe.sv'
    s=original.read_text()
    assert all(sha(ROOT/f)==h for f,h in ref['source_sha256'].items())
    front='dut.u_frame.u_render.u_render'
    start=s.index('  always @(posedge clk_i) if(rst_ni && '+front+'.block_valid')
    monitor="""
  for(genvar i=0;i<LANES;i++)begin:g_probe
    always @(posedge clk_i)if(rst_ni)begin
      if(C.s_valid_i&&C.s_ready_o)
        $display("POSITION %h", {C.s_transform_overflow_i,C.s_camera_x_q16_i,C.s_camera_y_q16_i,C.s_camera_z_q16_i});
      if(C.join_valid&&C.bbox_ready)
        $display("PROJECTION %h",{C.projection_visible,C.projection_overflow,C.covariance_overflow,C.mean_x_q8,C.mean_y_q8,C.cov00_q8,C.cov01_q8,C.cov11_q8});
      if(C.bbox_valid&&C.encoder_ready)
        $display("BOX %h",{C.bbox_keep,C.bbox_numeric_invalid,C.u_alpha_encoder.determinant_valid,C.bbox_x0,C.bbox_y0,C.bbox_x1,C.bbox_y1});
      if(C.encoder_valid&&C.task_desc_ready)
        $display("ENCODER %h",{C.u_alpha_encoder.input_overflow_final,C.u_alpha_encoder.error_final,C.u_alpha_encoder.factor_encode_overflow,C.encoded_keep});
    end
  end
  always @(posedge clk_i)if(rst_ni && F.block_valid && F.block_ready)begin
    if(frame_error_o||!dut.cmd_qsu_enable_q||F.block_gid!=0||t08_requests!=1)$fatal;
    $display("DESC %h",{F.block_culled,F.keep,F.descriptor_overflow,F.block_mean_x,F.block_mean_y,F.l00,F.l10,F.l11,F.coordinate_shift,F.factor_shift,F.block_opacity,F.block_r,F.block_g,F.block_b});
    $finish;
  end
endmodule
""".replace('F.',front+'.').replace('C.',front+'.u_front.u_projection.g_lane[i].u_lane.u_camera_lane.')
    bench=out/'tb_t08_peak.sv';bench.write_text((s[:start]+monitor).replace('tb_t08_bbox_probe','tb_t08_peak'))
    cmd=list(ref['command']);cmd[cmd.index(str(original))]=str(bench)
    overrides={}
    if extra:
        old_list=ROOT/'verification/rtl/system_top_sources.f'
        files=old_list.read_text().splitlines()
        for filename,key,value in [
            ('raw_gaussian_projection_lane','.META_W(WORLD_META_W),.QUAT_W', '.COV_FRAC_W(24),.META_W(WORLD_META_W),.QUAT_W'),
            ('camera_projection_tile_lane','screen_covariance_core #(.META_W','screen_covariance_core #(.COV3_FRAC_W(24),.META_W')]:
            rel='rtl/projection/'+filename+'.sv';body=(ROOT/rel).read_text()
            assert body.count(key)==1 and files.count(rel)==1
            changed=out/(filename+'.sv');changed.write_text(body.replace(key,value))
            files[files.index(rel)]=str(changed);overrides[str(changed.relative_to(ROOT))]=sha(changed)
        listing=out/'sources.f';listing.write_text('\n'.join(files)+'\n')
        cmd[cmd.index('-f')+1]=str(listing);overrides[str(listing.relative_to(ROOT))]=sha(listing)
    cmd[cmd.index('--top-module')+1]='tb_t08_peak'
    work=WORK/out.name;work.mkdir(parents=True,exist_ok=True);cmd[cmd.index('--Mdir')+1]=str(work)
    run_logged(cmd,out/'build.log')
    native=read(BASE/'inputs/native'/scene/'manifest.json')
    fat=BASE/'extended_20261107/inputs/full'/scene/'attribute.memh'
    mean=slot(Path(native['inputs']['MEAN']),gid,1)[0]
    assert mean&0xffffffff==gid
    (out/'mean.memh').write_text(f'{mean&~0xffffffff:032x}\n')
    cam=Path(native['inputs']['CAMERA']).read_text().split()
    cam[27]=f'{(int(cam[27],16)&~0xffffffff)|1:016x}';(out/'camera.memh').write_text('\n'.join(cam)+'\n')
    rows=[]
    for fmt,path in enumerate((Path(native['inputs']['ATTR']),fat)):
        d=out/str(fmt);d.mkdir(exist_ok=True)
        packet=slot(path,gid,9)
        if extra and fmt==1:
            # v1 escape explicitly carries quaternion/scale. Existing Q20 compact
            # payloads cannot be fed to an experimental Q24 covariance pipeline.
            from model.io.t08_attribute_codec import RAW_HEADER
            raw=sum(v<<(128*i) for i,v in enumerate(slot(Path(native['inputs']['ATTR']),gid,9)))
            escaped=(raw<<16)|RAW_HEADER
            packet=[(escaped>>(128*i))&((1<<128)-1) for i in range(9)]
        (d/'attribute.memh').write_text(''.join(f'{w:032x}\n' for w in packet))
        cmd=[str(work/'simulation'),'+AUTO_QSU',f'+ATTR_FORMAT={fmt}','+FRAME_MODE=0','+CAMERA='+str(out/'camera.memh'),
            '+MEAN='+str(out/'mean.memh'),'+ATTR='+str(d/'attribute.memh')]
        cmd+=['+'+k+'='+str(d/(k+'.memh')) for k in ('FRAME','RGB','SORTED_TRACE')]
        run_logged(cmd,d/'run.log',timeout=180)
        log=(d/'run.log').read_text()
        parsed={}
        layout={'POSITION':[1,-27,-27,-27],'PROJECTION':[1,1,1,-27,-27,35,-35,35],
                'BOX':[1,1,1,16,16,16,16],'ENCODER':[1,1,1,1],
                'DESC':[1,1,1,-27,-27,15,-16,15,-6,-6,13,13,13,13]}
        for key,widths in layout.items():
            lines=[line for line in log.splitlines() if line.startswith(key+' ')]
            assert len(lines)==1,(key,lines)
            packet=int(lines[0].split()[1],16);fields=[]
            for width in reversed(widths):
                bits=abs(width);v=packet&((1<<bits)-1);packet>>=bits
                fields.insert(0,v-(1<<bits) if width<0 and v&(1<<(bits-1)) else v)
            assert packet==0;parsed[key]=fields
        rows.append(parsed);print(fmt,parsed,flush=True)
    save(out/'report.json',dict(scene=scene,gid=gid,peak=pixel,stage_fields=rows,field_widths=layout,
        source_sha256={**ref['source_sha256'],**overrides,str(bench.relative_to(ROOT)):sha(bench)},elf_sha256=sha(work/'simulation'),
        experiment='Q24 world+view, legacy and v1 raw escape only' if extra else 'Q20 released arithmetic, raw and compact',
        scope='Single-record diagnostic for shared raw-reference discrepancy, both DMA formats, before raster.',signed_off=False))

if __name__=='__main__':main()
