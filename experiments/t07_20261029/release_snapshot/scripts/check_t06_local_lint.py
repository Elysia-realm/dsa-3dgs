import json,os,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t06_perf_optimization import source_hashes
OUT=ROOT/'experiments/t06_local_20261019/lint'
def main():
    OUT.mkdir(parents=True,exist_ok=True);src=source_hashes()
    cmd=[r'D:\Tools\msys64\usr\bin\bash.exe','-lc','cd /d/3DGS && verilator --lint-only --sv --timing -DSYNTHESIS -Wno-fatal -Irtl/raster --top-module gs_accel_system_top -GAUTO_QSU_LOCAL_RECORDS=256 -GSTATE_WINDOW_ENTRIES=4 -GSTATE_MSHR_COUNT=4 -GENABLE_RESPONSE_BLEND_BYPASS=1 -GENABLE_BLEND_COMMIT_BYPASS=1 -f verification/rtl/system_top_sources.f']
    env=os.environ.copy();env.update(MSYSTEM='UCRT64',CHERE_INVOKING='1');r=subprocess.run(cmd,cwd=ROOT,env=env,capture_output=True,text=True)
    log=r.stdout+r.stderr;(OUT/'lint.log').write_text(log);(OUT/'command.json').write_text(json.dumps(cmd,indent=2))
    bad=re.findall(r'%Warning-(?:LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error',log);assert r.returncode==0 and not bad,log[-2500:]
    assert source_hashes()==src
    (OUT/'report.json').write_text(json.dumps(dict(status='PASS',structural_errors=bad,source_sha256=src),indent=2));print('PASS local-QSU + F production top lint')
if __name__=='__main__':main()
