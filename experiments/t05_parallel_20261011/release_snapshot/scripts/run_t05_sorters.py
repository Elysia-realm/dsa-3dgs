"""Software stable-key oracle and same-input sorter cycle comparisons."""
from pathlib import Path
import subprocess,random,json,hashlib
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'experiments/t05_20261009/sorters'
IVER=Path(r'D:\IcarusVerilog\iverilog\bin\iverilog.exe')
VVP=IVER.with_name('vvp.exe')

def main():
    OUT.mkdir(parents=True,exist_ok=True);results=[]
    for k in (8,16):
        randomizer=random.Random(50109);input_words=[];expected=[];group_count=0
        for stress in (0,1):
            for lanes in (1,2,4):
                for case in range(110):
                    count=case if case<=k else k if case%5==0 else randomizer.randint(1,k)
                    group=case%4;owner=case%4
                    input_words.append(count|(lanes<<16)|(group<<24)|(stress<<32)|(owner<<33))
                    records=[]
                    for i in range(count):
                        d,g,s=randomizer.randint(-32768,32767),randomizer.randrange(8),randomizer.randrange(4)
                        if case%5==0:d=i
                        if case%5==1:d=count-i
                        if case%5==2:d=-32768 if i%2 else 32767
                        if case%5==3:d,g,s=12,3,7
                        records.append((d,g,s,i))
                    for d,g,s,p in records:input_words.append(((d&65535)<<32)|(g<<24)|(s<<16)|p)
                    for i,(d,g,s,p) in enumerate(sorted(records,key=lambda v:v[:3])):
                        record=((d&65535)<<32)|(g<<24)|(s<<16)|p
                        expected.append((record<<4)|(group<<2)|(int(i==0)<<1)|int(i==count-1))
                    group_count+=1
        inp=OUT/f'k{k}_input.memh';exp=OUT/f'k{k}_expected.memh'
        inp.write_text(''.join(f'{v:016x}\n' for v in input_words),encoding='ascii')
        exp.write_text(''.join(f'{v:016x}\n' for v in expected),encoding='ascii')
        for kind in (0,1,2):
            exe=OUT/f'k{k}_kind{kind}.vvp'
            cmd=[str(IVER),'-g2012','-DSYNTHESIS',f'-DT05_K={k}',f'-DT05_KIND={kind}',
                 '-s','tb_t05_sorters','-o',str(exe),
                 'rtl/sort/bitonic_group_sorter_shared.sv','rtl/sort/stable_group_sorter_shared_compare.sv',
                 'rtl/sort/stable_group_sorter_parallel_shared.sv','rtl/control/shared_reconfigurable_pe_slice.sv',
                 'verification/rtl/tb_t05_sorters.sv']
            c=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)
            (OUT/f'k{k}_kind{kind}_compile.log').write_text(c.stdout+c.stderr)
            if c.returncode:raise RuntimeError(c.stderr)
            run=[str(VVP),str(exe),f'+INPUT={inp.as_posix()}',f'+EXPECTED={exp.as_posix()}',f'+GROUPS={group_count}',f'+OUTPUTS={len(expected)}']
            c=subprocess.run(run,cwd=ROOT,capture_output=True,text=True)
            (OUT/f'k{k}_kind{kind}_run.log').write_text(c.stdout+c.stderr)
            if c.returncode:raise RuntimeError(c.stdout[-2000:]+c.stderr)
            results.append({'k':k,'kind':kind,'groups':group_count,'outputs':len(expected),'status':'PASS','commands':[cmd,run],
                            'input_sha256':hashlib.sha256(inp.read_bytes()).hexdigest()})
            print(c.stdout.splitlines()[-2:],flush=True)
    (OUT/'report.json').write_text(json.dumps({'status':'PASS','results':results},indent=2))

if __name__=='__main__':main()
