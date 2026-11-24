"""Candidate shared-R ordered-window regression; output remains experimental."""
import json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t06_real import sha
OUT=ROOT/'experiments/t06_perf_20261018/units'
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    src=['rtl/common/rv_reg_slice.sv','rtl/raster/blend_fixed_core.sv','rtl/raster/blend_state_commit_4.sv','verification/rtl/tb_t06_shared_window.sv']
    commands=[['D:/IcarusVerilog/iverilog/bin/iverilog.exe','-g2012','-DSYNTHESIS','-s','tb_t06_shared_window','-o',str(OUT/'window.vvp'),*src],['D:/IcarusVerilog/iverilog/bin/vvp.exe',str(OUT/'window.vvp')]]
    for i,cmd in enumerate(commands):
        r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(OUT/f'window_{i}.log').write_text(r.stdout+r.stderr)
        (OUT/f'window_{i}_command.json').write_text(json.dumps(cmd,indent=2));assert r.returncode==0,r.stdout+r.stderr
    assert 'PASS:' in r.stdout
    (OUT/'report.json').write_text(json.dumps(dict(status='PASS',scope='shared-R emulator stalls + 4-entry dual bypass, RAW/order/response/commit backpressure and wrap checks; production real shared slice separately exercised by matrix',source_sha256={f:sha(ROOT/f) for f in src}),indent=2))
    print(r.stdout)
if __name__=='__main__':main()
