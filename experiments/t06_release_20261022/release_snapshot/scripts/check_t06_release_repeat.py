"""Five nonempty real two-frame E->G transitions; no reset between frames."""
import os,json,re,subprocess,sys,time,traceback
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t06_release_common import configure,BASE,OLD,PROFILE,assert_command_profile
OUT=BASE/'repeat'

def main():
    p=configure('tb_t06_release_repeat','repeat');p.BASE=OUT
    # Distinct build directory; do not touch the running release build.
    p.build('H');assert_command_profile(p.read(OUT/'build/H/command.json'),p.BENCH_TOP)
    src=p.source_hashes();exe=ROOT/f'tmp/verilator_t06_{p.BUILD_TAG}_H/t06_perf.exe'
    env=os.environ.copy();env['PATH']=r'D:\Tools\msys64\ucrt64\bin;'+env['PATH']
    def run(n):
        folder=OLD/'subset'/n;dest=OUT/n;dest.mkdir(parents=True,exist_ok=True)
        cmd=[str(exe),'+AUTO_QSU','+AUTO_MODE','+AUTO_REPEAT_FRAMES=2','+FRAME_MODE=3',
          f'+MEAN={(folder/"mean.memh").as_posix()}',f'+ATTR={(folder/"attribute.memh").as_posix()}',
          f'+CAMERA={(folder/"camera.memh").as_posix()}',f'+FRAME={(dest/"state.memh").as_posix()}',
          f'+RGB={(dest/"rgb.memh").as_posix()}',f'+SORTED_TRACE={(dest/"sorted.txt").as_posix()}',
          '+READ_LATENCY=8','+READ_GAP=2','+READY_PERIOD=4','+READY_LOW=1','+WRITE_RESPONSE_LATENCY=8','+MAX_TIMEOUT=10000000']
        p.save(dest/'command.json',cmd);start=time.monotonic()
        with (dest/'run.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
        log=(dest/'run.log').read_text();assert r.returncode==0 and 'PASS: tb_t06_release_repeat' in log,log[-3000:]
        auto={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',next(l for l in log.splitlines() if l.startswith('REAL_AUTO ')))}
        assert auto['observe_mode']==3 and auto['selected_mode']==0 and auto['image_mismatches']==0
        rgb=bytes(int(x,16) for x in (dest/'rgb.memh').read_text().split());assert rgb==(folder/'oracle/frame.rgb').read_bytes()
        assert (dest/'sorted.txt').read_bytes()==2*(folder/'expected_sorted.txt').read_bytes()
        assert 'epoch=2 error=00000000' in log
        return dict(scene=n,status='PASS',frames=2,auto=auto,seconds=time.monotonic()-start,
          input_sha256=p.read(folder/'manifest.json')['input_sha256'],rgb_sha256=__import__('hashlib').sha256(rgb).hexdigest(),
          log_sha256=p.sha(dest/'run.log'))
    with ThreadPoolExecutor(max_workers=3) as pool:rows=list(pool.map(run,p.SCENES))
    assert p.source_hashes()==src
    p.save(OUT/'report.json',dict(status='PASS',results=rows,source_sha256=src,profile_sha256=p.sha(PROFILE),
       scope='Five real 512-record scenes, two fresh autonomous frames E->G, limited AXI; identical camera and no reset. Camera-change recovery checked independently; not T09 policy optimality.'))
if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main()
        except BaseException:traceback.print_exc();raise
