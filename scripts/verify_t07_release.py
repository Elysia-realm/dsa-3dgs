"""Verify the immutable T07 release; --current also checks the current handoff."""
import argparse,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t07_common import BASE,read,save,sha,source_manifest

def main():
    p=argparse.ArgumentParser();p.add_argument('--current',action='store_true');a=p.parse_args()
    s=read(BASE/'signoff.json');assert s['task']=='T07' and s['signed_off'] and s['status']=='COMPLETE'
    assert not s['final_ppa_pass'] and not s['formal_GT_30FPS_pass']
    assert sha(BASE/'release_audit.json')==s['audit_sha256']
    snap=BASE/'release_snapshot';assert sha(snap/'manifest.json')==s['snapshot_manifest_sha256']
    manifest=read(snap/'manifest.json')
    assert sha(snap/s['report'])==s['report_sha256'] and sha(snap/s['profile'])==s['profile_sha256']
    for name,h in manifest.items():assert sha(snap/name)==h,('snapshot mismatch',name)
    index=read(BASE/'accepted_artifacts.json');bad=[]
    for name,h in index['files'].items():
        path=Path(name)
        if not path.is_file() or sha(path)!=h.upper():bad.append(name)
    assert not bad,('accepted artifact mismatch',bad)
    if a.current:
        status=read(ROOT/'verification/implementation_status.json')
        assert status['t07_status']=='COMPLETE' and status['t07_signed_off']
        assert status['next_execution_task']==status['next_functional_task']=='T08'
        assert not status['ppa_signed_off'] and not status['ground_truth_quality_signed_off'] and not status['t07_30fps_verified']
        assert sha(ROOT/s['report'])==s['report_sha256'] and sha(ROOT/s['profile'])==s['profile_sha256']
        for name,h in source_manifest().items():assert manifest[name]==h
        before=read(BASE/'closure_before/verification/implementation_status.json')
        for task in ['t00_contract_signed_off','t01_signed_off','t03_signed_off','t04_signed_off','t05_signed_off','t06_signed_off']:
            assert status[task]==before[task]
    report=dict(status='PASS',task='T07',signed_off=True,current_handoff_checked=a.current,
      accepted_files=len(index['files']),index_sha256=sha(BASE/'accepted_artifacts.json'),snapshot_files=len(manifest),
      final_ppa_pass=False,formal_GT_30FPS_pass=False,next_task='T08',verifier_sha256=sha(Path(__file__)))
    save(BASE/'signoff_verification.json',report);print(report)
if __name__=='__main__':main()
