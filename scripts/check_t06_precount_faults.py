import json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t06_qsu_units import sha
OUT=ROOT/'experiments/t06_precount_mem_20261022/faults'
def main():
    OUT.mkdir(parents=True,exist_ok=True);rows=[];sources=['rtl/sort/autonomous_qsu.sv','rtl/sort/bitonic_group_sorter_pipelined_shared.sv','rtl/control/shared_reconfigurable_pe_slice.sv']
    for top,args in [('tb_t06_precount_abort',[[f'+ABORT_KIND={i}','+N=256','+ABORT_READ=3'] for i in range(6)]),('tb_t06_precount_backpressure',[['+N=256'],['+N=4097']])]:
        tb=f'verification/rtl/{top}.sv';cmd=[r'D:\IcarusVerilog\iverilog\bin\iverilog.exe','-g2012','-DSYNTHESIS','-s',top,'-o',str(OUT/f'{top}.vvp'),*sources[:3],tb]
        r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(OUT/f'{top}_build.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stderr;sources.append(tb)
        for i,extra in enumerate(args):
            n=4097 if '+N=4097' in extra else 256;folder=ROOT/'experiments/t06_precount_mem_20261022/units'/f'random_{n}'
            cmd=[r'D:\IcarusVerilog\iverilog\bin\vvp.exe',str(OUT/f'{top}.vvp'),*extra,f'+INPUT={(folder/"input.memh").as_posix()}',f'+EXPECTED={(folder/"expected.memh").as_posix()}']
            r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(OUT/f'{top}_{i}.log').write_text(r.stdout+r.stderr);assert r.returncode==0 and 'PASS T06' in r.stdout,r.stdout+r.stderr
            rows.append(dict(top=top,args=extra,status='PASS',command=cmd));print(top,i,'PASS',flush=True)
    (OUT/'report.json').write_text(json.dumps(dict(status='PASS',results=rows,source_sha256={f:sha(ROOT/f) for f in sources}),indent=2))
if __name__=='__main__':main()
