"""Protocol/recovery release evidence, including the T06 half-leaf regression."""
import json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t06_real import sources,sha
OUT=ROOT/'experiments/t06_20261014/protocol_v2'
IVER=r'D:\IcarusVerilog\iverilog\bin\iverilog.exe';VVP=r'D:\IcarusVerilog\iverilog\bin\vvp.exe'
def main():
    OUT.mkdir(parents=True,exist_ok=True);rows=[]
    cases=[('tb_t06_scratch_dma',['rtl/dma/axi4_qsu_scratch_dma.sv'],[[]]),
           ('tb_t06_qsu_abort',['rtl/sort/autonomous_qsu.sv','rtl/sort/bitonic_group_sorter_pipelined_shared.sv','rtl/control/shared_reconfigurable_pe_slice.sv'],
            [['+N=16','+ABORT_READ=3','+INPUT=experiments/t06_20261014/units/random_16/input.memh','+EXPECTED=experiments/t06_20261014/units/random_16/expected.memh'],
             ['+N=1025','+ABORT_READ=19','+INPUT=experiments/t06_20261014/units/identical_key/input.memh','+EXPECTED=experiments/t06_20261014/units/identical_key/expected.memh']]),
           ('tb_t06_system_recovery',['-f','verification/rtl/system_top_sources.f'],[[f'+FAULT={i}'] for i in range(10)]),
           ('tb_t06_backpressure',['rtl/sort/autonomous_qsu.sv','rtl/sort/bitonic_group_sorter_pipelined_shared.sv','rtl/control/shared_reconfigurable_pe_slice.sv'],
            [[f'+N={n}',f'+INPUT=experiments/t06_20261014/units_v2/random_{n}/input.memh',f'+EXPECTED=experiments/t06_20261014/units_v2/random_{n}/expected.memh'] for n in [512,4097]])]
    files=sources()
    for top,src,runs in cases:
        tb=f'verification/rtl/{top}.sv';files[tb]=sha(ROOT/tb)
        cmd=[IVER,'-g2012','-DSYNTHESIS','-Irtl/raster','-s',top,'-o',str(OUT/f'{top}.vvp'),*src,tb]
        r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(OUT/f'{top}_build.log').write_text(r.stdout+r.stderr)
        (OUT/f'{top}_build_command.json').write_text(json.dumps(cmd,indent=2));assert r.returncode==0,r.stderr[-3000:]
        for i,args in enumerate(runs):
            cmd=[VVP,str(OUT/f'{top}.vvp'),*args];r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)
            (OUT/f'{top}_{i}.log').write_text(r.stdout+r.stderr);(OUT/f'{top}_{i}_command.json').write_text(json.dumps(cmd,indent=2))
            assert r.returncode==0 and 'PASS T06' in r.stdout,(top,args,r.stdout+r.stderr)
            rows.append({'top':top,'args':args,'status':'PASS','log':f'{top}_{i}.log'});print(top,i,'PASS',flush=True)
    for f,h in files.items():assert sha(ROOT/f)==h,'source changed during verification: '+f
    (OUT/'report.json').write_text(json.dumps({'status':'PASS','results':rows,'source_sha256':files},indent=2))
if __name__=='__main__':main()
