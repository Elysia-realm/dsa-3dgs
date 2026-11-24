"""Current default regression and burst-enabled production lint, with logs."""
import json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t06_perf_optimization import source_hashes
OUT=ROOT/'experiments/t06_precount_20261022/compat'
def main():
    OUT.mkdir(parents=True,exist_ok=True);src=source_hashes()
    commands=[
      ('regression',['cmd.exe','/c',r'verification\rtl\run_iverilog.cmd']),
      ('lint',[r'D:\Tools\msys64\usr\bin\bash.exe','-lc','cd /d/3DGS && verilator --lint-only --sv --timing -DSYNTHESIS -Wno-fatal -Irtl/raster --top-module gs_accel_system_top -GAUTO_QSU_PRECOUNT_CHILDREN=1 -GFINAL_RGB_READ_BURST_BEATS=16 -GSHARED_P_DOT3=1 -GENABLE_ALPHA_ZERO_SKIP=1 -GSTATE_WINDOW_ENTRIES=4 -GSTATE_MSHR_COUNT=4 -GENABLE_RESPONSE_BLEND_BYPASS=1 -GENABLE_BLEND_COMMIT_BYPASS=1 -f verification/rtl/system_top_sources.f'])]
    env=os.environ.copy();env.update(MSYSTEM='UCRT64',CHERE_INVOKING='1');rows=[]
    for name,cmd in commands:
        (OUT/f'{name}_command.json').write_text(json.dumps(cmd,indent=2))
        with (OUT/f'{name}.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
        text=(OUT/f'{name}.log').read_text(errors='replace');assert r.returncode==0,text[-2000:]
        if name=='regression':
            assert text.count('PASS: tb_')==80 and 'PASS: all configured' in text
        else:assert not any(x in text for x in ['%Error','%Warning-LATCH','%Warning-UNOPTFLAT','%Warning-MULTIDRIVEN'])
        rows.append(dict(name=name,status='PASS'));print('PASS',name,flush=True)
    assert source_hashes()==src
    (OUT/'report.json').write_text(json.dumps(dict(status='PASS',results=rows,source_sha256=src),indent=2))
if __name__=='__main__':main()
