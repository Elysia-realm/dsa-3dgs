"""Candidate bounded-memory frontend synthesis; not mapped PPA or STA."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from asic.scripts.run_t01_synthesis import run_yosys,quote
from scripts.run_t06_qsu_units import sha
OUT=ROOT/'experiments/t06_precount_mem_20261022/synthesis';YOSYS=ROOT/'tmp/toolchains/oss-cad-suite-20260706/oss-cad-suite/bin/yosys.exe'
def main():
    OUT.mkdir(parents=True,exist_ok=True);src=ROOT/'rtl/sort/autonomous_qsu.sv';frozen=sha(src);rows=[]
    for cap in [0,1]:
        script=OUT/f'local{cap}.ys';stats=OUT/f'local{cap}.json'
        script.write_text('\n'.join([f'read_verilog -sv -DSYNTHESIS {quote(src)}',f'chparam -set PRECOUNT_CHILDREN {cap} autonomous_qsu',
          'hierarchy -check -top autonomous_qsu','proc','opt','memory_dff','memory_collect','opt_clean','check -assert',f'tee -o {quote(stats)} stat -json',f'write_json {quote(OUT/f"local{cap}_netlist.json")}'])+'\n')
        rc,seconds=run_yosys(YOSYS,script,OUT/f'local{cap}.log',ROOT);assert rc==0,(OUT/f'local{cap}.log').read_text()[-2500:]
        net=json.loads((OUT/f'local{cap}_netlist.json').read_text())['modules']['autonomous_qsu']
        memories={name:{k:int(cell['parameters'][k],2) for k in ['WIDTH','SIZE','RD_PORTS','WR_PORTS']} for name,cell in net['cells'].items() if cell['type']=='$mem_v2'}
        if cap:
            assert memories['saved_hist']==dict(WIDTH=1712,SIZE=218,RD_PORTS=1,WR_PORTS=1),memories
        else:assert not memories
        rows.append(dict(precount_children=cap,status='PASS',seconds=seconds,memories=memories,statistics=json.loads(stats.read_text())['modules']['\\autonomous_qsu']));print('PASS local synthesis',cap,flush=True)
    assert sha(src)==frozen
    (OUT/'report.json').write_text(json.dumps(dict(status='PASS',results=rows,source_sha256={'rtl/sort/autonomous_qsu.sv':frozen},
      scope='generic RTL process/memory validation only; no standard-cell area, SRAM mapping, STA, power or 30FPS signoff'),indent=2))
if __name__=='__main__':main()
