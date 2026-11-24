"""Candidate bounded-memory frontend synthesis; not mapped PPA or STA."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from asic.scripts.run_t01_synthesis import run_yosys,quote
from scripts.run_t06_qsu_units import sha
OUT=ROOT/'experiments/t06_local_20261019/synthesis';YOSYS=ROOT/'tmp/toolchains/oss-cad-suite-20260706/oss-cad-suite/bin/yosys.exe'
def main():
    OUT.mkdir(parents=True,exist_ok=True);src=ROOT/'rtl/sort/autonomous_qsu.sv';frozen=sha(src);rows=[]
    for cap in [0,256]:
        script=OUT/f'local{cap}.ys';stats=OUT/f'local{cap}.json'
        script.write_text('\n'.join([f'read_verilog -sv -DSYNTHESIS {quote(src)}',f'chparam -set LOCAL_RECORDS {cap} autonomous_qsu',
          'hierarchy -check -top autonomous_qsu','proc','opt','memory_dff','memory_collect','opt_clean','check -assert',f'tee -o {quote(stats)} stat -json'])+'\n')
        rc,seconds=run_yosys(YOSYS,script,OUT/f'local{cap}.log',ROOT);assert rc==0,(OUT/f'local{cap}.log').read_text()[-2500:]
        rows.append(dict(local_records=cap,status='PASS',seconds=seconds,statistics=json.loads(stats.read_text())['modules']['\\autonomous_qsu']));print('PASS local synthesis',cap,flush=True)
    assert sha(src)==frozen
    (OUT/'report.json').write_text(json.dumps(dict(status='PASS',results=rows,source_sha256={'rtl/sort/autonomous_qsu.sv':frozen},
      scope='generic RTL process/memory validation only; no standard-cell area, SRAM mapping, STA, power or 30FPS signoff'),indent=2))
if __name__=='__main__':main()
