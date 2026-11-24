"""Four-format regression on the five complete models at frozen width 128."""
from concurrent.futures import ThreadPoolExecutor
import fcntl
from itertools import islice
import os
from pathlib import Path
import re
import sys
import time

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.run_t08_dual_precision import OUT as DUAL
from scripts.run_t08_q24_compact import encode_q24, MASK128
from scripts.scan_t08_small_covariances import make_products, shift
from scripts.run_t08_early_advance import OUT as EARLY
from scripts.run_t01_wsl_real import blocks
from scripts.run_t07_real import state_values
from scripts.read_rgb888_frame import decode_rgb888
from scripts.t08_common import BASE, WORK, SCENES, read, save, sha, run_logged

OUT = BASE/'dual_precision_full128_20261122'
LOCAL = WORK/OUT.name
FLOAT = ROOT/'experiments/t01_resume_20261025/fresh_float'


def build():
    prior = read(DUAL/'build/binary.json')
    assert all(sha(ROOT/p)==h for p,h in prior['sources'].items())
    full = read(EARLY/'build/full/1/binary.json')['command']
    cmd = prior['command'].copy()
    for name in ('TB_MAX_COUNT','TB_MAX_PIXELS'):
        prefix = '-D'+name+'='
        i, = [i for i,a in enumerate(cmd) if a.startswith(prefix)]
        cmd[i], = [a for a in full if a.startswith(prefix)]
    assert sorted(a for a in full if a.startswith('-D'))==sorted(a for a in cmd if a.startswith('-D'))
    LOCAL.mkdir(parents=True,exist_ok=True)
    cmd[cmd.index('--Mdir')+1] = str(LOCAL)
    marker = OUT/'build/binary.json'
    exe = LOCAL/'simulation'
    if marker.exists():
        info = read(marker)
        assert info['command']==cmd and info['sources']==prior['sources'] and sha(exe)==info['elf_sha256']
    else:
        run_logged(cmd,OUT/'build/build.log')
        info = dict(exe=str(exe),elf_sha256=sha(exe),command=cmd,sources=prior['sources'])
        save(marker,info)
    return info


def groups(stream):
    while lines:=list(islice(stream,9*2048)):
        assert len(lines)%9==0
        yield [sum(int(w,16)<<(128*j) for j,w in enumerate(lines[i:i+9])) for i in range(0,len(lines),9)]


def convert_chunk(records,old):
    # Reuse frozen v1 SH/mean/opacity. Recompute covariance from original quaternion and scales.
    q=np.array([[(r>>(949+22*k))&0x3fffff for k in (3,2,1,0)] for r in records],dtype=np.int64)
    q=(q^(1<<21))-(1<<21)
    scale=np.array([[(r>>(877+24*k))&0xffffff for k in (2,1,0)] for r in records],dtype=np.int64)
    use=np.array([not bool(p&0x400) for p in old])
    cov=np.zeros((len(records),6),dtype=np.int64)
    if use.any():
        products=make_products(q[use],scale[use])[:,[0,0,0,1,1,2],[0,1,2,1,2,2]]
        cov[use]=shift(products,16)
        cov20=shift(products,20)
        # Verify all six source coefficients and original record alignment.
        stored=np.array([[(p>>(110+24*j))&0xffffff for j in range(6)] for p in old if not (p&0x400)])
        assert np.array_equal(stored,cov20&0xffffff)
    use &= np.all((cov>=-(1<<23)) & (cov<(1<<23)),axis=1)
    encoded=[]
    for i,(r,p) in enumerate(zip(records,old,strict=True)):
        assert (p&0x3ff)==0x1c8 and r.bit_length()<=1118
        if p&0x400:
            assert (p&0xffff)==0x3dc8 and p>>16==r
        if use[i]:
            v=(p&~(((1<<144)-1)<<110)&~0x300)|0x200
            for j,x in enumerate(cov[i]):
                v|=(int(x)&0xffffff)<<(110+24*j)
        else:
            v=(r<<16)|0x3ec8
        encoded.append(v)
    for i in {0,len(records)-1}:
        assert encoded[i]==encode_q24(records[i])[0]
    return encoded


def encode(scene,raw,old):
    folder=OUT/'inputs'/scene
    folder.mkdir(parents=True,exist_ok=True)
    dest=folder/'v2.memh'
    marker=folder/'manifest.json'
    parent=read(old.parent/'manifest.json')
    source=sha(raw)
    assert source==parent['source_sha256'] and sha(old)==parent['encoded_sha256']
    code={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__),ROOT/'scripts/scan_t08_small_covariances.py',
          ROOT/'scripts/run_t08_q24_compact.py',ROOT/'model/io/t08_precompute.py',ROOT/'model/io/t08_attribute_codec.py']}
    provenance=dict(raw_sha256=source,v1_sha256=parent['encoded_sha256'],encoder_sources=code)
    if marker.exists():
        meta=read(marker)
        assert meta['provenance']==provenance and meta['encoded_sha256']==sha(dest)
        return dest
    partial=folder/f'v2.{time.time_ns()}.partial'
    count=0
    with raw.open('rb') as a,old.open('rb') as b,partial.open('w',buffering=1<<20) as out:
        for records,prior in zip(groups(a),groups(b),strict=True):
            packed=convert_chunk(records,prior)
            out.writelines(''.join(f'{(v>>(128*j))&MASK128:032x}\n' for j in range(9)) for v in packed)
            count+=len(packed)
    assert count==parent['records'] and sha(raw)==source and sha(old)==parent['encoded_sha256']
    if dest.exists():
        assert sha(dest)==sha(partial)
    else:
        partial.rename(dest)
    save(marker,dict(provenance=provenance,records=count,encoded_sha256=sha(dest)))
    return dest


def case(scene,fmt,info,attrs,attr_hash):
    old=EARLY/'real/full/1'/scene/f'f{int(fmt in (1,2))}'
    baseline=read(old/'result.json')
    cmd=read(old/'run.command.json')
    cmd[0]=info['exe']
    cmd[cmd.index(f"+ATTR_FORMAT={baseline['format']}")]=f'+ATTR_FORMAT={fmt}'
    d=OUT/'real'/scene/f'f{fmt}'
    d.mkdir(parents=True,exist_ok=True)
    paths=dict(ATTR=attrs,FRAME=d/'state.memh',RGB=d/'rgb.memh',SORTED_TRACE=d/'sorted.txt')
    cmd=['+'+k+'='+str(paths[k]) if (k:=a.partition('=')[0][1:]) in paths else a for a in cmd]
    inputs={k:sha(a.partition('=')[2]) for a in cmd if (k:=a.partition('=')[0][1:]) in ('ATTR','MEAN','CAMERA')}
    assert inputs=={**baseline['input_sha256'],'ATTR':attr_hash}
    launch=dict(command=cmd,elf_sha256=info['elf_sha256'],input_sha256=inputs)
    marker=d/'launch.json'
    if marker.exists():
        assert read(marker)==launch
    else:
        save(marker,launch)
    ex=d/'run.execution.json'
    if ex.exists() and read(ex)['exit_code']==0:
        assert read(ex)['log_sha256']==sha(d/'run.log')
    else:
        run_logged(cmd,d/'run.log')
    log=(d/'run.log').read_text()
    assert 'PASS: tb_t08_dual_precision' in log and 'error=00000000' in log
    c=blocks(log)
    r=c['REAL_T08']
    assert r['format']==fmt and r['requests']==baseline['counters']['REAL_T08']['requests']
    assert r['world_precomputed']==r['precomputed'] and (r['precomputed']>0)==(fmt in (1,2))
    assert c['REAL_QSU']['enabled']==1 and c['REAL_ADDRESS_LAYOUT']['disjoint']==1
    assert sha(d/'sorted.txt')==baseline['outputs']['sorted.txt']
    oracle=next(row for row in read(FLOAT/'audit.json')['results'] if row['scene']==scene)
    fp=FLOAT/scene/'float_floor_0.30078125_jac_clamp.png'
    assert sha(fp)==oracle['float_sha256'] and inputs['CAMERA']==oracle['input_sha256']['camera.memh']
    assert inputs['MEAN']==oracle['input_sha256']['mean.memh'] and oracle['width']==128
    rgb=decode_rgb888(bytes.fromhex((d/'rgb.memh').read_text()),oracle['width'],oracle['height'])
    Image.fromarray(rgb).save(d/'frame.png')
    assert Image.open(d/'frame.png').tobytes()==rgb.tobytes()
    diff=np.abs(rgb.astype(np.int16)-np.asarray(Image.open(fp).convert('RGB')).astype(np.int16))
    if fmt<2:
        assert sha(d/'rgb.memh')==baseline['outputs']['rgb.memh'] and float(diff.mean())==oracle['mae']
    row=dict(scene=scene,format=fmt,width=oracle['width'],height=oracle['height'],gaussians=read(BASE/'inputs/native'/scene/'manifest.json')['gaussians'],
             counters=c,command_cycles=c['REAL_END_TO_END']['command_cycles'],bbox_skips=int(re.search(r'^BBOX_SKIPS (\d+)$',log,re.M)[1]),
             reference_sha256=sha(fp),internal_float_mae=float(diff.mean()),internal_float_max=int(diff.max()),
             hashes={name:sha(d/name) for name in ('rgb.memh','state.memh','sorted.txt','frame.png','launch.json')},execution=read(ex))
    save(d/'result.json',row)
    return row


def compare_states(a,b):
    first,second=state_values(a,1),state_values(b,1)
    assert len(first)==len(second)
    assert all(x==y and (t==u or max(t,u)<=7) for (x,t),(y,u) in zip(first,second))
    return sum(t!=u for (_,t),(_,u) in zip(first,second))


def run_scene(scene,info):
    old=EARLY/'real/full/1'/scene
    attrs=[Path(next(a[6:] for a in read(old/f'f{f}'/'run.command.json') if a.startswith('+ATTR='))) for f in (0,1)]
    v2=encode(scene,*attrs)
    budget=read(BASE/'q24_slot_budget_20261122'/scene/'result.json')
    compact_hash=read(v2.parent/'manifest.json')['encoded_sha256']
    rows={}
    for fmt,source in [(3,attrs[0]),(2,v2),(1,attrs[1]),(0,attrs[0])]:
        digest=compact_hash if fmt==2 else read(old/f'f{int(fmt==1)}'/'result.json')['input_sha256']['ATTR']
        rows[fmt]=case(scene,fmt,info,source,digest)
    d=OUT/'real'/scene
    state_differences={}
    for f,ref in [(2,d/'f3'),(1,old/'f1'),(0,old/'f0')]:
        assert sha(ref/'rgb.memh')==rows[f]['hashes']['rgb.memh']
        state_differences[f]=compare_states(d/f'f{f}'/'state.memh',ref/'state.memh')
    assert 16*rows[2]['counters']['REAL_DMA_COUNTS']['attribute_beats']==budget['q24_projected_bytes']
    result=dict(scene=scene,rows=rows,terminal_t_differences=state_differences,full_model=True,signed_off=False)
    save(d/'comparison.json',result)
    return result


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            save(OUT/'status.json',dict(status='BUILDING',pid=os.getpid(),signed_off=False))
            binary=build()
            save(OUT/'status.json',dict(status='ENCODING_AND_RUNNING',pid=os.getpid(),signed_off=False))
            with ThreadPoolExecutor(max_workers=3) as pool:
                results=list(pool.map(lambda s:run_scene(s,binary),SCENES))
            assert all(sha(ROOT/p)==h for p,h in binary['sources'].items())
            save(OUT/'report.json',dict(results=results,script_sha256=sha(__file__),signed_off=False,
                 scope='Five complete models, width128, G/legacy-ideal. Review measured internal error and costs, formal GT and native throughput open.'))
            save(OUT/'status.json',dict(status='FULL128_COMPARED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise
