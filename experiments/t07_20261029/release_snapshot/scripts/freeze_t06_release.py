"""Archive the signed functional source/evidence index without changing RTL."""
import json,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t06_release_common import BASE,PROFILE,check_frozen_sources
from scripts.run_t06_perf_optimization import read,save,sha

def main():
    audit=read(BASE/'audit.json');state=read(ROOT/'verification/implementation_status.json')
    assert audit['status']=='COMPLETE_FUNCTIONAL' and not audit['pending_evidence'] and audit['signed_off']
    assert state['t06_signed_off'] and not state['t06_30fps_verified'] and state['next_execution_task']=='T07'
    cmd=[sys.executable,'-m','unittest','verification.test_t06_release_gate','verification.test_implementation_status',
      'verification.test_t06_evidence.T06EvidenceTests.test_signoff_never_claimed_for_partial_evidence',
      'verification.test_t06_image_release.T06CorrectedReleaseTests.test_no_signoff_without_current_visual_review','-v']
    save(BASE/'final_consistency_command.json',cmd)
    with (BASE/'final_consistency.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    assert r.returncode==0
    source=check_frozen_sources()
    extra=list(ROOT.glob('scripts/*t06*.py'))+list(ROOT.glob('verification/test_t06*.py'))
    extra+=list(ROOT.glob('verification/rtl/tb_t06*.sv'))+list(ROOT.glob('verification/rtl/t06*.svh'))
    extra+=list(ROOT.glob('docs/T06*.md'))
    extra+=[ROOT/f for f in ['AGENTS.md','verification/t06_release_profile.json','verification/implementation_status.json',
      'verification/run_t06.ps1','verification/run_t06_release.ps1','verification/test_implementation_status.py',
      'verification/test_t05_parallel_evidence.py','docs/毕业设计剩余任务执行清单_2026-09-20.md',
      'model/io/scene.py','model/reference/math3d.py','scripts/build_full_frame_rtl_batch.py','scripts/build_full_frame_rtl_batch_stdlib.cpp']]
    for f in extra:source[f.relative_to(ROOT).as_posix()]=sha(f)
    snap=BASE/'release_snapshot'
    for f,h in source.items():
        dest=snap/f;dest.parent.mkdir(parents=True,exist_ok=True)
        if dest.exists():assert sha(dest)==h,('refuse to replace frozen source',f)
        else:shutil.copy2(ROOT/f,dest)
        assert sha(dest)==h
    evidence=dict(audit['evidence_sha256'])
    for f in BASE.rglob('*'):
        if not f.is_file() or snap in f.parents or f.name=='release_manifest.json':continue
        if f.suffix in ['.json','.log','.memh','.png','.rgb','.txt','.ys']:
            evidence[f.relative_to(ROOT).as_posix()]=sha(f)
    full=ROOT/'experiments/t06_full_precount_mem_20261022'
    for n in audit['profile']['scenes']:
        folder=full/n;m=read(folder/'manifest.json')
        for f,h in m['input_sha256'].items():
            assert sha(folder/f)==h;evidence[(folder/f).relative_to(ROOT).as_posix()]=h
        for f in ['manifest.json','expected_sorted.txt','H/result.json','H/command.json','H/run.log','H/sorted.txt','H/rgb.memh','H/state.memh','H/frame.rgb','H/frame.png','oracle/result.json','oracle/run.log','oracle/command.json','oracle/frame.rgb']:
            evidence[(folder/f).relative_to(ROOT).as_posix()]=sha(folder/f)
        float_root=ROOT/('experiments/t06_full_f_20261019/float_refs' if n in ['train','truck'] else 'experiments/t06_20261018/float_full')
        for f in (float_root/n).glob('float_floor_0.30078125_jac_clamp.*'):
            evidence[f.relative_to(ROOT).as_posix()]=sha(f)
    save(BASE/'release_manifest.json',dict(status='FROZEN_FUNCTIONAL_RELEASE',profile_sha256=sha(PROFILE),source_sha256=source,
      evidence_sha256=evidence,source_snapshot='experiments/t06_release_20261022/release_snapshot',
      limitations=audit['limitations'],hardware_30fps_verified=False,
      scope='Source copies immutable; large input/output evidence retained in original named directories with hashes. No mapped PPA claim.'))
    print('FROZEN',len(source),'source files,',len(evidence),'evidence files')
if __name__=='__main__':main()
