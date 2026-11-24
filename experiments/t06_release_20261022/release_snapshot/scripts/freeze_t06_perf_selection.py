"""Verify and pin the B/W/F selection before further production RTL changes."""
import json,shutil,statistics,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t06_perf_optimization import BASE,SCENES,VARIANTS,read,save,sha
def main():
    r=read(BASE/'selection_report.json');assert len(r['results'])==120
    assert {(x['variant'],x['scene'],x['mode'],x['profile']) for x in r['results']}=={(v,n,m,p) for v in VARIANTS for n in SCENES for m in range(4) for p in ['ideal','limited']}
    sources={};artifacts={}
    for x in r['results']:
        assert x['status']=='PASS';sources.update(x['source_sha256'])
        d=BASE/'subset'/x['scene']/f'{x["variant"]}_m{x["mode"]}_{x["profile"]}'
        assert sha(d/'frame.rgb')==x['rgb_sha256']
        assert (d/'frame.rgb').read_bytes()==(d.parent/'oracle/frame.rgb').read_bytes()
        assert (d/'sorted.txt').read_bytes()==(d.parent/'expected_sorted.txt').read_bytes()
        for f,h in x['input_sha256'].items():assert sha(d.parent/f)==h
        for f in ['run.log','command.json','result.json','frame.rgb','frame.png','sorted.txt']:
            artifacts[(d/f).relative_to(ROOT).as_posix()]=sha(d/f)
    for p in [BASE/'units/report.json',BASE/'recovery/report.json']:
        x=read(p);assert x['status']=='PASS';sources.update(x['source_sha256'])
    for n in SCENES:sources.update(read(BASE/'subset'/n/'oracle/result.json')['source_sha256'])
    for f in ['scripts/run_t06_perf_optimization.py','scripts/prepare_t06_full_render.py','model/io/scene.py',
      'scripts/build_full_frame_rtl_batch.py','scripts/build_full_frame_batch_index.py','model/io/dma_workload.py',
      'verification/rtl/system_top_sources.f']:
        sources[f]=sha(ROOT/f)
    for p in (ROOT/'rtl').rglob('*.svh'):sources[p.relative_to(ROOT).as_posix()]=sha(p)
    for f,h in sources.items():
        assert sha(ROOT/f)==h,f;dest=BASE/'selection_snapshot'/f;dest.parent.mkdir(parents=True,exist_ok=True)
        if dest.exists():assert sha(dest)==h,'different frozen source '+f
        else:shutil.copy2(ROOT/f,dest)
    summary={p:{k:dict(mean=statistics.mean(x[k] for x in r['comparisons'] if x['profile']==p),
        minimum=min(x[k] for x in r['comparisons'] if x['profile']==p),maximum=max(x[k] for x in r['comparisons'] if x['profile']==p))
        for k in ['W_saved_percent','F_saved_percent','bypass_saved_percent']} for p in ['ideal','limited']}
    assert all(x['F_saved_percent']>0 for x in r['comparisons'])
    save(BASE/'selection_audit.json',dict(status='PASS_SELECTION_NOT_SIGNOFF',signed_off=False,results=120,summary=summary,
      source_sha256=sources,artifact_sha256=artifacts,decision='F selected for complete-model validation; no production default promotion or 30FPS claim'))
    print(json.dumps(summary,indent=2))
if __name__=='__main__':main()
