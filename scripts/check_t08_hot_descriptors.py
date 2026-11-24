"""Extract encoded descriptor through real DMA and check candidate on every bbox pixel."""
from pathlib import Path
import re
import sys
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_early_advance import OUT as EARLY,matching_source
from scripts.t08_common import BASE,SCENES,WORK,read,save,sha,run_logged
from model.fixed.alpha import alpha_block_float_codes
from verification.test_shape_block_reject import rtl_delta

OUT=BASE/'bbox_axis0_probe_packed_20261122'
MODULE='rtl/projection/gaussian_bbox_axis0_reject.sv'

def slot(path,index,lines):
    with path.open('rb') as stream:
        stride=len(stream.readline())
        assert stride in (33,34)
        stream.seek(index*lines*stride)
        words=[stream.readline() for _ in range(lines)]
        assert all(len(w)==stride and len(w.strip())==32 for w in words)
        return [int(w,16) for w in words]

def build():
    parent=BASE/'native_gaussian_work_20261122/build/binary.json'
    prior=read(parent);matching_source()
    bench=OUT/'tb_t08_bbox_probe.sv'
    original=EARLY/'build/full/1/tb_t08_integrated.sv'
    s=original.read_text().replace('tb_t08_integrated','tb_t08_bbox_probe')
    front='dut.u_frame.u_render.u_render'
    monitor="""
  wire reject_entire;
  gaussian_bbox_axis0_reject predicate(.x0_i(F.bbox_x0),.x1_i(F.bbox_x1),.y0_i(F.bbox_y0),.y1_i(F.bbox_y1),
    .mean_x_i(F.block_mean_x),.mean_y_i(F.block_mean_y),.coord_i(F.coordinate_shift),.factor_i(F.factor_shift),
    .l00_i(F.l00),.l10_i(F.l10),.opacity_i(F.block_opacity),.reject_o(reject_entire));
  always @(posedge clk_i) if(rst_ni && F.block_valid && F.block_ready)begin
    if(frame_error_o||!F.keep||F.block_culled||!F.block_first||F.block_gid!=0||!dut.cmd_qsu_enable_q||
       dut.cmd_attribute_format_q!=1||epoch_id_o!=1||t08_requests!=1)$fatal(1,"bad descriptor probe");
    $display("HOT_DESC %h",{F.bbox_x0,F.bbox_y0,F.bbox_x1,F.bbox_y1,F.block_mean_x,F.block_mean_y,
      F.l00,F.l10,F.l11,F.coordinate_shift,F.factor_shift,F.block_opacity,reject_entire});
    $finish;
  end
"""
    bench.write_text(s.replace('endmodule',monitor.replace('F.',front+'.')+'\nendmodule'))
    cmd=list(prior['command'])
    cmd[cmd.index('--top-module')+1]='tb_t08_bbox_probe'
    oldbench=BASE/'native_gaussian_work_20261122/build/tb_t08_native_locality.sv'
    cmd[cmd.index(str(oldbench))]=str(bench)
    work=WORK/OUT.name;work.mkdir(parents=True,exist_ok=True)
    cmd[cmd.index('--Mdir')+1]=str(work)
    cmd.append(str(ROOT/MODULE))
    cmd=[a if not a.startswith('-DTB_MAX_COUNT=') else '-DTB_MAX_COUNT=16' for a in cmd]
    src={**matching_source()[0],MODULE:sha(ROOT/MODULE),str(bench.relative_to(ROOT)):sha(bench)}
    for f,h in prior['sources'].items():
        if f.endswith('.svh') and f in s:
            assert sha(ROOT/f)==h;src[f]=h
    run_logged(cmd,OUT/'build.log')
    exe=work/'simulation';save(OUT/'binary.json',dict(command=cmd,source_sha256=src,elf_sha256=sha(exe)))
    return exe

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    geometry=read(BASE/'native_gaussian_work_20261122/hot_projection.json')['results']
    exe=build();results=[]
    for scene in SCENES:
        native=read(BASE/'inputs/native'/scene/'manifest.json')
        old=read(BASE/'native_gaussian_work_20261122'/scene/'launch.json')
        paths={key:Path(next(a.split('=',1)[1] for a in old['command'] if a.startswith('+'+key+'='))) for key in ('MEAN','ATTR','CAMERA')}
        for k,p in paths.items():assert sha(p)==old['input_sha256'][k]
        for g in (g for g in geometry if g['scene']==scene):
            gid=g['gid'];d=OUT/scene/str(gid);d.mkdir(parents=True,exist_ok=True)
            mean=slot(paths['MEAN'],gid,1)[0];assert mean&0xffffffff==gid
            (d/'mean.memh').write_text(f'{mean&~0xffffffff:032x}\n')
            words=slot(paths['ATTR'],gid,9)
            (d/'attribute.memh').write_text(''.join(f'{w:032x}\n' for w in words))
            camera=paths['CAMERA'].read_text().split();camera[27]=f'{(int(camera[27],16)&~0xffffffff)|1:016x}'
            (d/'camera.memh').write_text('\n'.join(camera)+'\n')
            cmd=[str(exe),'+AUTO_QSU','+ATTR_FORMAT=1','+FRAME_MODE=0','+MEAN='+str(d/'mean.memh'),
                 '+ATTR='+str(d/'attribute.memh'),'+CAMERA='+str(d/'camera.memh')]
            # All output paths point to the new diagnostic directory even if a probe fails to stop.
            cmd.extend('+'+k+'='+str(d/(k+'.memh')) for k in ['FRAME','RGB','SORTED_TRACE'])
            run_logged(cmd,d/'run.log',timeout=180)
            log=(d/'run.log').read_text()
            packet=int(re.search(r'^HOT_DESC ([0-9a-fA-F]+)$',log,re.M)[1],16)
            fields=[]
            for width in reversed([16,16,16,16,-27,-27,15,-16,15,-6,-6,13,1]):
                bits=abs(width);value=packet&((1<<bits)-1);packet>>=bits
                fields.insert(0,value-(1<<bits) if width<0 and value&(1<<(bits-1)) else value)
            assert packet==0
            x0,y0,x1,y1,mx,my,l00,l10,l11,cs,fs,op,reject=fields
            assert [x0,y0,x1,y1]==g['rtl_bbox'] and cs in range(32) and fs<=2
            dx=np.array([rtl_delta(x,mx,cs) for x in range(x0,x1)])
            dy=np.array([rtl_delta(y,my,cs) for y in range(y0,y1)])
            passed=0
            for start in range(0,len(dy),32):
                _,mask=alpha_block_float_codes(dx,dy[start:start+32,None],l00,l10,l11,cs,fs,op)
                passed+=int(mask.sum())
            assert not reject or passed==0,(scene,gid,'unsafe cull',passed)
            results.append(dict(scene=scene,gid=gid,descriptor=fields,rtl_reject=bool(reject),
                total_pixels=len(dx)*len(dy),fixed_alpha_pass_pixels=passed,
                float_alpha_pass_pixels=g['float_alpha_pass_pixels_in_rtl_bbox'],log_sha256=sha(d/'run.log')))
            print(scene,gid,'reject',reject,'passing',passed,flush=True)
    save(OUT/'report.json',dict(status='DIRECTED_DESCRIPTOR_PROBE_COMPLETE',results=results,signed_off=False,
        scope='Selected task/commit leaders with reindexed GID 0. Every observed bbox pixel checked with fixed alpha oracle. Further randomized boundary and production integration checks required.'))

if __name__=='__main__':main()
