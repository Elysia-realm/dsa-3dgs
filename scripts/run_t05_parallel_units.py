from pathlib import Path
import subprocess,json,sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t05_sorters as old
OUT=ROOT/'experiments/t05_parallel_20261011/units'
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    # Reuse the pinned deterministic oracle inputs; no old results are reused.
    previous=json.loads((ROOT/'experiments/t05_20261009/sorters/report.json').read_text())
    rows=[]
    for k in (8,16):
        spec=next(r for r in previous['results'] if r['k']==k and r['kind']==0)
        for pipeline in (0,1):
            tag=f'k{k}_pipe{pipeline}';exe=OUT/f'{tag}.vvp'
            cmd=[str(old.IVER),'-g2012','-DSYNTHESIS',f'-DT05_K={k}','-DT05_KIND=0',
                 '-s','tb_t05_sorters','-o',str(exe)]
            if pipeline:cmd.append('-DT05_PIPELINED_UNIT')
            cmd+=['rtl/sort/bitonic_group_sorter_shared.sv','rtl/sort/bitonic_group_sorter_pipelined_shared.sv',
                 'rtl/control/shared_reconfigurable_pe_slice.sv','verification/rtl/tb_t05_sorters.sv']
            c=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(OUT/f'{tag}_compile.log').write_text(c.stdout+c.stderr)
            if c.returncode:raise RuntimeError(c.stderr)
            c=subprocess.run([str(old.VVP),str(exe),f'+INPUT={(ROOT/f"experiments/t05_20261009/sorters/k{k}_input.memh").as_posix()}',
                f'+EXPECTED={(ROOT/f"experiments/t05_20261009/sorters/k{k}_expected.memh").as_posix()}',
                f'+GROUPS={spec["groups"]}',f'+OUTPUTS={spec["outputs"]}'],cwd=ROOT,capture_output=True,text=True)
            (OUT/f'{tag}_run.log').write_text(c.stdout+c.stderr)
            if c.returncode:raise RuntimeError(c.stdout[-2000:]+c.stderr)
            rows.append({'k':k,'pipeline':pipeline,'groups':spec['groups'],'outputs':spec['outputs'],'status':'PASS'})
            print(c.stdout.splitlines()[-2:],flush=True)
    (OUT/'report.json').write_text(json.dumps({'status':'PASS','results':rows},indent=2))
if __name__=='__main__':main()
