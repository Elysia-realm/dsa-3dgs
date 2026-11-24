"""Bounded pre-enumeration cull in the production pipeline with paired native frames."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import fcntl
import itertools
import os
import re
import sys
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.check_t08_hot_descriptors import slot,MODULE
from scripts.run_t08_early_advance import OUT as DMA,matching_source
from scripts.read_rgb888_frame import decode_rgb888
from scripts.run_t01_wsl_real import blocks
from scripts.t08_common import BASE,WORK,SCENES,MAX_PIXELS,read,save,sha,run_logged

OUT=BASE/'bbox_pair_native_20261122'
PROBE=BASE/'bbox_axis0_probe_packed_20261122/report.json'
SERIAL_MODULE='rtl/projection/gaussian_bbox_axis0_serial.sv'
SERIAL=False


def build(enabled):
    src,_=matching_source()
    old=read(DMA/'build/full/1/binary.json')
    name='camera_projection_tile_lane'
    lane=ROOT/f'rtl/projection/{name}.sv'
    directory=OUT/'build'/str(enabled);directory.mkdir(parents=True,exist_ok=True)
    replacement=directory/lane.name
    needle='    assign encoded_keep=encoded_raw_desc[0]&&!encoded_numeric_overflow;'
    body=lane.read_text()
    assert body.count(needle)==1
    body=body.replace(needle,f"""
    logic bbox_proven_empty;
    wire signed [SCREEN_W-1:0] encoded_my=encoded_raw_desc[4*PIXEL_W+1+:SCREEN_W];
    wire signed [SCREEN_W-1:0] encoded_mx=encoded_raw_desc[4*PIXEL_W+1+SCREEN_W+:SCREEN_W];
    gaussian_bbox_axis0_reject #(.SCREEN_W(SCREEN_W),.PIXEL_W(PIXEL_W)) u_bbox_axis0(
      .x0_i(encoded_x0),.y0_i(encoded_y0),.x1_i(encoded_x1),.y1_i(encoded_y1),
      .mean_x_i(encoded_mx),.mean_y_i(encoded_my),.coord_i(encoded_coordinate_shift),
      .factor_i(encoded_factor_shift),.l00_i(encoded_l00),.l10_i(encoded_l10),.opacity_i(encoded_opacity),
      .reject_o(bbox_proven_empty));
    wire bbox_skip=1'b{enabled}&&encoded_raw_desc[0]&&!encoded_numeric_overflow&&bbox_proven_empty;
    assign encoded_keep=encoded_raw_desc[0]&&!encoded_numeric_overflow&&!bbox_skip;
""")
    if SERIAL:
        start=body.index('    gaussian_bbox_axis0_reject #')
        end=body.index('    assign encoded_keep=',start)
        # The existing encoder already holds the complete tagged descriptor
        # stable. Keep ready low there until the generator accepts its token.
        body=body[:start]+f"""
    logic generator_ready,bbox_offer;
    wire base_keep=encoded_raw_desc[0]&&!encoded_numeric_overflow;
    if(1'b{enabled})begin:g_serial_bbox
      gaussian_bbox_axis0_serial #(.SCREEN_W(SCREEN_W),.PIXEL_W(PIXEL_W)) u_serial(
        .clk_i(clk_i),.rst_ni(rst_ni),.valid_i(encoder_valid),.keep_i(base_keep),
        .ready_i(generator_ready),.ready_o(task_desc_ready),.valid_o(bbox_offer),.reject_o(bbox_proven_empty),
        .x0_i(encoded_x0),.y0_i(encoded_y0),.x1_i(encoded_x1),.y1_i(encoded_y1),
        .mean_x_i(encoded_mx),.mean_y_i(encoded_my),.coord_i(encoded_coordinate_shift),
        .factor_i(encoded_factor_shift),.l00_i(encoded_l00),.l10_i(encoded_l10),.opacity_i(encoded_opacity));
    end else begin:g_no_serial_bbox
      assign task_desc_ready=generator_ready;
      assign bbox_offer=encoder_valid;assign bbox_proven_empty=0;
    end
    wire bbox_skip=base_keep&&bbox_proven_empty;
"""+body[end:]
        old_port='.s_valid_i(encoder_valid),.s_ready_o(task_desc_ready)'
        assert body.count(old_port)==1
        body=body.replace(old_port,'.s_valid_i(bbox_offer),.s_ready_o(generator_ready)')
    listing=ROOT/'verification/rtl/system_top_sources.f'
    files=listing.read_text().splitlines()
    assert files.count(str(lane.relative_to(ROOT)))==1
    files[files.index(str(lane.relative_to(ROOT)))]=str(replacement)
    filelist=directory/'sources.f';predicate=SERIAL_MODULE if SERIAL else MODULE;files.append(predicate)
    top='tb_t08_bbox_pair'
    bench=directory/(top+'.sv')
    original=DMA/'build/full/1/tb_t08_integrated.sv'
    tb=original.read_text().replace('tb_t08_integrated',top)
    hook='''longint unsigned bbox_skips[0:LANES-1];
  for(genvar l=0;l<LANES;l++)begin:g_bbox_probe
    initial bbox_skips[l]=0;
    always @(posedge clk_i)if(rst_ni && LANE.encoder_valid && LANE.task_desc_ready && LANE.bbox_skip)
      bbox_skips[l]<=bbox_skips[l]+1;
  end
'''.replace('LANE.', 'dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[l].u_lane.u_camera_lane.')
    tb=tb.replace('endmodule',hook+'endmodule')
    mark=f'$display("PASS: {top}");'
    assert tb.count(mark)==1
    tb=tb.replace(mark,'begin longint unsigned s;s=0;for(int j=0;j<LANES;j++)s+=bbox_skips[j];$display("BBOX_SKIPS %0d",s);end\n    '+mark)
    for path,data in [(replacement,body),(filelist,'\n'.join(files)+'\n'),(bench,tb)]:
        if path.exists():assert path.read_text()==data
        else:path.write_text(data)
    code={**old['source_sha256'],**src,predicate:sha(ROOT/predicate)}
    for path in [bench,replacement,filelist]:code[str(path.relative_to(ROOT))]=sha(path)
    assert all(sha(ROOT/f)==h for f,h in code.items())
    w=WORK/OUT.name/str(enabled);w.mkdir(parents=True,exist_ok=True)
    cmd=list(old['command']);cmd[cmd.index('--top-module')+1]=top;cmd[cmd.index('--Mdir')+1]=str(w)
    cmd[cmd.index('-f')+1]=str(filelist);cmd[cmd.index(str(original))]=str(bench)
    cmd=[f'-DTB_MAX_PIXELS={MAX_PIXELS}' if a.startswith('-DTB_MAX_PIXELS=') else '-DTB_MAX_COUNT=128' if a.startswith('-DTB_MAX_COUNT=') else a for a in cmd]
    exe=w/'simulation';marker=directory/'binary.json'
    if marker.exists():
        result=read(marker)
        assert result['sources']==code and result['command']==cmd and sha(exe)==result['elf_sha256']
        return result
    run_logged(cmd,directory/'build.log')
    result=dict(command=cmd,sources=code,exe=str(exe),elf_sha256=sha(exe),enabled=enabled,parameters=old['parameters'])
    save(marker,result);return result


def prepare(scene):
    native=read(BASE/'inputs/native'/scene/'manifest.json')
    ref=read(BASE/'native_gaussian_work_20261122'/scene/'launch.json')
    paths={k:Path(next(x.split('=',1)[1] for x in ref['command'] if x.startswith('+'+k+'='))) for k in ('MEAN','ATTR','CAMERA')}
    assert all(sha(p)==ref['input_sha256'][k] for k,p in paths.items())
    leaders={r['gid'] for r in read(PROBE)['results'] if r['scene']==scene}
    # Preserve original relative GID order, keeping the fixed uniform controls.
    gids=sorted(leaders|{i*(native['gaussians']-1)//63 for i in range(64)})
    d=OUT/'inputs'/scene;d.mkdir(parents=True,exist_ok=True)
    means=[];attrs=[]
    for dense,gid in enumerate(gids):
        word=slot(paths['MEAN'],gid,1)[0];assert word&0xffffffff==gid
        means.append(f'{(word&~0xffffffff)|dense:032x}\n')
        attrs.extend(f'{v:032x}\n' for v in slot(paths['ATTR'],gid,9))
    camera=paths['CAMERA'].read_text().split();camera[-1]=f'{(int(camera[-1],16)&~0xffffffff)|len(gids):016x}'
    for f,data in [('mean.memh',''.join(means)),('attribute.memh',''.join(attrs)),('camera.memh','\n'.join(camera)+'\n')]:
        if (d/f).exists():assert (d/f).read_text()==data
        else:(d/f).write_text(data)
    meta=dict(scene=scene,camera=SCENES[scene],width=native['width'],height=native['height'],gids=gids,full_scene=False,
        source_inputs=ref['input_sha256'],input_sha256={f:sha(d/f) for f in ['mean.memh','attribute.memh','camera.memh']})
    save(d/'manifest.json',meta);return meta


def run_scene(scene,builds):
    meta=prepare(scene);input_dir=OUT/'inputs'/scene;rows=[]
    for enabled,build_info in enumerate(builds):
        d=OUT/'real'/scene/str(enabled);d.mkdir(parents=True,exist_ok=True)
        cmd=read(DMA/'real/full/1'/scene/'f1/run.command.json');cmd[0]=build_info['exe']
        files=dict(MEAN=input_dir/'mean.memh',ATTR=input_dir/'attribute.memh',CAMERA=input_dir/'camera.memh',
                   FRAME=d/'state.memh',RGB=d/'rgb.memh',SORTED_TRACE=d/'sorted.txt')
        cmd=['+'+k+'='+str(files[k]) if (k:=x.partition('=')[0][1:]) in files else x for x in cmd]
        launch=dict(command=cmd,elf_sha256=build_info['elf_sha256'],source_sha256=build_info['sources'],input_sha256=meta['input_sha256'])
        marker=d/'launch.json'
        if marker.exists():
            assert read(marker)==launch
            ex=read(d/'run.execution.json');assert ex['exit_code']==0 and ex['log_sha256']==sha(d/'run.log')
        else:
            save(marker,launch);ex=run_logged(cmd,d/'run.log')
        log=(d/'run.log').read_text();assert 'PASS: tb_t08_bbox_pair' in log and 'error=00000000' in log
        counters=blocks(log);skips=int(re.search(r'^BBOX_SKIPS (\d+)$',log,re.M)[1])
        if not enabled:assert skips==0
        raw=bytes.fromhex((d/'rgb.memh').read_text())
        pixels=decode_rgb888(raw,meta['width'],meta['height']);Image.fromarray(pixels).save(d/'frame.png')
        assert Image.open(d/'frame.png').tobytes()==pixels.tobytes()
        rows.append(dict(enabled=enabled,skips=skips,cycles=counters['REAL_END_TO_END']['command_cycles'],counters=counters,
            log_sha256=ex['log_sha256'],png_sha256=sha(d/'frame.png'),rgb_dma_sha256=sha(d/'rgb.memh'),sorted_sha256=sha(d/'sorted.txt')))
    assert rows[0]['rgb_dma_sha256']==rows[1]['rgb_dma_sha256'] and rows[0]['sorted_sha256']==rows[1]['sorted_sha256']
    base=OUT/'real'/scene
    count=0
    with (base/'0/state.memh').open() as first,(base/'1/state.memh').open() as second:
        for a,b in itertools.zip_longest(first,second):
            assert a and b
            def state(word):
                v=int(word,16)
                return (v&((1<<39)-1),(v>>39)&65535) if (v>>55)&65535==1 else (0,65535)
            rgb,t=state(a);rgb1,t1=state(b)
            assert rgb==rgb1 and (t==t1 or max(t,t1)<=7);count+=1
    assert count==meta['width']*meta['height']
    result=dict(status='PASS_PAIRED_NATIVE_SUBSET',rows=rows,inputs=meta,signed_off=False)
    save(base/'result.json',result);print(scene,[(r['cycles'],r['skips']) for r in rows],flush=True)
    return result


def main():
    global OUT,SERIAL
    if sys.argv[1:]==['--serial']:
        SERIAL=True;OUT=BASE/'bbox_pair_serial_native_20261122'
        assert read(BASE/'bbox_serial_units_20261122/report.json')['status']=='PASS_SERIAL_MODULE'
    elif sys.argv[1:]:raise SystemExit('expected --serial or no arguments')
    assert read(PROBE)['status']=='DIRECTED_DESCRIPTOR_PROBE_COMPLETE'
    assert any(r['rtl_reject'] for r in read(PROBE)['results'])
    assert read(BASE/'bbox_axis0_units_20261122/report.json')['status']=='PASS_MODULE_ONLY'
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        save(OUT/'status.json',dict(status='RUNNING',pid=os.getpid(),signed_off=False))
        try:
            builds=[build(i) for i in (0,1)]
            with ThreadPoolExecutor(max_workers=3) as pool:results=list(pool.map(lambda s:run_scene(s,builds),SCENES))
            matching_source();save(OUT/'report.json',dict(status='PASS_PAIRED_NATIVE_SUBSETS',results=results,signed_off=False))
            save(OUT/'status.json',dict(status='PASS_PAIRED_NATIVE_SUBSETS',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False));raise

if __name__=='__main__':main()
