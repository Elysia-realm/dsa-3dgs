"""Factor memory-model service rate separately from scalar/dot3 hardware."""
import os,shutil,sys,traceback
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t06_perf_optimization as p
BASE=ROOT/'experiments/t06_burst_20261021';OLD=ROOT/'experiments/t06_dot3_20261021/real'
def main():
    p.BASE=BASE;p.DATA=BASE/'subset';p.BUILD_TAG='burst_20261021';p.BENCH_TOP='tb_t06_burst_workload';p.VARIANTS={'A':(4,4,1,1),'D':(4,4,1,1)}
    p.EXTRA_DEFINES={'A':['-DTB_ENABLE_ALPHA_ZERO_SKIP=1','-DTB_SHARED_P_DOT3=0'],'D':['-DTB_ENABLE_ALPHA_ZERO_SKIP=1','-DTB_SHARED_P_DOT3=1']}
    p.save(BASE/'status.json',dict(status='BUILDING',pid=os.getpid(),signed_off=False))
    old=p.read(OLD/'report.json');assert len(old['results'])==80
    for n in p.SCENES:
        dest=p.DATA/n;dest.mkdir(parents=True,exist_ok=True)
        for f in ['manifest.json','camera.memh','mean.memh','attribute.memh','expected_sorted.txt']:
            if not (dest/f).exists():shutil.copy2(OLD/'subset'/n/f,dest/f)
            assert p.sha(dest/f)==p.sha(OLD/'subset'/n/f)
        (dest/'oracle').mkdir(exist_ok=True)
        for f in ['result.json','frame.rgb','frame.png']:shutil.copy2(OLD/'subset'/n/'oracle'/f,dest/'oracle'/f)
    for v in p.VARIANTS:p.build(v)
    p.save(BASE/'status.json',dict(status='RUNNING_10_CASES',pid=os.getpid(),signed_off=False));rows=[]
    for v in p.VARIANTS:
        p.run((v,'bonsai',0,'ideal'))
        with ThreadPoolExecutor(max_workers=3) as pool:rows+=list(pool.map(p.run,[(v,n,0,'ideal') for n in p.SCENES]))
    compare=[]
    for n in p.SCENES:
        x={r['variant']:r for r in rows if r['scene']==n};y={r['variant']:r for r in old['results'] if r['scene']==n and r['mode']==0 and r['profile']=='ideal'}
        for v in x:
            mm=x[v]['counters']['REAL_MEMORY_MODEL'];assert mm['mean_contiguous']>0 and mm['attribute_contiguous']>0
            assert x[v]['rgb_sha256']==y[v]['rgb_sha256']
            # RTL file identity is held fixed across the memory-model comparison.
            for f,h in y[v]['source_sha256'].items():
                if f.startswith('rtl/'):assert p.sha(ROOT/f)==h
        compare.append(dict(scene=n,legacy_A=y['A']['command_cycles'],legacy_D=y['D']['command_cycles'],burst_A=x['A']['command_cycles'],burst_D=x['D']['command_cycles'],
          dot3_saved_under_burst_percent=100*(x['A']['command_cycles']-x['D']['command_cycles'])/x['A']['command_cycles']))
    p.save(BASE/'report.json',dict(status='PASS_MODEL_CALIBRATION_NOT_HARDWARE_SIGNOFF',signed_off=False,results=rows,comparisons=compare,
      scope='five subsets G mode only; legacy-vs-burst is memory-model sensitivity, NOT hardware acceleration. A-vs-D within the same profile is the hardware comparison. Neither model is a validated LPDDR system.'))
    p.save(BASE/'status.json',dict(status='COMPLETE_REVIEW_REQUIRED',signed_off=False))
if __name__=='__main__':
    BASE.mkdir(parents=True,exist_ok=True)
    with (BASE/'worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main()
        except BaseException as e:p.save(BASE/'status.json',dict(status='FAILED_REVIEW_REQUIRED',error=repr(e),signed_off=False));traceback.print_exc();raise
