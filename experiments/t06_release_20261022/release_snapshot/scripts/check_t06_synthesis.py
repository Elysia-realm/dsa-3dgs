"""Actual Yosys front-end/process/memory validation; not a mapped PPA claim."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from asic.scripts.run_t01_synthesis import run_yosys,quote
from scripts.run_t06_qsu_units import sha
YOSYS=ROOT/'tmp/toolchains/oss-cad-suite-20260706/oss-cad-suite/bin/yosys.exe'
OUT=ROOT/'experiments/t06_20261014/synthesis_v2'
FILES=['rtl/sort/autonomous_qsu.sv','rtl/dma/axi4_qsu_scratch_dma.sv']
def main():
    OUT.mkdir(parents=True,exist_ok=True);rows=[]
    for file in FILES:
        top=Path(file).stem;script=OUT/f'{top}.ys';stats=OUT/f'{top}.json';il=OUT/f'{top}.il'
        script.write_text('\n'.join([f'read_verilog -sv -DSYNTHESIS {quote(ROOT/file)}',f'hierarchy -check -top {top}',
            'proc','opt','memory_dff','memory_collect','opt_clean','check -assert',f'tee -o {quote(stats)} stat -json',f'write_rtlil {quote(il)}'])+'\n')
        rc,seconds=run_yosys(YOSYS,script,OUT/f'{top}.log',ROOT)
        assert rc==0,(OUT/f'{top}.log').read_text()[-3000:]
        stat=json.loads(stats.read_text())['modules']['\\'+top]
        rows.append({'module':top,'status':'PASS','seconds':seconds,'statistics':stat,'rtlil_sha256':sha(il)})
        print(top,'PASS',flush=True)
    report={'status':'PASS','results':rows,'source_sha256':{f:sha(ROOT/f) for f in FILES},'yosys_sha256':sha(YOSYS),
            'scope':'actual RTL->process/memory IR with check -assert; generic memory retained explicitly, NOT mapped area/STA/power signoff',
            'default_key_bits':91,'dfs_entries':218,'dfs_payload_bits':53846,'dual_leaf_payload_bits':2912,'writer_payload_address_bits':3072}
    (OUT/'report.json').write_text(json.dumps(report,indent=2))
if __name__=='__main__':main()
