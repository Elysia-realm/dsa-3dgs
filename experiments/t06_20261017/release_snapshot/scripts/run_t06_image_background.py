"""One-shot corrected-image acceptance worker. No automatic task signoff."""
import json,os,sys,traceback
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t06_image_release as release
from scripts import diagnose_t06_low_resolution as floating
BASE=release.BASE;JOB=BASE/'jobs/image_release'
def status(phase,**kw):
    JOB.mkdir(parents=True,exist_ok=True);p=JOB/'status.json';tmp=p.with_suffix('.pending')
    tmp.write_text(json.dumps({'status':phase,'pid':os.getpid(),'signed_off':False,**kw},ensure_ascii=False,indent=2),encoding='utf-8');tmp.replace(p)
def main():
    status('CHECKING_INPUTS');release.verify_encoding()
    r=release.read(release.SUB/'report.json');assert r['status']=='PASS' and len(r['results'])==40
    assert all(x['source_sha256']==release.common.sources() for x in r['results'])
    status('CHECKING_FLOAT_REFERENCE')
    float_rows=[]
    for n in release.NAMES:
        p=BASE/'float_subset'/n/'float_floor_0.30078125_jac_clamp.json'
        f=release.read(p);assert f['jacobian_fov_clamp']
        assert f['rtl_mae_rgb8']<=2 and f['rtl_active_mae_rgb8']<=5,(n,f)
        float_rows.append(f)
    release.save(BASE/'float_subset/report.json',{'status':'PASS','scope':'independent float semantic check on real subsets; not GT/target-quality signoff','results':float_rows})
    status('RUNNING_FULL_MODELS',subset_runs_passed=40,float_scenes_passed=5)
    release.full(4)
    status('TESTS_FINISHED_REVIEW_REQUIRED',full_scenes_passed=5,full_rgb_matches=5,
           next='Inspect corrected full PNGs, run final source-bound evidence checks and archive before any signoff')
if __name__=='__main__':
    JOB.mkdir(parents=True,exist_ok=True)
    with (JOB/'worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main()
        except BaseException as e:
            status('FAILED_REVIEW_REQUIRED',error=repr(e),traceback=traceback.format_exc());traceback.print_exc();raise
