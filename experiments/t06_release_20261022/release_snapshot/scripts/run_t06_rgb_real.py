"""Same memory model, same renderer, scalar versus 16-beat final RGB reads."""
import os,shutil,sys,traceback
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t06_perf_optimization as p
BASE=ROOT/'experiments/t06_rgb_burst_20261022/real';OLD=ROOT/'experiments/t06_dot3_20261021/real'
def main():
    p.BASE=BASE;p.DATA=BASE/'subset';p.BUILD_TAG='rgb_20261022';p.BENCH_TOP='tb_t06_rgb_workload'
    p.VARIANTS={'D':(4,4,1,1),'R':(4,4,1,1)}
    p.EXTRA_DEFINES={v:['-DTB_ENABLE_ALPHA_ZERO_SKIP=1','-DTB_SHARED_P_DOT3=1',f'-DTB_RGB_READ_BURST={1 if v=="D" else 16}'] for v in p.VARIANTS}
    p.save(BASE/'status.json',dict(status='BUILDING',pid=os.getpid(),signed_off=False))
    for n in p.SCENES:
        dest=p.DATA/n;dest.mkdir(parents=True,exist_ok=True)
        for f in ['manifest.json','camera.memh','mean.memh','attribute.memh','expected_sorted.txt']:
            if not (dest/f).exists():shutil.copy2(OLD/'subset'/n/f,dest/f)
            assert p.sha(dest/f)==p.sha(OLD/'subset'/n/f)
        (dest/'oracle').mkdir(exist_ok=True)
        for f in ['result.json','frame.rgb','frame.png']:shutil.copy2(OLD/'subset'/n/'oracle'/f,dest/'oracle'/f)
    for v in p.VARIANTS:p.build(v)
    p.save(BASE/'status.json',dict(status='RUNNING_80_CASES',pid=os.getpid(),signed_off=False));rows=[]
    for v in p.VARIANTS:
        p.run((v,'bonsai',0,'ideal'))
        cases=[(v,n,m,a) for n in p.SCENES for m in range(4) for a in ['ideal','limited']]
        with ThreadPoolExecutor(max_workers=4) as pool:rows+=list(pool.map(p.run,cases))
    compare=[]
    for n in p.SCENES:
        for m in range(4):
            for a in ['ideal','limited']:
                pair={r['variant']:r for r in rows if (r['scene'],r['mode'],r['profile'])==(n,m,a)};d=pair['D'];r=pair['R']
                assert d['rgb_sha256']==r['rgb_sha256']
                assert d['counters']['REAL_RGB_BURST']['configured']==1 and r['counters']['REAL_RGB_BURST']['configured']==16
                for group,keys in [('REAL_QSU',['input','partitions','leaves','reads','writes']),('REAL_SHARED_PE',['G','P','R']),('REAL_RGB',['reads','write_beats','bytes'])]:
                    for k in keys:assert d['counters'][group][k]==r['counters'][group][k],(n,group,k)
                assert r['counters']['REAL_DMA_COUNTS']['state_read_bursts']<d['counters']['REAL_DMA_COUNTS']['state_read_bursts']
                compare.append(dict(scene=n,mode=m,profile=a,D_cycles=d['command_cycles'],R_cycles=r['command_cycles'],
                  saved_percent=100*(d['command_cycles']-r['command_cycles'])/d['command_cycles'],
                  D_state_AR=d['counters']['REAL_DMA_COUNTS']['state_read_bursts'],R_state_AR=r['counters']['REAL_DMA_COUNTS']['state_read_bursts']))
    p.save(BASE/'report.json',dict(status='PASS_SUBSET_NOT_SIGNOFF',signed_off=False,results=rows,comparisons=compare,
      scope='actual production RGB DMA read-burst change; same scalar/burst-capable slave model for both variants; not full-model or final-resolution frame performance signoff'))
    p.save(BASE/'status.json',dict(status='COMPLETE_REVIEW_REQUIRED',signed_off=False))
if __name__=='__main__':
    BASE.mkdir(parents=True,exist_ok=True)
    with (BASE/'worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main()
        except BaseException as e:p.save(BASE/'status.json',dict(status='FAILED_REVIEW_REQUIRED',error=repr(e),signed_off=False));traceback.print_exc();raise
