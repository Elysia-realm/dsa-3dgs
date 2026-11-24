"""Complete models for the frozen child-precount H candidate, excluding Kitchen/Garden.

Compiles from a pinned source tree; concurrent new RTL work cannot relabel it.
"""
import json,os,re,shutil,subprocess,sys,traceback,time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t06_perf_optimization import SCENES,read,save
from scripts.collect_t06_performance_baseline import sha
from scripts.prepare_t06_full_render import attribute_words
from scripts.build_full_frame_batch_index import pack_mean_records,rtl_depth_q16
from scripts.read_rgb888_frame import decode_rgb888
from model.io.scene import iter_gaussian_batches,open_ply_vertices
BASE=ROOT/'experiments/t06_full_precount_mem_20261022';OLD=ROOT/'experiments/t06_precount_mem_20261022/real'
SNAP=OLD/'source_snapshot';EXE=ROOT/'tmp/verilator_t06_precount_full_20261022/t06_perf.exe'
def prepare():
    for n,cam_id in SCENES.items():
        dest=BASE/n;dest.mkdir(parents=True,exist_ok=True)
        if (dest/'manifest.json').exists():
            for f,h in read(dest/'manifest.json')['input_sha256'].items():assert sha(dest/f)==h
            continue
        if n in SCENES:
            src=ROOT/'experiments/t06_full_f_20261019'/n
            for f in ['camera.memh','mean.memh','attribute.memh','expected_sorted.txt','manifest.json']:
                if not (dest/f).exists():
                    if f.endswith('.memh'):os.link(src/f,dest/f)
                    else:shutil.copy2(src/f,dest/f)
            continue
        ply=ROOT/'data'/n/'point_cloud/iteration_30000/point_cloud.ply';head,_=open_ply_vertices(ply);count=head.vertex_count
        cam=[int(v,16) for v in (OLD/'subset'/n/'camera.memh').read_text().split()];cam[27]=(0x47534301<<32)|count
        signed=lambda v:v-(1<<64) if v>>63 else v
        rotation=np.array([signed(v) for v in cam[6:9]]);translation=signed(cam[11]);depths=[];visible=[]
        (dest/'camera.memh').write_text(''.join(f'{v:016x}\n' for v in cam))
        with (dest/'mean.memh').open('w') as mf,(dest/'attribute.memh').open('w') as af:
            for b in iter_gaussian_batches(ply,batch_size=16384,include_sh=True):
                gids=np.arange(b.start,b.stop,dtype=np.uint32);mw=pack_mean_records(gids,b.mean);aw=attribute_words(b)
                mf.writelines(f'{int(hi):016x}{int(lo):016x}\n' for lo,hi in mw)
                af.writelines(f'{int(row[k+1]):016x}{int(row[k]):016x}\n' for row in aw for k in range(0,18,2))
                depth,overflow=rtl_depth_q16(b.mean,rotation,translation);assert not overflow.any()
                depths.append(depth);visible.append((depth>=cam[19])&(depth<=cam[20]))
        depth=np.concatenate(depths);ids=np.flatnonzero(np.concatenate(visible));order=ids[np.argsort(depth[ids],kind='stable')]
        (dest/'expected_sorted.txt').write_text(''.join(f'{int(depth[i])} {int(i)} {int(i)}\n' for i in order))
        save(dest/'manifest.json',dict(scene=n,camera_index=cam_id,gaussians=count,visible=len(ids),full_scene=True,width=cam[25],height=cam[26],
          software_preprocessing='complete original PLY order, fixed-point encoding; no CPU pivots/batches for production',source_ply_sha256=sha(ply),
          input_sha256={p.name:sha(p) for p in dest.glob('*.memh')},oracle_sha256=sha(dest/'expected_sorted.txt')))
        print('PREPARED FULL',n,count,flush=True)
def build():
    source=read(OLD/'build/H/sources.json')
    source.update({p.relative_to(SNAP).as_posix():sha(p) for p in (SNAP/'rtl').rglob('*.svh')})
    for f,h in source.items():assert sha(SNAP/f)==h
    dest=BASE/'build';dest.mkdir(exist_ok=True)
    if EXE.exists() and (dest/'sources.json').exists():assert read(dest/'sources.json')==source;return
    cmd=read(OLD/'build/H/command.json')
    cmd[-1]=cmd[-1].replace('cd /d/3DGS &&','cd /d/3DGS/experiments/t06_precount_mem_20261022/real/source_snapshot &&').replace('-DTB_MAX_COUNT=512','-DTB_MAX_COUNT=7000000').replace('tmp/verilator_t06_precount_mem_20261022_H','/d/3DGS/tmp/verilator_t06_precount_full_20261022')
    env=os.environ.copy();env.update(MSYSTEM='UCRT64',CHERE_INVOKING='1');save(dest/'command.json',cmd)
    with (dest/'build.log').open('w') as log:r=subprocess.run(cmd,cwd=SNAP,env=env,stdout=log,stderr=subprocess.STDOUT)
    assert r.returncode==0,(dest/'build.log').read_text()[-2000:]
    for f,h in source.items():assert sha(SNAP/f)==h
    save(dest/'sources.json',source);save(dest/'binary.json',dict(sha256=sha(EXE)));print('BUILT FULL PRECOUNT',flush=True)
def run(case):
    n,role=case;folder=BASE/n;dest=folder/role;dest.mkdir(exist_ok=True);m=read(folder/'manifest.json')
    src=read(BASE/'build/sources.json') if role=='H' else read(ROOT/'experiments/t06_20261018/full_render/oracle_build/sources.json')
    if (dest/'result.json').exists():
        r=read(dest/'result.json');assert r['source_sha256']==src;assert sha(dest/'frame.rgb')==r['rgb_sha256'];return
    for f,h in src.items():assert sha((SNAP if role=='H' else ROOT/'experiments/t06_perf_20261018/selection_snapshot')/f)==h,'source not pinned '+f
    if role=='oracle':
        old=ROOT/'experiments/t06_full_f_20261019'/n/'oracle'
        for f in ['result.json','frame.rgb','frame.png','run.log','command.json']:shutil.copy2(old/f,dest/f)
        save(dest/'reuse.json',dict(from_directory=str(old),reason='identical encoded input and renderer source; legacy reference only'))
        return
    assert sha(EXE)==read(BASE/'build/binary.json')['sha256']
    exe=EXE if role=='H' else ROOT/'tmp/verilator_t06_memory_oracle/t06_oracle.exe'
    cmd=[str(exe),f'+MEAN={(folder/"mean.memh").as_posix()}',f'+ATTR={(folder/"attribute.memh").as_posix()}',
      f'+CAMERA={(folder/"camera.memh").as_posix()}',f'+FRAME={(dest/"state.memh").as_posix()}',f'+RGB={(dest/"rgb.memh").as_posix()}',
      '+FRAME_MODE=0','+READ_LATENCY=0','+READ_GAP=0','+READY_PERIOD=1','+READY_LOW=0','+WRITE_RESPONSE_LATENCY=2','+MAX_TIMEOUT=2000000000']
    cmd+=['+AUTO_QSU',f'+SORTED_TRACE={(dest/"sorted.txt").as_posix()}'] if role=='H' else [f'+ORACLE={(folder/"expected_sorted.txt").as_posix()}']
    save(dest/'command.json',cmd);env=os.environ.copy();env['PATH']=r'D:\Tools\msys64\ucrt64\bin;'+env['PATH'];start=time.monotonic()
    try:
        with (dest/'run.log').open('w') as log:r=subprocess.run(cmd,cwd=SNAP,env=env,stdout=log,stderr=subprocess.STDOUT)
    except OSError as e:
        save(dest/'environment_failure.json',dict(error=str(e),winerror=getattr(e,'winerror',None),action='No executable renaming or security-policy bypass'));raise
    log=(dest/'run.log').read_text();assert r.returncode==0 and 'PASS:' in log,log[-3000:]
    assert 'error=00000000' in log and 'disjoint=1' in log
    raw=bytes(int(v,16) for v in (dest/'rgb.memh').read_text().split())
    (dest/'frame.rgb').write_bytes(raw);Image.fromarray(decode_rgb888(raw,m['width'],m['height'])).save(dest/'frame.png')
    if role=='H':assert (dest/'sorted.txt').read_bytes()==(folder/'expected_sorted.txt').read_bytes()
    for f,h in src.items():assert sha((SNAP if role=='H' else ROOT/'experiments/t06_perf_20261018/selection_snapshot')/f)==h
    save(dest/'result.json',dict(status='PASS_DATAPATH_PENDING_PAIR' if role=='H' else 'PASS_ORACLE',scene=n,full_scene=True,source_sha256=src,rgb_sha256=sha(dest/'frame.rgb'),seconds=time.monotonic()-start))
    print('PASS FULL',n,role,flush=True)
def main():
    BASE.mkdir(parents=True,exist_ok=True);save(BASE/'status.json',dict(status='PREPARING_AND_BUILDING',pid=os.getpid(),signed_off=False))
    assert read(OLD/'report.json')['status']=='PASS_SUBSET_NOT_SIGNOFF'
    for gate in ['units','faults','recovery','compat','synthesis']:
        assert read(OLD.parent/gate/'report.json')['status']=='PASS',gate
    build();prepare();save(BASE/'status.json',dict(status='RUNNING_COMPLETE_MODELS',pid=os.getpid(),signed_off=False))
    with ThreadPoolExecutor(max_workers=3) as pool:list(pool.map(run,[(n,r) for n in SCENES for r in ['H','oracle']]))
    for n in SCENES:assert (BASE/n/'H/frame.rgb').read_bytes()==(BASE/n/'oracle/frame.rgb').read_bytes(),n
    save(BASE/'status.json',dict(status='COMPLETE_REVIEW_REQUIRED',signed_off=False,scenes=list(SCENES)))
    from scripts.audit_t06_precount_full import main as audit
    audit()
if __name__=='__main__':
    BASE.mkdir(parents=True,exist_ok=True)
    with (BASE/'worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main()
        except BaseException as e:save(BASE/'status.json',dict(status='FAILED_REVIEW_REQUIRED',error=repr(e),signed_off=False));traceback.print_exc();raise
