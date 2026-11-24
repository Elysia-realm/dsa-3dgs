"""Run both complementary mixed-format decks on each frozen dual DMA TT netlist."""
from concurrent.futures import ThreadPoolExecutor
import fcntl
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from asic.scripts.run_t01_wsl_synthesis import q,run_stage
from scripts.map_t08_early_advance import LIBRARIES,TOP
from scripts.map_t08_dual_dma import OUT as COST
from scripts.run_t08_dual_precision import OUT as DUAL
from scripts.run_t08_q24_compact import edit,freeze
from scripts.t08_common import BASE,WORK,read,save,sha,run_logged

OUT=BASE/'dual_dma_gates_20261122'
LOCAL=WORK/OUT.name


def build(spec):
    pdk,rel,*_=spec
    mapped=COST/pdk/'mapped.v'
    lib=ROOT/rel
    row=read(COST/pdk/'result.json')
    for path in (mapped,lib):
        assert sha(path)==row['hashes'][str(path)]
    rtlbench=DUAL/'protocol/enabled/tb_t08_attribute_dma.sv'
    oracle=read(DUAL/'protocol/report.json')
    assert all(r['sources'][str(rtlbench.relative_to(ROOT))]==sha(rtlbench) for r in oracle['results'] if r['enabled'])
    d=OUT/pdk
    w=LOCAL/pdk
    w.mkdir(parents=True,exist_ok=True)
    d.mkdir(exist_ok=True)
    bench=d/rtlbench.name
    freeze(bench,edit(rtlbench.read_text(),"#(.ENABLE_Q24(1'b1),.EARLY_ADVANCE(1'b1)) dut","dut"))
    cells=w/'cells.v'
    exe=w/'dma.vvp'
    marker=d/'build.json'
    inputs={str(p):sha(p) for p in (mapped,lib,bench,Path('/usr/bin/iverilog'),Path('/usr/bin/vvp'))}
    if marker.exists():
        info=read(marker)
        assert info['inputs']==inputs and sha(exe)==info['binary_sha256'] and sha(cells)==info['cells_sha256']
    else:
        run_stage('cell_models',[f'read_liberty -ignore_miss_func -ignore_miss_dir -ignore_miss_data_latch {q(lib)}',
                  f'read_verilog {q(mapped)}',f'hierarchy -check -top {TOP}','check -assert',f'write_verilog -noattr {q(cells)}'],d)
        run_logged(['/usr/bin/iverilog','-g2012','-s',bench.stem,'-o',str(exe),str(bench),str(cells)],d/'build.log')
        info=dict(inputs=inputs,exe=str(exe),binary_sha256=sha(exe),cells_sha256=sha(cells))
        save(marker,info)
    return info


def run_deck(pdk,variant,binary,sample):
    rtl=DUAL/'protocol/enabled'/str(variant)
    inputs=rtl/'input.memh'
    expected=BASE/'dma_20261107/expected.memh'
    ref=next(r for r in read(DUAL/'protocol/report.json')['results'] if r['enabled'] and r['variant']==variant)
    assert sha(inputs)==ref['inputs_sha256'] and sha(expected)==ref['expected_sha256']
    count=ref['records']
    beats=ref['beats']
    d=OUT/pdk/('probe' if sample else 'full')/str(variant)
    d.mkdir(parents=True,exist_ok=True)
    if sample:
        indices=[s*1024+i for s in range(5) for i in range(16)]+list(range(5120,6144,13))
        x,y=inputs.read_text().splitlines(),expected.read_text().splitlines()
        inputs,expected=d/'input.memh',d/'expected.memh'
        freeze(inputs,''.join(x[i]+'\n' for i in indices))
        freeze(expected,''.join(y[i]+'\n' for i in indices))
        count=len(indices)
        beats=sum((int(x[i],16)>>1152)&15 for i in indices)
    cmd=['/usr/bin/vvp',binary['exe'],f'+N={count}',f'+INPUT={inputs}',f'+EXPECTED={expected}']
    config=dict(command=cmd,inputs_sha256=sha(inputs),expected_sha256=sha(expected),binary_sha256=binary['binary_sha256'])
    marker=d/'launch.json'
    if marker.exists():
        assert read(marker)==config
    else:
        save(marker,config)
    ex=d/'run.execution.json'
    if ex.exists() and read(ex)['exit_code']==0:
        assert sha(d/'run.log')==read(ex)['log_sha256']
    else:
        run_logged(cmd,d/'run.log')
    log=(d/'run.log').read_text()
    assert f'PASS T08 attribute DMA data_records={count} control_cases=14' in log and f'beats={beats} ' in log
    row=dict(pdk=pdk,variant=variant,sample=sample,records=count,beats=beats,controls=14,execution=read(ex),config=config)
    save(d/'result.json',row)
    return row


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            save(OUT/'status.json',dict(status='BUILDING',pid=os.getpid(),signed_off=False))
            binaries={spec[0]:build(spec) for spec in LIBRARIES}
            results=[]
            for sample in (True,False):
                save(OUT/'status.json',dict(status='RUNNING_SAMPLES' if sample else 'RUNNING_FULL',pid=os.getpid(),signed_off=False))
                with ThreadPoolExecutor(max_workers=4) as pool:
                    jobs=[pool.submit(run_deck,pdk,v,info,sample) for pdk,info in binaries.items() for v in (0,1)]
                    results.extend(job.result() for job in jobs)
            save(OUT/'report.json',dict(results=results,builds=binaries,script_sha256=sha(__file__),signed_off=False,
                 scope='Zero-delay mapped DMA with frozen Liberty logic. Includes mixed Q20/Q24 requests. No SDF or full renderer timing.'))
            save(OUT/'status.json',dict(status='PASS_ZERO_DELAY_MAPPED_FUNCTION',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise
