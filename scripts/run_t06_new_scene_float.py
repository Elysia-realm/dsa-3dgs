"""Independent full Train/Truck float references; explicitly not RTL outputs."""
import os
os.environ['OPENBLAS_NUM_THREADS']='1';os.environ['OMP_NUM_THREADS']='1'
import sys,traceback
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import diagnose_t06_low_resolution as f
from scripts.run_t06_perf_optimization import save,sha
BASE=ROOT/'experiments/t06_full_f_20261019';OUT=BASE/'float_refs'
def main():
    f.BASE=BASE;f.OUT=OUT
    files=['scripts/diagnose_t06_low_resolution.py','scripts/build_full_frame_rtl_batch.py','model/io/scene.py']
    sources={p:sha(ROOT/p) for p in files};rows=[]
    for n in ['train','truck']:
        save(OUT/'status.json',dict(status='RUNNING',scene=n,pid=os.getpid(),signed_off=False))
        rows.append(f.run(n,77/256,True))
    assert all(sha(ROOT/p)==h for p,h in sources.items())
    save(OUT/'report.json',dict(status='REFERENCE_READY',source_sha256=sources,results=rows))
    save(OUT/'status.json',dict(status='REFERENCE_READY',signed_off=False))
if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main()
        except BaseException as e:save(OUT/'status.json',dict(status='FAILED',error=repr(e)));traceback.print_exc();raise
