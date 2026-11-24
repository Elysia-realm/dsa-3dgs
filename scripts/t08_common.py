"""T08 native-only paths and immutable baseline provenance."""
import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.t01_resume_common import read, save, sha, run_logged

BASE = ROOT / 'experiments/t08_20261031'
WORK = Path.home() / 'work/t08_20261031'
T07 = ROOT / 'experiments/t07_20261029'
PROFILE = ROOT / 'verification/t07_release_profile.json'
SCENES = read(PROFILE)['scenes']
MAX_COUNT = 2600000  # diagnostic harness capacity; does not change production QSU capacity
MAX_PIXELS = 6500000


def freeze_baseline():
    assert os.name == 'posix' and ROOT.as_posix() == '/mnt/d/3DGS'
    signoff = read(T07 / 'signoff.json')
    assert signoff['signed_off'] and signoff['task'] == 'T07'
    manifest = read(T07 / 'release_snapshot/manifest.json')
    assert sha(T07 / 'release_snapshot/manifest.json') == signoff['snapshot_manifest_sha256']
    names = {f for f in manifest if f.startswith(('rtl/', 'verification/rtl/'))}
    names.update(['verification/t07_release_profile.json', 'model/io/scene.py',
                  'model/io/dma_workload.py', 'model/reference.py'])
    # Some model versions use a package rather than model/reference.py.
    names = {f for f in names if (ROOT / f).is_file()}
    for f in sorted(names):
        if f in manifest:
            assert sha(ROOT / f) == manifest[f].upper(), ('T07 source mismatch', f)
    source = {f: sha(ROOT / f) for f in sorted(names)}
    destination = BASE / 'baseline_snapshot'
    for f, h in source.items():
        out = destination / f
        out.parent.mkdir(parents=True, exist_ok=True)
        if out.exists():
            assert sha(out) == h, ('baseline cannot be overwritten', f)
        else:
            shutil.copy2(ROOT / f, out)
    marker = destination / 'manifest.json'
    if marker.exists():
        assert read(marker) == source
    else:
        save(marker, source)
        save(BASE / 'implementation_status_before.json', read(ROOT / 'verification/implementation_status.json'))
        save(BASE / 'baseline_profile.json', read(PROFILE))
    WORK.mkdir(parents=True, exist_ok=True)
    return source


def production_sources():
    baseline = read(BASE / 'baseline_snapshot/manifest.json')
    names = {f for f in baseline if f.startswith('rtl/')}
    names.update(x.strip() for x in (ROOT / 'verification/rtl/system_top_sources.f').read_text().splitlines() if x.strip())
    names.add('verification/rtl/system_top_sources.f')
    return {f: sha(ROOT / f) for f in sorted(names)}


if __name__ == '__main__':
    print('T08 baseline frozen:', len(freeze_baseline()), 'files')
