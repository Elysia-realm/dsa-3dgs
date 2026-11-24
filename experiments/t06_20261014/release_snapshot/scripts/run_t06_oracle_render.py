"""Independent CPU global-order oracle through legacy QSU/continuation RTL.

This path is NEVER counted as autonomous verification. Its DMA RGB is compared
with autonomous full-model images, using the identical fixed-point input bytes.
"""
import argparse,json,os,subprocess,sys,time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t06_real as base
from scripts.read_rgb888_frame import decode_rgb888
OUT=ROOT/'experiments/t06_20261014/full_render'
def source_hashes():
    h=base.sources();h.pop('verification/rtl/tb_real_dma_workload.sv')
    h['verification/rtl/tb_t06_oracle_render.sv']=base.sha(ROOT/'verification/rtl/tb_t06_oracle_render.sv');return h
def build():
    folder=OUT/'oracle_build';folder.mkdir(exist_ok=True)
    cmd=json.loads((OUT/'build/pipe1_verilator_command.json').read_text())
    cmd[-1]=cmd[-1].replace('tb_real_dma_workload','tb_t06_oracle_render').replace('tmp/verilator_t06_pipe1_n6000000','tmp/verilator_t06_oracle').replace('-o t06_real.exe','-o t06_oracle.exe')
    env=os.environ.copy();env.update(MSYSTEM='UCRT64',CHERE_INVOKING='1')
    with (folder/'build.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    (folder/'command.json').write_text(json.dumps(cmd,indent=2))
    if r.returncode:raise RuntimeError((folder/'build.log').read_text()[-3000:])
    (folder/'sources.json').write_text(json.dumps(source_hashes(),indent=2));print('BUILT oracle',flush=True)
def run(name,collect_only=False):
    folder=OUT/name;dest=folder/'oracle';dest.mkdir(exist_ok=True);m=json.loads((folder/'manifest.json').read_text())
    frozen=json.loads((OUT/'oracle_build/sources.json').read_text())
    # The independent oracle deliberately uses the frozen legacy grouping path.
    # A QSU-only fix must not silently relabel this reference as current RTL.
    snapshot=ROOT/'experiments/t06_20261014/pre_leaf_buffer_snapshot'
    for f,h in frozen.items():assert base.sha(snapshot/f)==h,'unverified reference snapshot '+f
    cmd=[str(ROOT/'tmp/verilator_t06_oracle/t06_oracle.exe'),
         f'+MEAN={(folder/"mean.memh").as_posix()}',f'+ATTR={(folder/"attribute.memh").as_posix()}',f'+CAMERA={(folder/"camera.memh").as_posix()}',
         f'+ORACLE={(folder/"expected_sorted.txt").as_posix()}',f'+FRAME={(dest/"state.memh").as_posix()}',f'+RGB={(dest/"rgb.memh").as_posix()}',
         '+FRAME_MODE=0','+READ_LATENCY=0','+READ_GAP=0','+READY_PERIOD=1','+READY_LOW=0','+WRITE_RESPONSE_LATENCY=2','+MAX_TIMEOUT=3000000']
    env=os.environ.copy();env['PATH']=r'D:\Tools\msys64\ucrt64\bin;'+env['PATH'];t=time.monotonic()
    if collect_only:
        assert json.loads((dest/'command.json').read_text())==cmd,'cannot collect a different command'
        assert json.loads((dest/'progress.json').read_text())['source_sha256']==frozen,'cannot collect a different source version'
        rc=0
    else:
        (dest/'command.json').write_text(json.dumps(cmd,indent=2))
        (dest/'progress.json').write_text(json.dumps({'status':'RUNNING','source_sha256':frozen},indent=2))
        with (dest/'run.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
        rc=r.returncode
    log=(dest/'run.log').read_text()
    if rc or 'PASS: tb_t06_oracle_render' not in log:
        (dest/'progress.json').write_text(json.dumps({'status':'FAILED','returncode':rc}));raise RuntimeError(name+log[-4000:])
    rgb=bytes(int(x,16) for x in (dest/'rgb.memh').read_text().split())
    (dest/'frame.rgb').write_bytes(rgb);Image.fromarray(decode_rgb888(rgb,m['width'],m['height'])).save(dest/'frame.png')
    match=None
    reference=folder/'production_v2/frame.rgb'
    if reference.exists():match=rgb==reference.read_bytes();assert match,'full autonomous/oracle RGB mismatch'
    row={'status':'PASS_ORACLE','scene':name,'seconds':None if collect_only else time.monotonic()-t,'collected_after_worker_exit':collect_only,'rgb_sha256':base.sha(dest/'frame.rgb'),
         'autonomous':False,'cpu_global_sorted':True,'source_sha256':frozen,'autonomous_rgb_matches':match}
    (dest/'result.json').write_text(json.dumps(row,indent=2));(dest/'progress.json').write_text(json.dumps({'status':'PASS_ORACLE'}));print('PASS ORACLE',name,'matches',match,flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['build','run']);p.add_argument('--scenes',nargs='+',default=base.SCENES);p.add_argument('--workers',type=int,default=1);p.add_argument('--collect-only',action='store_true');a=p.parse_args()
    if a.action=='build':build()
    else:
        with ThreadPoolExecutor(max_workers=a.workers) as pool:list(pool.map(lambda n:run(n,a.collect_only),a.scenes))
