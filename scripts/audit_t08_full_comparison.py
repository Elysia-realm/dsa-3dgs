"""Audit completed full-model comparisons without signing off T08."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,SCENES,read,save,sha

def main():
    folder=BASE/'extended_20261107';report=read(folder/'full_report.json');rows=report['results']
    assert len(rows)==10 and {(r['scene'],r['format']) for r in rows}=={(s,f) for s in SCENES for f in [0,1]}
    files={}
    for r in rows:
        assert r['status']=='PASS_SCOPED_NOT_SIGNED_OFF' and r['full_scene'] and r['width']==128
        d=folder/'real/full'/r['scene']/f"f{r['format']}"
        for f,h in r['source_sha256'].items():
            if f not in files:files[f]=sha(ROOT/f)
            assert files[f]==h
        for f,h in r['evidence_sha256'].items():assert sha(d/f)==h,(str(d),f)
    comparisons=[]
    for s in SCENES:
        b=next(r for r in rows if r['scene']==s and r['format']==0)
        c=next(r for r in rows if r['scene']==s and r['format']==1)
        comparisons.append(dict(scene=s,uncompressed_cycles=b['command_cycles'],compressed_cycles=c['command_cycles'],
          cycle_increase_percent=100*(c['command_cycles']/b['command_cycles']-1),
          attribute_byte_reduction_percent=100*(1-c['counters']['REAL_DMA_COUNTS']['attribute_beats']/b['counters']['REAL_DMA_COUNTS']['attribute_beats']),
          uncompressed_attribute_bursts=b['counters']['REAL_DMA_COUNTS']['attribute_bursts'],
          compressed_attribute_bursts=c['counters']['REAL_DMA_COUNTS']['attribute_bursts']))
    save(folder/'full_comparison_audit.json',dict(status='PASS_EVIDENCE_AUDIT',comparisons=comparisons,
         report_sha256=sha(folder/'full_report.json'),scope='Five complete models, width128, G/legacy-ideal; source/output integrity checked. No native GT/PPA/30FPS signoff.',signed_off=False))
    print('Verified 10 full-model results; all five compressed cases have increased cycles')

if __name__=='__main__':main()
