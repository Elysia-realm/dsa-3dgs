"""Native-resolution full Train/Truck pairs for the single root-precount change."""
from concurrent.futures import ThreadPoolExecutor
import fcntl
import os
from pathlib import Path
import sys

from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_qsu_root_precount import OUT as CANDIDATE
from scripts.run_t08_dual_full import OUT as FULL
from scripts.run_t08_q24_compact import edit,freeze
from scripts.t08_common import BASE,WORK,MAX_COUNT,MAX_PIXELS,read,save,sha,run_logged
from scripts.run_t01_wsl_real import blocks
from scripts.read_rgb888_frame import decode_rgb888

OUT=BASE/'qsu_root_native_full_20261122'
LOCAL=WORK/OUT.name
SCENES=('train','truck')


def build(enabled):
    old=CANDIDATE if enabled else FULL
    orig=read(old/'build/binary.json')
    sources=orig['sources'].copy()
    assert all(sha(ROOT/p)==h for p,h in sources.items())
    d=OUT/'build'/str(enabled)
    w=LOCAL/str(enabled)
    d.mkdir(parents=True,exist_ok=True)
    w.mkdir(parents=True,exist_ok=True)
    cmd=orig['command'].copy()
    index=cmd.index('--top-module')+1
    oldbench=Path(next(a for a in cmd if a.endswith('/'+cmd[index]+'.sv')))
    bench=d/'tb_t08_native_root.sv'
    obs=ROOT/'verification/rtl/t08_native_bus_observer.svh'
    body=oldbench.read_text().replace(oldbench.stem,bench.stem)
    body=edit(body,'endmodule',f'`include "{obs.relative_to(ROOT)}"\nendmodule')
    needle=f'$display("PASS: {bench.stem}");'
    freeze(bench,edit(body,needle,'''if(t08_beats!=measure_camera_beats+measure_mean_beats+measure_attr_beats+
            measure_qsu_reads+measure_qsu_writes+state_reads+rgb_read_count+state_writes+rgb_write_beats)
          $fatal(1,"data-bus counters disagree at DONE");
        $display("REAL_SHARED_BUS beats=%0d overlap_cycles=%0d excess_beats=%0d peak_queue=%0d final_queue=%0d",
          t08_beats,t08_overlap,t08_excess,t08_peak_queue,t08_shared_queue);
        '''+needle))
    cmd[index]=bench.stem
    cmd[cmd.index(str(oldbench))]=str(bench)
    cmd[cmd.index('--Mdir')+1]=str(w)
    for name,size in [('TB_MAX_COUNT',MAX_COUNT),('TB_MAX_PIXELS',MAX_PIXELS)]:
        i,=[i for i,arg in enumerate(cmd) if arg.startswith('-D'+name+'=')]
        cmd[i]=f'-D{name}={size}'
    for p in [bench,obs]:
        sources[str(p.relative_to(ROOT))]=sha(p)
    marker=d/'binary.json'
    exe=w/'simulation'
    if marker.exists():
        info=read(marker)
        assert info['command']==cmd and info['sources']==sources and info['elf_sha256']==sha(exe)
    else:
        run_logged(cmd,d/'build.log')
        info=dict(exe=str(exe),sources=sources,elf_sha256=sha(exe),command=cmd)
        save(marker,info)
    return info


def case(scene,enabled,info):
    d=OUT/'real'/scene/str(enabled)
    d.mkdir(parents=True,exist_ok=True)
    ref=FULL/'real'/scene/'f2'
    base=read(ref/'result.json')
    old=read(ref/'launch.json')
    assert sha(ref/'launch.json')==base['hashes']['launch.json']
    meta=read(BASE/'inputs/native'/scene/'manifest.json')
    assert meta['full_scene'] and meta['gaussians']==base['gaussians']
    assert sha(meta['camera_source'])==meta['camera_source_sha256'] and sha(meta['ply'])==meta['ply_sha256']
    assert meta['input_sha256']['MEAN']==old['input_sha256']['MEAN']
    cmd=old['command'].copy()
    cmd[0]=info['exe']
    paths=dict(CAMERA=meta['inputs']['CAMERA'],FRAME=d/'state.memh',RGB=d/'rgb.memh',SORTED_TRACE=d/'sorted.txt')
    cmd=['+'+k+'='+str(paths[k]) if (k:=a.partition('=')[0][1:]) in paths else a for a in cmd]
    cmd.append(f"+LABEL={scene}_camera{meta['camera_index']}")
    inputs={k:sha(a.partition('=')[2]) for a in cmd if (k:=a.partition('=')[0][1:]) in ('MEAN','ATTR','CAMERA')}
    assert inputs=={**old['input_sha256'],'CAMERA':meta['input_sha256']['CAMERA']}
    launch=dict(command=cmd,inputs=inputs,elf_sha256=info['elf_sha256'],meta=meta)
    marker=d/'launch.json'
    if marker.exists():
        assert read(marker)==launch
    else:
        save(marker,launch)
    ex=d/'run.execution.json'
    if ex.exists() and read(ex)['exit_code']==0:
        assert sha(d/'run.log')==read(ex)['log_sha256']
    else:
        run_logged(cmd,d/'run.log')
    log=(d/'run.log').read_text()
    assert 'PASS: tb_t08_native_root' in log and 'error=00000000' in log
    c=blocks(log)
    assert c['REAL_ADDRESS_LAYOUT']['disjoint']==1 and c['REAL_QSU']['enabled']==1
    assert c['REAL_T08']==base['counters']['REAL_T08'] and c['REAL_T08']['world_precomputed']>0
    assert sha(d/'sorted.txt')==base['hashes']['sorted.txt']
    expected=read((CANDIDATE/'real'/scene if enabled else ref)/'result.json')['counters']['REAL_QSU']
    for key in ('input','leaves','partitions','axi_reads','axi_writes','peak'):
        assert c['REAL_QSU'][key]==expected[key],(scene,enabled,key)
    rgb=decode_rgb888(bytes.fromhex((d/'rgb.memh').read_text()),meta['width'],meta['height'])
    Image.fromarray(rgb).save(d/'frame.png')
    assert Image.open(d/'frame.png').tobytes()==rgb.tobytes()
    cycles=c['REAL_END_TO_END']['command_cycles']
    beats=c['REAL_SHARED_BUS']['beats']
    result=dict(scene=scene,enabled=enabled,full_model=True,meta=meta,counters=c,execution=read(ex),
                cycles=cycles,estimated_fps_at_assumed_200mhz=200e6/cycles,actual_data_bus_bytes=16*beats,
                required_shared_gbps_at_30fps=16*beats*30/1e9,
                hashes={f:sha(d/f) for f in ('sorted.txt','state.memh','rgb.memh','frame.png','launch.json')},
                signed_off=False)
    save(d/'result.json',result)
    return result


def compare(scene,off,on):
    for name in ('sorted.txt','rgb.memh','frame.png'):
        assert off['hashes'][name]==on['hashes'][name]
    changes=0
    n=0
    with (OUT/'real'/scene/'0/state.memh').open('rb') as a,(OUT/'real'/scene/'1/state.memh').open('rb') as b:
        for x,y in zip(a,b,strict=True):
            n+=1
            if x!=y:
                def fields(word):
                    v=int(word,16)
                    return (v&((1<<39)-1),(v>>39)&65535) if (v>>55)&65535==1 else (0,65535)
                p,t=fields(x)
                q,u=fields(y)
                assert p==q and (t==u or max(t,u)<=7),(scene,n)
                changes+=int(t!=u)
    assert n==on['meta']['width']*on['meta']['height']
    r=dict(scene=scene,off=off,on=on,cycle_delta=on['cycles']-off['cycles'],terminal_t_differences=changes)
    save(OUT/'real'/scene/'comparison.json',r)
    return r


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            save(OUT/'status.json',dict(status='BUILDING',pid=os.getpid(),signed_off=False))
            info=[build(mode) for mode in (0,1)]
            save(OUT/'status.json',dict(status='RUNNING_FOUR_NATIVE_FRAMES',pid=os.getpid(),signed_off=False))
            with ThreadPoolExecutor(max_workers=4) as pool:
                jobs={(s,m):pool.submit(case,s,m,info[m]) for s in SCENES for m in (0,1)}
                rows=[compare(s,jobs[s,0].result(),jobs[s,1].result()) for s in SCENES]
            assert all(sha(ROOT/p)==h for binary in info for p,h in binary['sources'].items())
            save(OUT/'report.json',dict(results=rows,script_sha256=sha(__file__),signed_off=False,
                 scope='Full native Train and Truck only. Matched Q24 compact frames. Passive bus demand, no physical DDR timing model or official per-view GT.'))
            save(OUT/'status.json',dict(status='TWO_NATIVE_PAIRS_CHECKED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise
