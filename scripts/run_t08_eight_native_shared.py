"""Native Train/Truck, full-Gaussian Q24 raw vs eight-beat compact on the shared LPDDR4 bridge."""
from concurrent.futures import ThreadPoolExecutor
import fcntl
import os
from pathlib import Path
import re
import sys
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_eight_beat_header import OUT as EIGHT
from scripts.run_t08_shared_ddr import OUT as SHARED,CFG
from scripts.run_t08_terminated_blocks import OUT as IDEAL
from scripts.run_t08_qsu_native_full import OUT as NATIVE
from scripts.run_t08_q24_compact import freeze,edit
from scripts.run_t01_wsl_real import blocks
from scripts.read_rgb888_frame import decode_rgb888
from scripts.t08_common import BASE,WORK,read,save,sha,run_logged

OUT=BASE/'eight_beat_native_shared_20261123'
LOCAL=WORK/OUT.name


def build():
    prior=read(EIGHT/'build/binary.json')
    assert all(sha(ROOT/p)==h for p,h in prior['sources'].items())
    sources=prior['sources'].copy()
    cmd=prior['command'].copy()
    d=OUT/'build'
    d.mkdir(parents=True,exist_ok=True)
    LOCAL.mkdir(parents=True,exist_ok=True)
    old=EIGHT/'build/tb_t08_eight_beat_header.sv'
    bench=d/'tb_t08_native_eight_shared.sv'
    text=old.read_text().replace(old.stem,bench.stem)
    text=edit(text,'axi_cycle=0,frame_mode=3,max_timeout=1000000;', 'frame_mode=3;longint unsigned axi_cycle=0,max_timeout=1000000;')
    text=edit(text,'integer b_due[','longint unsigned b_due[')
    text=edit(text,'initial begin integer timeout,i,frame_file','initial begin longint unsigned timeout;integer i,frame_file')
    old_scratch=SHARED/'build/scratch.svh'
    sc=edit(old_scratch.read_text(),'integer qsu_b_time[','longint unsigned qsu_b_time[')
    sc=edit(sc,'qsu_read_delay=0,qsu_tick=0;','qsu_read_delay=0;longint unsigned qsu_tick=0;')
    scratch=d/'scratch.svh'
    freeze(scratch,sc)
    freeze(bench,edit(text,str(old_scratch.relative_to(ROOT)),str(scratch.relative_to(ROOT))))
    for p in (scratch,bench):sources[str(p)]=sha(p)
    cmd[cmd.index(str(old))]=str(bench)
    cmd[cmd.index('--top-module')+1]=bench.stem
    cmd[cmd.index('--Mdir')+1]=str(LOCAL)
    marker=d/'binary.json'
    exe=LOCAL/'simulation'
    if marker.exists():
        info=read(marker)
        assert info['sources']==sources and info['command']==cmd and sha(exe)==info['elf_sha256']
    else:
        run_logged(cmd,d/'build.log')
        info=dict(exe=str(exe),sources=sources,command=cmd,elf_sha256=sha(exe))
        save(marker,info)
    return info


def terminal_check(current,golden):
    differences=0
    with current.open('rb') as a,golden.open('rb') as b:
        for x,y in zip(a,b,strict=True):
            if x==y:continue
            v,w=int(x,16),int(y,16)
            assert (v>>55)&65535==(w>>55)&65535==1 and v%(1<<39)==w%(1<<39)
            assert v>>118==w>>118==0 and max((v>>39)&65535,(w>>39)&65535)<=7
            differences+=1
    return differences


def case(scene,fmt,info,pilot=False):
    d=OUT/('pilot' if pilot else 'native')/scene/f'f{fmt}'
    d.mkdir(parents=True,exist_ok=True)
    if pilot:
        ref=EIGHT/'subset'/scene if fmt==2 else SHARED/'subset'/scene/'f3_t1'
    else:
        ref=IDEAL/'native'/scene
    baseline=read(ref/'result.json')
    assert sha(ref/'launch.json')==baseline['hashes']['launch.json']
    old=read(ref/'launch.json')
    cmd=old['command'].copy()
    cmd[0]=info['exe']
    meta=read(BASE/'inputs/native'/scene/'manifest.json')
    cmd[cmd.index(next(a for a in cmd if a.startswith('+ATTR_FORMAT=')))]=f'+ATTR_FORMAT={fmt}'
    if not pilot:
        cmd[cmd.index(next(a for a in cmd if a.startswith('+MAX_TIMEOUT='))) ]='+MAX_TIMEOUT=4000000000'
        assert '+LPDDR_TIMED' not in cmd
        cmd+=['+LPDDR_TIMED',f'+MODEL_CFG={CFG}',f'+MODEL_STATS={d}/model.stats']
    paths=dict(FRAME=d/'state.memh',RGB=d/'rgb.memh',SORTED_TRACE=d/'sorted.txt',MODEL_STATS=d/'model.stats')
    if not pilot and fmt==3:paths['ATTR']=Path(meta['inputs']['ATTR'])
    cmd=['+'+k+'='+str(paths[k]) if (k:=a.partition('=')[0][1:]) in paths else a for a in cmd]
    inputs={k:sha(a.partition('=')[2]) for a in cmd if (k:=a.partition('=')[0][1:]) in ('ATTR','MEAN','CAMERA')}
    expected=dict(old.get('inputs') or old['input_sha256'])
    if not pilot:
        assert meta['full_scene'] and sha(meta['ply'])==meta['ply_sha256']
        assert expected['CAMERA']==meta['input_sha256']['CAMERA'] and expected['MEAN']==meta['input_sha256']['MEAN']
        if fmt==3:expected['ATTR']=meta['input_sha256']['ATTR']
    assert inputs==expected
    launch=dict(command=cmd,inputs=inputs,elf_sha256=info['elf_sha256'],baseline_sha256=sha(ref/'result.json'))
    marker=d/'launch.json'
    if marker.exists():assert read(marker)==launch
    else:save(marker,launch)
    ex=d/'run.execution.json'
    if ex.exists() and read(ex)['exit_code']==0:assert sha(d/'run.log')==read(ex)['log_sha256']
    else:run_logged(cmd,d/'run.log')
    log=(d/'run.log').read_text()
    assert 'PASS: tb_t08_native_eight_shared' in log and 'error=00000000' in log
    c=blocks(log)
    assert c['REAL_ADDRESS_LAYOUT']['disjoint']==1 and c['REAL_QSU']['enabled']==1
    assert c['REAL_T08']['format']==fmt and (c['REAL_T08']['world_precomputed']>0)==(fmt==2)
    stats=(d/'model.stats').read_text()
    assert int(re.search(r'ramulator\.incoming_requests\s+(\d+)',stats)[1])==c['REAL_LPDDR']['lines']
    assert c['REAL_LPDDR']['qsu_b']==c['REAL_DMA_COUNTS']['qsu_write_bursts'] and c['REAL_LPDDR']['out_b']==c['REAL_DMA_COUNTS']['output_write_bursts']
    if pilot:
        for section in ('REAL_LPDDR','REAL_END_TO_END','REAL_T08','REAL_SHARED_BUS','REAL_DMA_COUNTS'):
            assert c[section]==baseline['counters'][section],(fmt,section)
    else:
        low=read((EIGHT/'full128'/scene/'result.json') if fmt==2 else (SHARED/'full128'/scene/'f3_t1/result.json'))
        assert c['REAL_T08']==low['counters']['REAL_T08']
        for key in ('attribute_beats','attribute_bursts'):
            assert c['REAL_DMA_COUNTS'][key]==low['counters']['REAL_DMA_COUNTS'][key]
    cam=Path(next(a[8:] for a in cmd if a.startswith('+CAMERA=')))
    words=cam.read_text().split()
    width,height=[int(words[i],16) for i in (25,26)]
    rgb=decode_rgb888(bytes.fromhex((d/'rgb.memh').read_text()),width,height)
    Image.fromarray(rgb).save(d/'frame.png')
    assert Image.open(d/'frame.png').tobytes()==rgb.tobytes()
    for name in ('frame.png','rgb.memh','sorted.txt'):
        assert sha(d/name)==baseline['hashes'][name],(scene,fmt,name)
    assert sha(ref/'state.memh')==baseline['hashes']['state.memh']
    changes=terminal_check(d/'state.memh',ref/'state.memh')
    samples=None
    if not pilot:
        g=read(NATIVE/'reference'/scene/'samples.json')
        assert (width,height)==(g['width'],g['height']) and g['camera']==meta['camera_index']
        assert g['inputs'][str(cam)]==inputs['CAMERA'] and g['inputs'][meta['ply']]==meta['ply_sha256']
        delta=np.array([rgb[v['y'],v['x']].astype(int)-v['rgb'] for v in g['samples']])
        assert delta.shape==(81,3)
        samples=dict(mae_rgb8=float(np.abs(delta).mean()),max_channel_error=int(np.abs(delta).max()))
    cycles=c['REAL_END_TO_END']['command_cycles']
    row=dict(scene=scene,camera=meta['camera_index'],full_model=not pilot,width=width,height=height,
             fmt=fmt,cycles=cycles,estimated_fps_at_assumed_200mhz=200e6/cycles,counters=c,
             terminal_word_differences=changes,sample_comparison=samples,execution=read(ex),
             hashes={n:sha(d/n) for n in ('model.stats','frame.png','rgb.memh','sorted.txt','state.memh','launch.json')},
             signed_off=False)
    save(d/'result.json',row)
    return row


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            save(OUT/'status.json',dict(status='BUILD_AND_CHECK_CLOCKS',pid=os.getpid(),signed_off=False))
            info=build()
            pilot=[case('train',fmt,info,True) for fmt in (3,2)]
            save(OUT/'pilot_report.json',dict(results=pilot,signed_off=False))
            save(OUT/'status.json',dict(status='RUNNING_NATIVE_SHARED_PAIRS',pid=os.getpid(),signed_off=False))
            with ThreadPoolExecutor(max_workers=4) as pool:
                jobs=[pool.submit(case,s,fmt,info) for s in ('train','truck') for fmt in (3,2)]
                rows=[job.result() for job in jobs]
            assert all(sha(ROOT/p)==h for p,h in info['sources'].items())
            save(OUT/'report.json',dict(results=rows,script_sha256=sha(__file__),signed_off=False,
                 scope='Q24 raw and eight-beat compact under shared LPDDR4 timing, two native complete models, G; no official GT.'))
            save(OUT/'status.json',dict(status='NATIVE_SHARED_PAIRS_COMPARED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise
