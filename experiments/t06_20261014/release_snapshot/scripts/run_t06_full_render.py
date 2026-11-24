"""Full production input -> autonomous QSU -> BSU -> RTL RGB. No quality signoff."""
import argparse,json,os,re,subprocess,sys,time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t06_real as runner
from scripts.read_rgb888_frame import decode_rgb888
OUT=ROOT/'experiments/t06_20261014/full_render'
def run(name,collect_only=False):
    folder=OUT/name;m=json.loads((folder/'manifest.json').read_text());dest=folder/'production_v2';dest.mkdir(exist_ok=True)
    frozen=json.loads((OUT/'build/pipe1_verilator_sources.json').read_text())
    for f,h in frozen.items():assert runner.sha(ROOT/f)==h,'stale build '+f
    cmd=[str(ROOT/'tmp/verilator_t06_pipe1_n6000000/t06_real.exe'),'+AUTO_QSU',
         f'+MEAN={(folder/"mean.memh").as_posix()}',f'+ATTR={(folder/"attribute.memh").as_posix()}',
         f'+CAMERA={(folder/"camera.memh").as_posix()}',f'+FRAME={(dest/"state.memh").as_posix()}',
         f'+RGB={(dest/"rgb.memh").as_posix()}',f'+SORTED_TRACE={(dest/"sorted.txt").as_posix()}',
         '+FRAME_MODE=0','+READ_LATENCY=0','+READ_GAP=0','+READY_PERIOD=1','+READY_LOW=0','+WRITE_RESPONSE_LATENCY=2','+MAX_TIMEOUT=2000000000']
    env=os.environ.copy();env['PATH']=r'D:\Tools\msys64\ucrt64\bin;'+env['PATH'];t=time.monotonic()
    if collect_only:
        assert json.loads((dest/'command.json').read_text())==cmd,'cannot collect output from a different command'
        assert json.loads((dest/'progress.json').read_text())['source_sha256']==frozen,'cannot collect a different source version'
        rc=0
    else:
        (dest/'command.json').write_text(json.dumps(cmd,indent=2))
        (dest/'progress.json').write_text(json.dumps({'status':'RUNNING','scene':name,'pid':os.getpid(),'source_sha256':frozen},indent=2))
        with (dest/'run.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
        rc=r.returncode
    log=(dest/'run.log').read_text()
    if rc or 'PASS: tb_real_dma_workload' not in log:
        (dest/'progress.json').write_text(json.dumps({'status':'FAILED','scene':name,'returncode':rc,'seconds':time.monotonic()-t},indent=2))
        raise RuntimeError(name+log[-4000:])
    assert (dest/'sorted.txt').read_bytes()==(folder/'expected_sorted.txt').read_bytes(),'full-model order differs'
    rgb=bytes(int(x,16) for x in (dest/'rgb.memh').read_text().split());w,h=m['width'],m['height'];stride=(w*3+15)&~15
    state=[int(x,16) for x in (dest/'state.memh').read_text().split()];expected=bytearray(stride*h)
    for i,s in enumerate(state):
        if (s>>55)&65535!=1:continue
        y,x=divmod(i,w)
        for c in range(3):expected[y*stride+3*x+c]=min(255,(((s>>(13*c))&8191)*255+2048)//4096)
    assert rgb==expected,'RGB DMA/state mismatch'
    (dest/'frame.rgb').write_bytes(rgb);Image.fromarray(decode_rgb888(rgb,w,h)).save(dest/'frame.png')
    qsu={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',next(x for x in log.splitlines() if x.startswith('REAL_QSU')))}
    assert qsu['input']==m['visible'] and qsu['reads']==qsu['axi_reads'] and qsu['writes']==qsu['axi_writes']
    assert runner.sources()==frozen,'source changed while simulation was running; do not relabel the binary'
    row={'status':'PASS_DATAPATH_PENDING_IMAGE_ORACLE','scene':name,'gaussians':m['gaussians'],'visible':m['visible'],'full_scene':True,
         'width':w,'height':h,'qsu':qsu,'seconds':None if collect_only else time.monotonic()-t,'collected_after_worker_exit':collect_only,'cycles':int(re.search(r'REAL_PERF cycles=(\d+)',log)[1]),'rgb_sha256':runner.sha(dest/'frame.rgb'),'source_sha256':frozen}
    (dest/'result.json').write_text(json.dumps(row,indent=2));(dest/'progress.json').write_text(json.dumps({'status':row['status'],'seconds':row['seconds']}));print('PASS DATAPATH',name,row['cycles'],flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['build','run']);p.add_argument('--scenes',nargs='+',default=runner.SCENES);p.add_argument('--workers',type=int,default=1);p.add_argument('--collect-only',action='store_true');a=p.parse_args()
    if a.action=='build':runner.OUT=OUT;runner.build('verilator',1,6000000)
    else:
        with ThreadPoolExecutor(max_workers=a.workers) as pool:list(pool.map(lambda n:run(n,a.collect_only),a.scenes))
