"""Identical-vector comparison: external-only QSU versus scatter-time child histograms."""
import json,random,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t06_qsu_units import pack,sha
OUT=ROOT/'experiments/t06_precount_20261022/units'
IVER=r'D:\IcarusVerilog\iverilog\bin\iverilog.exe';VVP=r'D:\IcarusVerilog\iverilog\bin\vvp.exe'
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    shared=['rtl/sort/autonomous_qsu.sv','rtl/sort/bitonic_group_sorter_pipelined_shared.sv','rtl/control/shared_reconfigurable_pe_slice.sv'];sources=shared.copy()
    for v,top in [('B','tb_t06_qsu_bsu'),('H','tb_t06_qsu_bsu')]:
        tb=f'verification/rtl/{top}.sv';sources.append(tb);cmd=[IVER,'-g2012','-DSYNTHESIS',f'-DTB_QSU_PRECOUNT={int(v=="H")}','-s',top,'-o',str(OUT/f'{v}.vvp'),*shared,tb]
        r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(OUT/f'{v}_build.log').write_text(r.stdout+r.stderr)
        (OUT/f'{v}_build_command.json').write_text(json.dumps(cmd));assert r.returncode==0,r.stderr
    rng=random.Random(6019);cases={f'random_{n}':[(rng.randrange(-(1<<26),1<<26),rng.getrandbits(32),i) for i in range(n)] for n in [0,1,15,16,17,31,64,127,255,256,257,512,4097]}
    cases.update(same_depth=[(1234,rng.getrandbits(32),i) for i in range(1025)],same_depth_gid=[(-17,3,1024-i) for i in range(1025)],
      identical_key=[(4,5,6)]*1025,skew=[(5,i,i) for i in range(2048)]+[((1<<26)-1,0,2048),(-(1<<26),0,2049)],
      ascending=[(i,3,i) for i in range(513)],descending=[(512-i,3,512-i) for i in range(513)])
    rows=[]
    for name,data in cases.items():
        folder=OUT/name;folder.mkdir(exist_ok=True)
        for f,vals in [('input.memh',data),('expected.memh',sorted(data))]:(folder/f).write_text(''.join(f'{pack(v):023x}\n' for v in vals))
        pair={}
        for v in ['B','H']:
            cmd=[VVP,str(OUT/f'{v}.vvp'),f'+N={len(data)}',f'+INPUT={(folder/"input.memh").as_posix()}',f'+EXPECTED={(folder/"expected.memh").as_posix()}']
            r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(folder/f'{v}.log').write_text(r.stdout+r.stderr);(folder/f'{v}_command.json').write_text(json.dumps(cmd))
            assert r.returncode==0 and 'PASS T06' in r.stdout,r.stdout+r.stderr
            line=next(x for x in r.stdout.splitlines() if x.startswith('PASS T06'));pair[v]={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)}
        assert pair['H']['reads']<=pair['B']['reads'] and pair['H']['writes']==pair['B']['writes']
        assert pair['H']['leaves']==pair['B']['leaves'] and pair['H']['partitions']==pair['B']['partitions']
        if pair['B']['partitions']>1:
            assert pair['H']['reads']<pair['B']['reads']
            # B reads each internal node twice plus all leaves. H counts root only.
            assert pair['H']['reads']==(pair['B']['reads']-len(data))//2+2*len(data)
        rows.append(dict(name=name,status='PASS',metrics=pair));print(name,pair,flush=True)
    (OUT/'report.json').write_text(json.dumps(dict(status='PASS',results=rows,source_sha256={f:sha(ROOT/f) for f in sources}),indent=2))
if __name__=='__main__':main()
