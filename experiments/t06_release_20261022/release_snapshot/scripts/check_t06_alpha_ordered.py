import json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t06_perf_optimization import source_hashes,sha
OUT=ROOT/'experiments/t06_alpha_20261020/units'
def main():
    OUT.mkdir(parents=True,exist_ok=True);tb='verification/rtl/tb_t06_alpha_ordered.sv';src=source_hashes();src[tb]=sha(ROOT/tb)
    cmd=[r'D:\IcarusVerilog\iverilog\bin\iverilog.exe','-g2012','-DSYNTHESIS','-Irtl/raster','-s','tb_t06_alpha_ordered','-o',str(OUT/'alpha.vvp'),'-f','verification/rtl/system_top_sources.f',tb]
    r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(OUT/'build.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stderr
    run=[r'D:\IcarusVerilog\iverilog\bin\vvp.exe',str(OUT/'alpha.vvp')];r=subprocess.run(run,cwd=ROOT,capture_output=True,text=True)
    (OUT/'run.log').write_text(r.stdout+r.stderr);assert r.returncode==0 and 'PASS:' in r.stdout,r.stdout+r.stderr
    (OUT/'report.json').write_text(json.dumps(dict(status='PASS',build_command=cmd,run_command=run,source_sha256=src,
      scope='same-pixel nonzero/zero/below-threshold interleave, output stalls, shared-R emulator stalls, 4-entry dual-bypass and 4-MSHR cache'),indent=2))
    print(r.stdout)
if __name__=='__main__':main()
