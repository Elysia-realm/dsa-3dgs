"""All Gaussian keys (including depth-culled records) through QSU+BSU.

This is separate module-capacity evidence; production full rendering remains
the frozen real DMA run. Python computes only this test's inputs and oracle.
"""
import os,re,subprocess,sys,time,traceback
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t06_release_common import BASE,profile
from scripts.run_t06_perf_optimization import read,save,sha
OUT=BASE/'full_order';DATA=ROOT/'experiments/t06_full_precount_mem_20261022'
FILES=['rtl/sort/autonomous_qsu.sv','rtl/sort/bitonic_group_sorter_pipelined_shared.sv','rtl/control/shared_reconfigurable_pe_slice.sv','verification/rtl/tb_t06_qsu_bsu.sv']
EXE=ROOT/'tmp/verilator_t06_release_full_order/t06_order.exe'

def prepare(n):
    dest=OUT/n;dest.mkdir(parents=True,exist_ok=True);src=DATA/n;m=read(src/'manifest.json')
    for f,h in m['input_sha256'].items():assert sha(src/f)==h
    if (dest/'manifest.json').exists():
        old=read(dest/'manifest.json');assert old['input_sha256']==sha(src/'mean.memh')
        for f,h in old['vectors_sha256'].items():assert sha(dest/f)==h
        return old
    cam=[int(v,16) for v in (src/'camera.memh').read_text().split()]
    signed=lambda v,b:v-(1<<b) if v>>(b-1) else v
    rotation=[signed(v,64) for v in cam[6:9]];translation=signed(cam[11],64)
    values=[]
    with (src/'mean.memh').open() as f:
        for seq,line in enumerate(f):
            word=int(line,16);gid=word&0xffffffff
            xyz=[signed((word>>(32+27*k))&((1<<27)-1),27) for k in range(3)]
            acc=sum(a*b for a,b in zip(xyz,rotation))+(translation<<20)
            d=((abs(acc)+(1<<19))>>20)*(1 if acc>=0 else -1)
            assert -(1<<26)<=d<(1<<26)
            values.append((d,gid,seq))
    assert len(values)==m['gaussians']
    for filename,rows in [('input.memh',values),('expected.memh',sorted(values))]:
        with (dest/filename).open('w') as f:
            f.writelines(f'{((d&((1<<27)-1))<<64)|(g<<32)|s:023x}\n' for d,g,s in rows)
    meta=dict(scene=n,gaussians=len(values),camera_index=m['camera_index'],full_scene=True,
      input_sha256=sha(src/'mean.memh'),camera_sha256=sha(src/'camera.memh'),
      vectors_sha256={f:sha(dest/f) for f in ['input.memh','expected.memh']},
      scope='all model records, no depth visibility cull; module QSU+BSU capacity/order evidence only')
    save(dest/'manifest.json',meta);return meta
def main():
    source={f:sha(ROOT/f) for f in FILES};save(OUT/'status.json',dict(status='BUILDING',pid=os.getpid()))
    cmd=[r'D:\Tools\msys64\usr\bin\bash.exe','-lc','cd /d/3DGS && verilator --binary --build -j 2 -CFLAGS -D_GLIBCXX_USE_CXX11_ABI=0 --sv --timing -Wno-fatal -DSYNTHESIS -DT06_MAX_COUNT=7000000 -DTB_QSU_PRECOUNT=1 --top-module tb_t06_qsu_bsu --Mdir tmp/verilator_t06_release_full_order '+' '.join(FILES)+' -o t06_order.exe']
    env=os.environ.copy();env.update(MSYSTEM='UCRT64',CHERE_INVOKING='1');env['PATH']=r'D:\Tools\msys64\ucrt64\bin;'+env['PATH']
    save(OUT/'build_command.json',cmd)
    if not (OUT/'executable_block.json').exists():
        with (OUT/'build.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
        assert r.returncode==0,(OUT/'build.log').read_text()[-3000:]
    interpreter=None
    if (OUT/'executable_block.json').exists():
        interpreter=OUT/'order.vvp'
        compile_cmd=[r'D:\IcarusVerilog\iverilog\bin\iverilog.exe','-g2012','-DSYNTHESIS','-DT06_MAX_COUNT=7000000','-DTB_QSU_PRECOUNT=1','-s','tb_t06_qsu_bsu','-o',str(interpreter),*FILES]
        save(OUT/'icarus_command.json',compile_cmd)
        with (OUT/'icarus_build.log').open('w') as log:r=subprocess.run(compile_cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
        assert r.returncode==0,(OUT/'icarus_build.log').read_text()[-3000:]
    save(OUT/'status.json',dict(status='RUNNING',pid=os.getpid()));binary=sha(EXE)
    def run(n):
        m=prepare(n);d=OUT/n;cmd=[str(EXE),f'+N={m["gaussians"]}',f'+INPUT={(d/"input.memh").as_posix()}',f'+EXPECTED={(d/"expected.memh").as_posix()}']
        if interpreter:cmd=[r'D:\IcarusVerilog\iverilog\bin\vvp.exe',str(interpreter),*cmd[1:]]
        save(d/'command.json',cmd);start=time.monotonic()
        with (d/'run.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
        text=(d/'run.log').read_text();assert r.returncode==0 and 'PASS T06' in text,text[-2000:]
        line=next(x for x in text.splitlines() if x.startswith('PASS T06'));metrics={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)}
        assert metrics['n']==m['gaussians'];row=dict(scene=n,status='PASS',metrics=metrics,seconds=time.monotonic()-start,source_sha256=source,binary_sha256=sha(interpreter) if interpreter else binary,simulator='icarus' if interpreter else 'verilator',manifest_sha256=sha(d/'manifest.json'),log_sha256=sha(d/'run.log'))
        save(d/'result.json',row);print('PASS full order',n,metrics,flush=True);return row
    with ThreadPoolExecutor(max_workers=2) as pool:rows=list(pool.map(run,profile()['scenes']))
    assert all(sha(ROOT/f)==h for f,h in source.items()) and sha(EXE)==binary
    save(OUT/'report.json',dict(status='PASS',results=rows,source_sha256=source));save(OUT/'status.json',dict(status='PASS'))
if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main()
        except BaseException as e:save(OUT/'status.json',dict(status='FAILED',error=repr(e)));traceback.print_exc();raise
