"""Independent global oracle against real QSU + production spatial BSU RTL."""
import hashlib,json,random,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'experiments/t06_20261014/units_v2'
IVER=r'D:\IcarusVerilog\iverilog\bin\iverilog.exe'
VVP=r'D:\IcarusVerilog\iverilog\bin\vvp.exe'
FILES=['rtl/sort/autonomous_qsu.sv','rtl/sort/bitonic_group_sorter_pipelined_shared.sv',
       'rtl/control/shared_reconfigurable_pe_slice.sv','verification/rtl/tb_t06_qsu_bsu.sv']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def pack(v):d,g,s=v;return ((d&((1<<27)-1))<<64)|(g<<32)|s
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    cmd=[IVER,'-g2012','-DSYNTHESIS','-s','tb_t06_qsu_bsu','-o',str(OUT/'test.vvp'),*FILES]
    build=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)
    (OUT/'build.log').write_text(build.stdout+build.stderr);(OUT/'build_command.json').write_text(json.dumps(cmd))
    if build.returncode:raise RuntimeError(build.stderr)
    rng=random.Random(60014)
    cases={}
    for n in [0,1,15,16,17,31,64,127,512,4097]:
        cases[f'random_{n}']=[(rng.randrange(-(1<<26),1<<26),rng.getrandbits(32),i) for i in range(n)]
    cases['same_depth']=[(1234,rng.getrandbits(32),i) for i in range(1025)]
    cases['same_depth_gid']=[(-17,3,1024-i) for i in range(1025)]
    cases['identical_key']=[(4,5,6)]*1025
    cases['skew']=[(5,i,i) for i in range(2048)]+[((1<<26)-1,0,2048),(-(1<<26),0,2049)]
    cases['ascending']=[(i,3,i) for i in range(513)]
    cases['descending']=list(reversed(cases['ascending']))
    rows=[]
    for name,values in cases.items():
        p=OUT/name;p.mkdir(exist_ok=True)
        for file,data in [('input.memh',values),('expected.memh',sorted(values))]:
            (p/file).write_text(''.join(f'{pack(v):023x}\n' for v in data))
        cmd=[VVP,str(OUT/'test.vvp'),f'+N={len(values)}',f'+INPUT={(p/"input.memh").as_posix()}',f'+EXPECTED={(p/"expected.memh").as_posix()}']
        r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)
        (p/'run.log').write_text(r.stdout+r.stderr);(p/'command.json').write_text(json.dumps(cmd))
        if r.returncode or 'PASS T06' not in r.stdout:raise RuntimeError(f'{name}: {r.stdout}{r.stderr}')
        print(name,r.stdout.strip(),flush=True);rows.append({'name':name,'n':len(values),'status':'PASS','result':r.stdout.strip()})
    (OUT/'report.json').write_text(json.dumps({'status':'PASS','results':rows,'source_sha256':{f:sha(ROOT/f) for f in FILES}},indent=2))
if __name__=='__main__':main()
