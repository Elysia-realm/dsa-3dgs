"""Run both mixed-format RTL oracle decks against the actual eight-beat TT netlists."""
from concurrent.futures import ThreadPoolExecutor
import fcntl
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from asic.scripts.run_t01_wsl_synthesis import q,run_stage
from scripts.run_t08_eight_beat_header import OUT as DESIGN
from scripts.run_t08_dual_precision import OUT as DUAL
from scripts.map_t08_early_advance import TOP,LIBRARIES
from scripts.run_t08_q24_compact import edit,freeze
from scripts.t08_common import BASE,WORK,read,save,sha,run_logged

OUT=DESIGN/'gates'
LOCAL=WORK/DESIGN.name/'gates'


def build(spec,refs):
    pdk,rel,*_=spec
    d=OUT/pdk
    d.mkdir(exist_ok=True)
    w=LOCAL/pdk
    w.mkdir(parents=True,exist_ok=True)
    mapped=DESIGN/'mapping'/pdk
    row=read(mapped/'result.json')
    net=mapped/'mapped.v'
    lib=ROOT/rel
    rtl=DESIGN/'build'/(TOP+'.sv')
    for p in (net,lib,rtl):
        assert sha(p)==row['hashes'][str(p)]
    for stage in ('mapping','sta'):
        assert row[stage]['exit_code']==0 and row[stage]['log_sha256']==sha(mapped/(stage+'.log'))
    old=DESIGN/'protocol/1/tb_t08_attribute_dma.sv'
    assert all(r['bench_sha256']==sha(old) and r['rtl_sha256']==sha(rtl) for r in refs)
    bench=d/old.name
    freeze(bench,edit(old.read_text(),"#(.ENABLE_Q24(1'b1),.EARLY_ADVANCE(1'b1)) dut","dut"))
    inputs={str(p):sha(p) for p in (lib,net,bench,Path('/usr/bin/iverilog'),Path('/usr/bin/vvp'))}
    exe=w/'simulation.vvp'
    cells=w/'cells.v'
    marker=d/'binary.json'
    if marker.exists():
        info=read(marker)
        assert info['inputs']==inputs and info['vvp_sha256']==sha(exe) and info['cells_sha256']==sha(cells)
    else:
        run_stage('cell_models',[f'read_liberty -ignore_miss_func -ignore_miss_dir -ignore_miss_data_latch {q(lib)}',
                  f'read_verilog {q(net)}',f'hierarchy -check -top {TOP}','check -assert',f'write_verilog -noattr {q(cells)}'],d)
        run_logged(['/usr/bin/iverilog','-g2012','-s',bench.stem,'-o',str(exe),str(bench),str(cells)],d/'build.log')
        info=dict(exe=str(exe),inputs=inputs,vvp_sha256=sha(exe),cells_sha256=sha(cells))
        save(marker,info)
    return info


def run(pdk,sample,ref,binary):
    variant=ref['variant']
    d=OUT/pdk/('sample' if sample else 'full')/str(variant)
    d.mkdir(parents=True,exist_ok=True)
    x=DUAL/'protocol/enabled'/str(variant)/'input.memh'
    y=BASE/'dma_20261107/expected.memh'
    assert sha(x)==ref['inputs_sha256'] and sha(y)==ref['expected_sha256']
    vectors=x.read_text().splitlines()
    if sample:
        indices=[s*1024+j for s in range(5) for j in range(16)]+list(range(5120,6144,13))
        oracle=y.read_text().splitlines()
        vectors=[vectors[i] for i in indices]
        x,y=d/'input.memh',d/'expected.memh'
        freeze(x,'\n'.join(vectors)+'\n')
        freeze(y,''.join(oracle[i]+'\n' for i in indices))
    beats=0
    for i,word in enumerate(vectors):
        packet=int(word,16)
        size=(packet>>1152)&15
        room=1+(i//4)%8 if (i//32)%2==0 else 8
        beats+=max(size,room) if packet>>1156==2 else size
    if not sample:assert beats==ref['physical_beats'] and len(vectors)==ref['records']
    cmd=['/usr/bin/vvp',binary['exe'],f'+N={len(vectors)}',f'+INPUT={x}',f'+EXPECTED={y}']
    cfg=dict(command=cmd,input_sha256=sha(x),expected_sha256=sha(y),vvp_sha256=binary['vvp_sha256'])
    marker=d/'launch.json'
    if marker.exists():assert read(marker)==cfg
    else:save(marker,cfg)
    ex=d/'run.execution.json'
    if ex.exists() and read(ex)['exit_code']==0:
        assert sha(d/'run.log')==read(ex)['log_sha256']
    else:
        run_logged(cmd,d/'run.log')
    log=(d/'run.log').read_text()
    assert f'PASS T08 attribute DMA data_records={len(vectors)} control_cases=18' in log and f'beats={beats} ' in log
    row=dict(pdk=pdk,sample=sample,variant=variant,records=len(vectors),physical_beats=beats,controls=18,
             execution=read(ex),config=cfg)
    save(d/'result.json',row)
    return row


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            refs=[r for r in read(DESIGN/'protocol/report.json')['results'] if r['early']==1]
            assert len(refs)==2 and {r['variant'] for r in refs}=={0,1}
            save(OUT/'status.json',dict(status='BUILDING',pid=os.getpid(),signed_off=False))
            builds={spec[0]:build(spec,refs) for spec in LIBRARIES}
            rows=[]
            for sample in (True,False):
                save(OUT/'status.json',dict(status='RUNNING_SAMPLE' if sample else 'RUNNING_FULL',pid=os.getpid(),signed_off=False))
                with ThreadPoolExecutor(max_workers=4) as pool:
                    jobs=[pool.submit(run,pdk,sample,r,info) for pdk,info in builds.items() for r in refs]
                    rows.extend(job.result() for job in jobs)
            save(OUT/'report.json',dict(results=rows,builds=builds,script_sha256=sha(__file__),
                 scope='Zero-delay mapped attribute DMA/decoder; Q24 eight-beat enabled, early advance enabled, two TT libraries.',signed_off=False))
            save(OUT/'status.json',dict(status='MAPPED_FUNCTION_CHECKED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise
