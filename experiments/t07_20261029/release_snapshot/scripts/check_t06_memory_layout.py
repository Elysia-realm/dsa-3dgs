"""Positive and expected-failure RTL tests of the shared address guard."""
import json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t06_real import sha
OUT=ROOT/'experiments/t06_20261018/memory_layout_units'
IVER=r'D:\IcarusVerilog\iverilog\bin\iverilog.exe'
VVP=r'D:\IcarusVerilog\iverilog\bin\vvp.exe'
def main():
    OUT.mkdir(parents=True,exist_ok=True);rows=[]
    for name,count,pixels,fault,expected in [
        ('valid_capacity',7000000,16384,0,None),
        ('below_region',7000000,16384,1,'AXI region violation'),
        ('past_region',7000000,16384,2,'AXI region violation'),
        ('address_wrap',7000000,16384,3,'AXI region violation'),
        ('zero_length',7000000,16384,4,'AXI region violation'),
        ('scratch_overlap',8500000,16384,0,'overlapping or overflowing'),
        ('output_overflow',7000000,9000000,0,'overlapping or overflowing')]:
        binary=OUT/f'{name}.vvp'
        build=[IVER,'-g2012','-s','tb_t06_memory_layout',f'-Ptb_t06_memory_layout.MAX_COUNT={count}',
               f'-Ptb_t06_memory_layout.MAX_PIXELS={pixels}','-o',str(binary),'verification/rtl/tb_t06_memory_layout.sv']
        r=subprocess.run(build,cwd=ROOT,capture_output=True,text=True);assert r.returncode==0,r.stderr
        cmd=[VVP,str(binary),f'+FAULT={fault}'];r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)
        (OUT/f'{name}.log').write_text(r.stdout+r.stderr,encoding='utf-8')
        assert (r.returncode==0 and 'PASS T06' in r.stdout) if expected is None else (r.returncode!=0 and expected in r.stdout),(name,r)
        rows.append(dict(name=name,status='PASS',expected_rejection=expected is not None,returncode=r.returncode,build=build,command=cmd))
    sources=['verification/rtl/t06_memory_layout.svh','verification/rtl/tb_t06_memory_layout.sv','scripts/check_t06_memory_layout.py']
    (OUT/'report.json').write_text(json.dumps(dict(status='PASS',results=rows,source_sha256={p:sha(ROOT/p) for p in sources}),indent=2))
    print('PASS T06 address guard: 1 valid configuration, 6 correctly rejected errors')
if __name__=='__main__':main()
