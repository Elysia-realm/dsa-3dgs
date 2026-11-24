"""T07 native WSL evidence helpers; never overwrite the frozen T01/T06 release."""
import sys, shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import read,save,sha,run_logged
BASE=ROOT/'experiments/t07_20261029'
WORK=Path.home()/'work/t07_20261029'
T01=ROOT/'experiments/t01_resume_20261025'
PROFILE=ROOT/'verification/t06_release_profile.json'
VERILATOR=str(Path.home()/'eda/opt/oss-cad-suite-20260706/oss-cad-suite/bin/verilator')

def source_manifest():
    names=set(read(T01/'frozen_source_manifest.json'))
    names.update(x.strip() for x in (ROOT/'verification/rtl/system_top_sources.f').read_text().splitlines() if x.strip())
    return {f:sha(ROOT/f) for f in sorted(names)}

def snapshot(name, sources):
    dest=BASE/name
    for f,h in sources.items():
        p=dest/f;p.parent.mkdir(parents=True,exist_ok=True)
        if p.exists():assert sha(p)==h.upper(),('snapshot drift',f)
        else:shutil.copy2(ROOT/f,p)
    save(dest/'manifest.json',sources)

def initialize():
    assert ROOT.as_posix()=='/mnt/d/3DGS'
    BASE.mkdir(parents=True,exist_ok=True);WORK.mkdir(parents=True,exist_ok=True)
    before=BASE/'source_before/manifest.json'
    if not before.exists():
        old=read(T01/'frozen_source_manifest.json')
        assert all(sha(ROOT/f)==h.upper() for f,h in old.items())
        snapshot('source_before',old)
        save(BASE/'implementation_status_before.json',read(ROOT/'verification/implementation_status.json'))
        save(BASE/'baseline_profile.json',read(PROFILE))
    return BASE

if __name__=='__main__':
    initialize();print(BASE)
