from pathlib import Path
import sys,random,subprocess,json,re
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t05_sorters import IVER,VVP
OUT=ROOT/'experiments/t05_parallel_20261011/throughput'
def main():
    OUT.mkdir(parents=True,exist_ok=True);results=[]
    for k in (8,16):
      for lanes in (1,2,4):
        words=[];gold=[];rng=random.Random(11505);groups=160
        for g in range(groups):
            stress=int(g>=128);words.append(k|(lanes<<16)|((g%4)<<24)|(stress<<32)|((3 if lanes==1 else 0)<<33))
            records=[(rng.randrange(-32768,32768),rng.randrange(256),rng.randrange(256),i) for i in range(k)]
            words += [((d&65535)<<32)|(gid<<24)|(seq<<16)|i for d,gid,seq,i in records]
            gold += [((((d&65535)<<32)|(gid<<24)|(seq<<16)|v)<<4)|((g%4)<<2)|(int(i==0)<<1)|int(i==k-1)
                     for i,(d,gid,seq,v) in enumerate(sorted(records,key=lambda v:v[:3]))]
        inp=OUT/f'k{k}l{lanes}.memh';exp=OUT/f'k{k}l{lanes}_expected.memh'
        inp.write_text(''.join(f'{x:016x}\n' for x in words));exp.write_text(''.join(f'{x:016x}\n' for x in gold))
        for pipe in (0,1):
            tag=f'k{k}l{lanes}p{pipe}';exe=OUT/f'{tag}.vvp'
            cmd=[str(IVER),'-g2012','-DSYNTHESIS','-DT05_CONTINUOUS',f'-DT05_K={k}','-DT05_KIND=0','-s','tb_t05_sorters','-o',str(exe)]
            if pipe:cmd.append('-DT05_PIPELINED_UNIT')
            cmd+=['rtl/sort/bitonic_group_sorter_shared.sv','rtl/sort/bitonic_group_sorter_pipelined_shared.sv',
                  'rtl/control/shared_reconfigurable_pe_slice.sv','verification/rtl/tb_t05_sorters.sv']
            c=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(OUT/f'{tag}_compile.log').write_text(c.stdout+c.stderr)
            if c.returncode:raise RuntimeError(c.stderr)
            c=subprocess.run([str(VVP),str(exe),f'+INPUT={inp.as_posix()}',f'+EXPECTED={exp.as_posix()}',f'+GROUPS={groups}',f'+OUTPUTS={groups*k}'],
                             cwd=ROOT,capture_output=True,text=True)
            (OUT/f'{tag}_run.log').write_text(c.stdout+c.stderr)
            if c.returncode:raise RuntimeError(c.stdout[-3000:])
            ticks=[int(x) for x in re.findall(r'T05_FIRST cycle=(\d+)',c.stdout)]
            intervals=[b-a for a,b in zip(ticks[16:126],ticks[17:127])]
            overlap=re.search(r'T05_OVERLAP collect_emit=(\d+) multi_stage=(\d+)',c.stdout)
            row={'k':k,'lanes':lanes,'pipeline':pipe,'status':'PASS','first_output_cycle':ticks[0],
                 'steady_max_interval':max(intervals),'steady_mean_interval':sum(intervals)/len(intervals),
                 'collect_emit':int(overlap[1]) if overlap else 0,'multi_stage':int(overlap[2]) if overlap else 0}
            if pipe:assert row['steady_max_interval']<=k+1 and row['collect_emit']>0 and row['multi_stage']>0,row
            results.append(row);print(row,flush=True)
    (OUT/'report.json').write_text(json.dumps({'status':'PASS','results':results},indent=2))
if __name__=='__main__':main()
