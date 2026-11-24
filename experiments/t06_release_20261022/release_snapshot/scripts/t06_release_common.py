"""Explicit production profile binding; generic defaults are compatibility only."""
import re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t06_perf_optimization as p
BASE=ROOT/'experiments/t06_release_20261022'
PROFILE=ROOT/'verification/t06_release_profile.json'
OLD=ROOT/'experiments/t06_precount_mem_20261022/real'

def profile():return p.read(PROFILE)
def bindings(bench='tb_t06_rgb_workload'):
    text=(ROOT/f'verification/rtl/{bench}.sv').read_text()
    inst=text.split('gs_accel_system_top #(',1)[1].split(')dut(',1)[0]
    return dict(re.findall(r'\.([A-Z][A-Z0-9_]+)\(`(TB_[A-Z0-9_]+)\)',inst))
def integer(s):
    if "'" in s:
        _,v=s.split("'",1);return int(v[1:],{'b':2,'d':10,'h':16}[v[0]])
    return int(s)
def assert_command_profile(command,bench='tb_t06_rgb_workload'):
    params=profile()['parameters'];mapping=bindings(bench)
    defs=dict(re.findall(r'-D(TB_[A-Z0-9_]+)=(\d+)', ' '.join(command)))
    tb=(ROOT/f'verification/rtl/{bench}.sv').read_text()
    defaults=dict(re.findall(r'`define\s+(TB_[A-Z0-9_]+)\s+(\d+)',tb))
    top=(ROOT/'rtl/gs_accel_system_top.sv').read_text().split(') (',1)[0]
    observed={}
    for name,value in params.items():
        if name in mapping:
            macro=mapping[name];observed[name]=int(defs.get(macro,defaults.get(macro,'-999')))
        else:
            m=re.search(r'\b'+name+r"\s*=\s*([0-9]+(?:'[bdh][0-9a-fA-F]+)?)",top)
            assert m,(name,'missing default');observed[name]=integer(m[1])
        assert observed[name]==value,(name,observed[name],value)
    return observed
def configure(bench='tb_t06_rgb_workload',suffix='release'):
    cfg=profile();p.BASE=BASE;p.DATA=BASE/'subset';p.SCENES=cfg['scenes']
    p.BUILD_TAG='release_20261022' if suffix=='release' else f'release_{suffix}_20261022'
    p.BENCH_TOP=bench;p.VARIANTS={'H':(4,4,1,1)}
    mapping=bindings(bench)
    p.EXTRA_DEFINES={'H':[f'-D{mapping[k]}={v}' for k,v in cfg['parameters'].items() if k in mapping]}
    return p
def check_frozen_sources():
    manifest=p.read(ROOT/profile()['frozen_source_manifest'])
    required={f.strip() for f in (ROOT/'verification/rtl/system_top_sources.f').read_text().splitlines() if f.strip()}
    required|={f.relative_to(ROOT).as_posix() for f in ROOT.glob('rtl/**/*.svh')}
    required|={'verification/rtl/system_top_sources.f','verification/rtl/tb_t06_rgb_workload.sv','verification/rtl/t06_perf_measurements.svh','verification/rtl/t06_memory_layout.svh','verification/rtl/t06_memory_scratch.svh','verification/rtl/t06_scratch_signals.svh'}
    assert required<=manifest.keys(),('incomplete frozen manifest',sorted(required-manifest.keys()))
    for f,h in manifest.items():assert p.sha(ROOT/f)==h,('release source drift',f)
    return manifest
