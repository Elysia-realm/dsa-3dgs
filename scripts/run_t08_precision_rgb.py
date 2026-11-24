"""Native RGB recovery experiment on the already frozen serial-cull subsets."""
from concurrent.futures import ThreadPoolExecutor
import fcntl
import os
from pathlib import Path
import sys

import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from model.io.t08_attribute_codec import RAW_HEADER
from scripts.check_t08_hot_descriptors import slot
from scripts.read_rgb888_frame import decode_rgb888
from scripts.run_t01_wsl_real import blocks
from scripts.t08_common import BASE, WORK, SCENES, read, save, sha, run_logged

PREVIOUS=BASE/'bbox_pair_serial_native_20261122'
OUT=BASE/'precision_rgb_20261122'


def freeze(path,content):
    if path.exists():
        assert path.read_text()==content, path
    else:
        path.write_text(content)


def build():
    previous=read(PREVIOUS/'build/1/binary.json')
    sources=previous['sources'].copy()
    assert all(sha(ROOT/f)==h for f,h in sources.items())
    d=OUT/'build';d.mkdir(parents=True,exist_ok=True)
    old_dir=PREVIOUS/'build/1'
    files=(old_dir/'sources.f').read_text().splitlines()
    changes=[
        (Path('rtl/projection/raw_gaussian_projection_lane.sv'),'.META_W(WORLD_META_W),.QUAT_W','.COV_FRAC_W(24),.META_W(WORLD_META_W),.QUAT_W'),
        (old_dir/'camera_projection_tile_lane.sv','screen_covariance_core #(.META_W','screen_covariance_core #(.COV3_FRAC_W(24),.META_W')]
    for name,old,new in changes:
        original=ROOT/name
        text=original.read_text()
        assert files.count(str(name))==1 and text.count(old)==1
        p=d/original.name
        freeze(p,text.replace(old,new));sources[str(p.relative_to(ROOT))]=sha(p)
        files[files.index(str(name))]=str(p)
    filelist=d/'sources.f';freeze(filelist,'\n'.join(files)+'\n')
    old_bench=old_dir/'tb_t08_bbox_pair.sv';bench=d/'tb_t08_precision_rgb.sv'
    text=old_bench.read_text().replace('tb_t08_bbox_pair','tb_t08_precision_rgb')
    guard='observed!=t08_precomputed||(t08_format==1&&observed==0)'
    assert text.count(guard)==1
    # This isolated build supports only raw and raw escape. Fail immediately
    # if any precomputed Q20 payload reaches the Q24 compute experiment.
    freeze(bench,text.replace(guard,'observed!=0||t08_precomputed!=0')
           .replace('endmodule','always @(posedge clk_i) if(rst_ni&&dut.attr_rsp_valid&&dut.attr_rsp_ready&&dut.compressed_precomputed)$fatal(1,"Q20 compact forbidden in Q24 experiment");\nendmodule'))
    for p in [bench,filelist]:sources[str(p.relative_to(ROOT))]=sha(p)
    w=WORK/OUT.name;w.mkdir(parents=True,exist_ok=True);exe=w/'simulation'
    cmd=previous['command'].copy()
    cmd[cmd.index('-f')+1]=str(filelist);cmd[cmd.index(str(old_bench))]=str(bench)
    cmd[cmd.index('--top-module')+1]=bench.stem;cmd[cmd.index('--Mdir')+1]=str(w)
    marker=d/'binary.json'
    if marker.exists():
        info=read(marker);assert info['sources']==sources and info['command']==cmd and sha(exe)==info['elf_sha256']
        return info
    run_logged(cmd,d/'build.log')
    info=dict(exe=str(exe),elf_sha256=sha(exe),sources=sources,command=cmd,world_fraction=24,view_fraction=24)
    save(marker,info);return info


def prepare(scene):
    d=OUT/'inputs'/scene;d.mkdir(parents=True,exist_ok=True)
    meta=read(PREVIOUS/'inputs'/scene/'manifest.json')
    native=read(BASE/'inputs/native'/scene/'manifest.json')
    original=Path(native['inputs']['ATTR']);assert sha(original)==native['input_sha256']['ATTR']
    plain=[];escaped=[]
    for gid in meta['gids']:
        words=slot(original,gid,9);record=sum(v<<(128*i) for i,v in enumerate(words))
        assert record.bit_length()<=1118
        packet=(record<<16)|RAW_HEADER
        plain.extend(f'{v:032x}\n' for v in words)
        escaped.extend(f'{(packet>>(128*i))&((1<<128)-1):032x}\n' for i in range(9))
    for name,lines in [('raw.memh',plain),('escape.memh',escaped)]:freeze(d/name,''.join(lines))
    return meta,d


def case(scene,fmt,meta,inputs,info):
    d=OUT/'real'/scene/f'f{fmt}';d.mkdir(parents=True,exist_ok=True)
    cmd=read(PREVIOUS/'real'/scene/'1/run.command.json')
    cmd[0]=info['exe']
    paths={'ATTR':inputs/('escape.memh' if fmt else 'raw.memh'),'FRAME':d/'state.memh','RGB':d/'rgb.memh','SORTED_TRACE':d/'sorted.txt'}
    cmd=['+'+k+'='+str(paths[k]) if (k:=a.partition('=')[0][1:]) in paths else a for a in cmd]
    cmd[cmd.index('+ATTR_FORMAT=1')]=f'+ATTR_FORMAT={fmt}'
    hashes={k:sha(Path(a.split('=',1)[1])) for a in cmd if (k:=a.partition('=')[0][1:]) in ('ATTR','MEAN','CAMERA')}
    assert hashes['MEAN']==meta['input_sha256']['mean.memh'] and hashes['CAMERA']==meta['input_sha256']['camera.memh']
    launch=dict(command=cmd,input_sha256=hashes,source_sha256=info['sources'],elf_sha256=info['elf_sha256'],meta=meta)
    marker=d/'launch.json'
    if marker.exists():
        assert read(marker)==launch
        ex=read(d/'run.execution.json');assert ex['exit_code']==0 and ex['log_sha256']==sha(d/'run.log')
    else:
        save(marker,launch);ex=run_logged(cmd,d/'run.log')
    log=(d/'run.log').read_text()
    assert 'PASS: tb_t08_precision_rgb' in log and 'error=00000000' in log
    counters=blocks(log);assert counters['REAL_T08']['format']==fmt and counters['REAL_T08']['requests']>0
    assert counters['REAL_T08']['precomputed']==counters['REAL_T08']['world_precomputed']==0
    assert counters['REAL_DMA_COUNTS']['attribute_beats']==9*counters['REAL_T08']['requests']
    return d,dict(format=fmt,cycles=counters['REAL_END_TO_END']['command_cycles'],execution=ex,counters=counters)


def run_scene(scene,info):
    meta,inputs=prepare(scene)
    semantic=read(PREVIOUS/'semantic/audit.json')
    old=next(r for r in semantic['results'] if r['scene']==scene)
    fp=PREVIOUS/'semantic'/scene/'raw_reference.png';assert sha(fp)==old['float_image_sha256']
    fps=np.asarray(Image.open(fp))
    rows=[]
    for fmt in (0,1):
        d,row=case(scene,fmt,meta,inputs,info)
        raw=bytes.fromhex((d/'rgb.memh').read_text());pixels=decode_rgb888(raw,meta['width'],meta['height'])
        Image.fromarray(pixels).save(d/'frame.png');assert Image.open(d/'frame.png').tobytes()==pixels.tobytes()
        assert sha(d/'sorted.txt')==sha(PREVIOUS/'real'/scene/'1/sorted.txt')
        delta=np.abs(pixels.astype(np.int16)-fps.astype(np.int16));mask=np.any(pixels,axis=2)|np.any(fps,axis=2)
        x,y=old['peak_pixel']['x'],old['peak_pixel']['y']
        row.update(image_sha256=sha(d/'frame.png'),rgb_sha256=sha(d/'rgb.memh'),state_sha256=sha(d/'state.memh'),
            internal_mae=float(delta.mean()),active_mae=float(delta[mask].mean()),max_error=int(delta.max()),
            old_peak_after=pixels[y,x].tolist(),old_peak_reference=fps[y,x].tolist(),
            pixels_above_32=int((delta.max(axis=2)>32).sum()))
        rows.append(row)
    for k in ('state_sha256','rgb_sha256','image_sha256'):assert rows[0][k]==rows[1][k],(scene,k)
    result=dict(scene=scene,rows=rows,old_float_metrics=old,inputs=meta,full_scene=False,signed_off=False)
    save(OUT/'real'/scene/'result.json',result);print(scene,rows[0]['old_peak_after'],rows[0]['max_error'],flush=True)
    return result


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        save(OUT/'status.json',dict(status='RUNNING',pid=os.getpid(),signed_off=False))
        try:
            info=build()
            with ThreadPoolExecutor(max_workers=3) as pool:rows=list(pool.map(lambda s:run_scene(s,info),SCENES))
            assert all(sha(ROOT/f)==h for f,h in info['sources'].items())
            save(OUT/'report.json',dict(status='RAW_AND_ESCAPE_RGB_COMPARED',results=rows,signed_off=False,
                 scope='Native hotspot subsets; Q24 diagnostic raw attributes and v1 raw escapes only. Compact Q24 DMA not exercised. Inspect quality and throughput before acceptance.'))
            save(OUT/'status.json',dict(status='RAW_AND_ESCAPE_RGB_COMPARED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False));raise

if __name__=='__main__':main()
