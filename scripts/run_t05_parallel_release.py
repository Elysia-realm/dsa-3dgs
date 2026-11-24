"""Current production-default build, separate from immutable selection runs."""
import sys,json,shutil,argparse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t05_parallel_real as work
BASE=ROOT/'experiments/t05_parallel_20261011';OUT=BASE/'release'
def setup():
    work.OUT=OUT;work.CONFIGS={'production16':(16,1)};OUT.mkdir(parents=True,exist_ok=True)
def prepare():
    for name in work.NAMES:
        src=BASE/'real'/name/'g16';dest=OUT/name/'g16';dest.mkdir(parents=True,exist_ok=True)
        m=json.loads((src/'manifest.json').read_text())
        for relative,h in m['input_sha256'].items():
            assert work.sha(src/relative)==h
            target=dest/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src/relative,target)
        shutil.copy2(src/'manifest.json',dest/'manifest.json')
def run():
    if (OUT/'report.json').exists():
        prior=json.loads((OUT/'report.json').read_text())
        assert prior['source_sha256']==work.sources(),'release source changed; use a fresh output directory'
    cases=[(n,16,'production16',m,p) for n in work.NAMES for m in range(4) for p in ['ideal','limited']]
    with ThreadPoolExecutor(max_workers=10) as pool:rows=list(pool.map(work.simulate,cases))
    selection=json.loads((BASE/'real/report.json').read_text())['results']
    for r in rows:
        old=next(x for x in selection if x['scene']==r['scene'] and x['subset_capacity']==16 and x['variant']=='pipe16' and x['mode']==r['mode'] and x['profile']==r['profile'])
        assert (r['cycles'],r['rgb_sha256'])==(old['cycles'],old['rgb_sha256'])
        log=(OUT/r['scene']/'g16'/f"production16_m{r['mode']}_{r['profile']}"/'run.log').read_text()
        assert 'T05_RELEASE_DEFAULTS K=16 pipeline=1 shared_R=1 RGB=1' in log
    (OUT/'report.json').write_text(json.dumps({'status':'PASS','results':rows,'source_sha256':work.sources(),'scope':'real production defaults; same inputs and exact cycles/RGB as selected K16'},indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['prepare','build','run']);a=p.parse_args();setup()
    if a.action=='prepare':prepare()
    elif a.action=='build':
        work.build('production16','icarus',True);work.build('production16','verilator',True)
    else:run()
