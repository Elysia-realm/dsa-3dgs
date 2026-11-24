"""A = frozen F scheduling + existing exact alpha-zero transaction skip."""
import os,shutil,sys,traceback
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t06_perf_optimization as p
BASE=ROOT/'experiments/t06_alpha_20261020'
OLD=ROOT/'experiments/t06_local_20261019/real'
def main():
    p.BASE=BASE;p.DATA=BASE/'subset';p.BUILD_TAG='alpha_20261020';p.VARIANTS={'A':(4,4,1,1)}
    p.EXTRA_DEFINES={'A':['-DTB_QSU_LOCAL_RECORDS=0','-DTB_ENABLE_ALPHA_ZERO_SKIP=1']}
    p.save(BASE/'status.json',dict(status='PREPARING_BUILDING',pid=os.getpid(),signed_off=False))
    baseline=p.read(OLD/'report.json')
    assert baseline['status']=='PASS_SUBSET_NOT_SIGNOFF'
    expected=p.source_hashes()
    for r in baseline['results']:assert r['source_sha256']==expected
    for n in p.SCENES:
        d=p.DATA/n;d.mkdir(parents=True,exist_ok=True)
        for f in ['manifest.json','camera.memh','mean.memh','attribute.memh','expected_sorted.txt']:
            if not (d/f).exists():shutil.copy2(OLD/'subset'/n/f,d/f)
            assert p.sha(d/f)==p.sha(OLD/'subset'/n/f)
        (d/'oracle').mkdir(exist_ok=True)
        for f in ['result.json','frame.rgb','frame.png']:shutil.copy2(OLD/'subset'/n/'oracle'/f,d/'oracle'/f)
    # Pin baseline source before comparing; no producer code is edited by this job.
    for f,h in expected.items():
        d=BASE/'source_snapshot'/f;d.parent.mkdir(parents=True,exist_ok=True)
        if d.exists():assert p.sha(d)==h
        else:shutil.copy2(ROOT/f,d)
    p.build('A');p.run(('A','bonsai',0,'ideal'))
    p.save(BASE/'status.json',dict(status='RUNNING_40_CASES',pid=os.getpid(),signed_off=False))
    cases=[('A',n,m,a) for n in p.SCENES for m in range(4) for a in ['ideal','limited']]
    with ThreadPoolExecutor(max_workers=4) as pool:rows=list(pool.map(p.run,cases))
    compare=[]
    for a in rows:
        f=next(x for x in baseline['results'] if x['variant']=='F' and (x['scene'],x['mode'],x['profile'])==(a['scene'],a['mode'],a['profile']))
        assert a['rgb_sha256']==f['rgb_sha256']
        ac=a['counters'];fc=f['counters'];assert ac['REAL_ALPHA_SKIP']['enabled']==1 and ac['REAL_ALPHA_SKIP']['skipped']>0
        assert ac['REAL_LOCAL_QSU']['records']==0
        for key in ['input','partitions','leaves','reads','writes']:assert ac['REAL_QSU'][key]==fc['REAL_QSU'][key]
        for key in ['G','P']:assert ac['REAL_SHARED_PE'][key]==fc['REAL_SHARED_PE'][key],(a['scene'],key)
        compare.append(dict(scene=a['scene'],mode=a['mode'],profile=a['profile'],F_cycles=f['command_cycles'],A_cycles=a['command_cycles'],
          saved_percent=100*(f['command_cycles']-a['command_cycles'])/f['command_cycles'],
          skipped=ac['REAL_ALPHA_SKIP']['skipped'],F_R=fc['REAL_SHARED_PE']['R'],A_R=ac['REAL_SHARED_PE']['R'],
          F_state_reads=fc['REAL_PERF']['state_reads'],A_state_reads=ac['REAL_PERF']['state_reads'],
          F_state_writes=fc['REAL_PERF']['state_writes'],A_state_writes=ac['REAL_PERF']['state_writes']))
    p.save(BASE/'report.json',dict(status='PASS_SUBSET_NOT_SIGNOFF',signed_off=False,results=rows,comparisons=compare,
      baseline_report=str(OLD/'report.json'),baseline_report_sha256=p.sha(OLD/'report.json'),source_sha256=expected))
    p.save(BASE/'status.json',dict(status='COMPLETE_REVIEW_REQUIRED',signed_off=False))
if __name__=='__main__':
    BASE.mkdir(parents=True,exist_ok=True)
    with (BASE/'worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main()
        except BaseException as e:p.save(BASE/'status.json',dict(status='FAILED_REVIEW_REQUIRED',error=repr(e),signed_off=False));traceback.print_exc();raise
