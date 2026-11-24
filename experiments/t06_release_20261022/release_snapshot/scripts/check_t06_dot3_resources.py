"""Confirm real parallel arithmetic in Yosys IR, without claiming mapped PPA."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from asic.scripts.run_t01_synthesis import run_yosys,quote
from scripts.collect_t06_performance_baseline import sha
OUT=ROOT/'experiments/t06_dot3_20261021/resources'
YOSYS=ROOT/'tmp/toolchains/oss-cad-suite-20260706/oss-cad-suite/bin/yosys.exe'
def main():
    OUT.mkdir(parents=True,exist_ok=True);src=ROOT/'rtl/control/shared_reconfigurable_pe_slice.sv';h=sha(src);rows=[]
    for dot,width in [(0,32),(1,96)]:
        script=OUT/f'dot{dot}.ys';net=OUT/f'dot{dot}.json';stats=OUT/f'dot{dot}_stat.json'
        script.write_text('\n'.join([f'read_verilog -sv -DSYNTHESIS {quote(src)}',
          f'chparam -set DATA_W {width} -set RESULT_W 65 -set P_DOT3 {dot} shared_reconfigurable_pe_slice',
          'hierarchy -check -top shared_reconfigurable_pe_slice','proc','opt','wreduce','opt','check -assert',
          f'tee -o {quote(stats)} stat -json',f'write_json {quote(net)}'])+'\n')
        rc,seconds=run_yosys(YOSYS,script,OUT/f'dot{dot}.log',ROOT);assert rc==0,(OUT/f'dot{dot}.log').read_text()[-2000:]
        design=json.loads(net.read_text())['modules']['shared_reconfigurable_pe_slice']
        muls=[dict(A=int(c['parameters']['A_WIDTH'],2),B=int(c['parameters']['B_WIDTH'],2),Y=int(c['parameters']['Y_WIDTH'],2)) for c in design['cells'].values() if c['type']=='$mul']
        assert len(muls)==(3 if dot else 1) and all(x==dict(A=32,B=32,Y=64) for x in muls),muls
        rows.append(dict(dot3=bool(dot),status='PASS',multipliers=muls,seconds=seconds,netlist_sha256=sha(net)));print('PASS DOT3 IR',dot,muls,flush=True)
    assert sha(src)==h
    (OUT/'report.json').write_text(json.dumps(dict(status='PASS',results=rows,source_sha256={'rtl/control/shared_reconfigurable_pe_slice.sv':h},
      scope='generic IR: scalar 1x32-bit multiplier; dot3 3x32-bit multipliers. Two are P-only, primary remains G/P/R shared. Not standard-cell area, STA, SRAM/power or 30FPS signoff'),indent=2))
if __name__=='__main__':main()
