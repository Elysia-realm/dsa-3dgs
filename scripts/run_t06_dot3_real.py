"""Five-scene source-matched scalar-P A versus dot3-P D candidate; no signoff."""
import json,os,shutil,sys,traceback
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t06_perf_optimization as p
BASE=ROOT/'experiments/t06_dot3_20261021/real';OLD=ROOT/'experiments/t06_perf_20261018'
def main():
    p.BASE=BASE;p.DATA=BASE/'subset';p.BUILD_TAG='dot3_20261021';p.VARIANTS={'A':(4,4,1,1),'D':(4,4,1,1)}
    p.EXTRA_DEFINES={'A':['-DTB_ENABLE_ALPHA_ZERO_SKIP=1','-DTB_SHARED_P_DOT3=0'],'D':['-DTB_ENABLE_ALPHA_ZERO_SKIP=1','-DTB_SHARED_P_DOT3=1']}
    p.save(BASE/'status.json',dict(status='PREPARING_BUILDING',pid=os.getpid(),signed_off=False))
    for n in p.SCENES:
        d=p.DATA/n;d.mkdir(parents=True,exist_ok=True)
        for f in ['manifest.json','camera.memh','mean.memh','attribute.memh','expected_sorted.txt']:
            if not (d/f).exists():shutil.copy2(OLD/'subset'/n/f,d/f)
            assert p.sha(d/f)==p.sha(OLD/'subset'/n/f)
        ref=OLD/'subset'/n/'oracle';source=p.read(ref/'result.json')['source_sha256']
        for f,h in source.items():assert p.sha(OLD/'selection_snapshot'/f)==h
        (d/'oracle').mkdir(exist_ok=True)
        for f in ['result.json','frame.rgb','frame.png']:shutil.copy2(ref/f,d/'oracle'/f)
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
                pair={r['variant']:r for r in rows if (r['scene'],r['mode'],r['profile'])==(n,m,a)};f=pair['A'];l=pair['D']
                assert f['counters']['REAL_LOCAL_QSU']['records']==l['counters']['REAL_LOCAL_QSU']['records']==0
                assert l['counters']['REAL_SHARED_PE']['P']*3==f['counters']['REAL_SHARED_PE']['P']
                assert f['rgb_sha256']==l['rgb_sha256']
                for key in ['input','partitions','leaves']:assert f['counters']['REAL_QSU'][key]==l['counters']['REAL_QSU'][key]
                assert l['counters']['REAL_QSU']['reads']==f['counters']['REAL_QSU']['reads']
                compare.append(dict(scene=n,mode=m,profile=a,A_cycles=f['command_cycles'],D_cycles=l['command_cycles'],
                  saved_percent=100*(f['command_cycles']-l['command_cycles'])/f['command_cycles'],A_P=f['counters']['REAL_SHARED_PE']['P'],D_P=l['counters']['REAL_SHARED_PE']['P']))
    p.save(BASE/'report.json',dict(status='PASS_SUBSET_NOT_SIGNOFF',results=rows,comparisons=compare,signed_off=False))
    p.save(BASE/'status.json',dict(status='COMPLETE_REVIEW_REQUIRED',signed_off=False))
if __name__=='__main__':
    BASE.mkdir(parents=True,exist_ok=True)
    with (BASE/'worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main()
        except BaseException as e:p.save(BASE/'status.json',dict(status='FAILED_REVIEW_REQUIRED',error=repr(e),signed_off=False));traceback.print_exc();raise
