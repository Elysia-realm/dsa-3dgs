"""R/H same-source comparison, no input, renderer, or AXI-model change."""
import os,shutil,sys,traceback
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t06_perf_optimization as p
BASE=ROOT/'experiments/t06_precount_mem_20261022/real'
OLD=ROOT/'experiments/t06_rgb_burst_20261022/real'

def main():
    p.BASE=BASE;p.DATA=BASE/'subset';p.BUILD_TAG='precount_mem_20261022';p.BENCH_TOP='tb_t06_rgb_workload'
    p.VARIANTS={'R':(4,4,1,1),'H':(4,4,1,1)}
    p.EXTRA_DEFINES={v:['-DTB_ENABLE_ALPHA_ZERO_SKIP=1','-DTB_SHARED_P_DOT3=1','-DTB_RGB_READ_BURST=16',f'-DTB_QSU_PRECOUNT={int(v=="H")}'] for v in p.VARIANTS}
    p.save(BASE/'status.json',dict(status='BUILDING',pid=os.getpid(),signed_off=False))
    for n in p.SCENES:
        dest=p.DATA/n;dest.mkdir(parents=True,exist_ok=True)
        for f in ['manifest.json','camera.memh','mean.memh','attribute.memh','expected_sorted.txt']:
            if not (dest/f).exists():shutil.copy2(OLD/'subset'/n/f,dest/f)
            assert p.sha(dest/f)==p.sha(OLD/'subset'/n/f)
        (dest/'oracle').mkdir(exist_ok=True)
        for f in ['result.json','frame.rgb','frame.png']:shutil.copy2(OLD/'subset'/n/'oracle'/f,dest/'oracle'/f)
    # Include all headers/filelist in the immutable snapshot, not just .sv.
    src=p.source_hashes()
    for f in list(ROOT.glob('rtl/**/*.svh'))+[ROOT/'verification/rtl/system_top_sources.f']:
        src[f.relative_to(ROOT).as_posix()]=p.sha(f)
    snap=BASE/'source_snapshot'
    for f,h in src.items():
        dest=snap/f;dest.parent.mkdir(parents=True,exist_ok=True)
        if not dest.exists():shutil.copy2(ROOT/f,dest)
        assert p.sha(dest)==h
    p.save(snap/'manifest.json',src)
    for v in p.VARIANTS:p.build(v)
    p.save(BASE/'status.json',dict(status='RUNNING_80_CASES',pid=os.getpid(),signed_off=False));rows=[]
    for v in p.VARIANTS:
        p.run((v,'bonsai',0,'ideal'))
        cases=[(v,n,m,a) for n in p.SCENES for m in range(4) for a in ['ideal','limited']]
        with ThreadPoolExecutor(max_workers=4) as pool:rows+=list(pool.map(p.run,cases))
    comparisons=[]
    for n in p.SCENES:
        for m in range(4):
            for a in ['ideal','limited']:
                pair={r['variant']:r for r in rows if (r['scene'],r['mode'],r['profile'])==(n,m,a)};r=pair['R'];h=pair['H']
                assert r['rgb_sha256']==h['rgb_sha256']
                # The disabled candidate must reproduce the frozen R baseline.
                old=p.read(OLD/'subset'/n/f'R_m{m}_{a}'/'result.json')
                assert r['command_cycles']==old['command_cycles'] and r['rgb_sha256']==old['rgb_sha256']
                for group,keys in [('REAL_QSU',['input','partitions','leaves','writes']),('REAL_SHARED_PE',['G','P','R']),('REAL_RGB',['reads','write_beats','bytes'])]:
                    for k in keys:assert r['counters'][group][k]==h['counters'][group][k],(n,group,k)
                qr=r['counters']['REAL_QSU'];qh=h['counters']['REAL_QSU']
                assert qh['reads']<qr['reads']
                assert qh['reads']==(qr['reads']-qr['input'])//2+2*qr['input']
                comparisons.append(dict(scene=n,mode=m,profile=a,R_cycles=r['command_cycles'],H_cycles=h['command_cycles'],
                  saved_percent=100*(r['command_cycles']-h['command_cycles'])/r['command_cycles'],
                  R_qsu_reads=qr['reads'],H_qsu_reads=qh['reads']))
    assert all(p.sha(ROOT/f)==h for f,h in src.items())
    p.save(BASE/'report.json',dict(status='PASS_SUBSET_NOT_SIGNOFF',signed_off=False,results=rows,comparisons=comparisons,
      scope='Five scenes, 512 Gaussians, four modes/two AXI; not full model/native-resolution/PPA/30FPS signoff'))
    p.save(BASE/'status.json',dict(status='COMPLETE_REVIEW_REQUIRED',signed_off=False))
if __name__=='__main__':
    BASE.mkdir(parents=True,exist_ok=True)
    with (BASE/'worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main()
        except BaseException as e:p.save(BASE/'status.json',dict(status='FAILED_REVIEW_REQUIRED',error=repr(e),signed_off=False));traceback.print_exc();raise
