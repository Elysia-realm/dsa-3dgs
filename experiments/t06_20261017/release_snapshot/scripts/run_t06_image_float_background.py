"""One-shot independent float full-model reference; never a substitute for RTL."""
import os
os.environ['OPENBLAS_NUM_THREADS']='1';os.environ['OMP_NUM_THREADS']='1'
import hashlib,json,sys,traceback
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import diagnose_t06_low_resolution as work
BASE=ROOT/'experiments/t06_20261017';JOB=BASE/'jobs/float_reference'
def main():
    JOB.mkdir(parents=True,exist_ok=True);work.BASE=BASE/'full_render';work.OUT=BASE/'float_full'
    files=['scripts/diagnose_t06_low_resolution.py','scripts/build_full_frame_rtl_batch.py','model/io/scene.py']
    sources={f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in files};rows=[]
    for name in ['bonsai','counter','room','kitchen','garden']:
        (JOB/'status.json').write_text(json.dumps({'status':'RUNNING','scene':name,'pid':os.getpid(),'signed_off':False}))
        rows.append(work.run(name,77/256,True))
    assert all(hashlib.sha256((ROOT/f).read_bytes()).hexdigest()==h for f,h in sources.items())
    (work.OUT/'report.json').write_text(json.dumps({'status':'REFERENCE_READY','source_sha256':sources,'results':rows,
        'scope':'independent float evaluation with project quantization, clipping and thresholds, not official GPU GT; compare with actual RTL when complete'},indent=2))
    (JOB/'status.json').write_text(json.dumps({'status':'REFERENCE_READY','pid':os.getpid(),'signed_off':False}))
if __name__=='__main__':
    JOB.mkdir(parents=True,exist_ok=True)
    with (JOB/'worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main()
        except BaseException as e:
            (JOB/'status.json').write_text(json.dumps({'status':'FAILED_REVIEW_REQUIRED','error':repr(e),'signed_off':False}));traceback.print_exc();raise
