"""Exercise consecutive precision changes and intermediate-batch errors on the frozen dual top."""
from concurrent.futures import ThreadPoolExecutor
import fcntl
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_dual_precision import OUT as DUAL
from scripts.run_t08_q24_compact import encode_q24, edit, freeze, MASK128
from scripts.t08_common import BASE, WORK, read, save, sha, run_logged

OUT=BASE/'dual_format_sequences_20261122'
LOCAL=WORK/OUT.name
OLD=BASE/'continuation_early_advance_20261120'


def build():
    prior=read(DUAL/'build/binary.json')
    sources=prior['sources'].copy()
    assert all(sha(ROOT/p)==digest for p,digest in sources.items())
    d=OUT/'build'
    d.mkdir(parents=True,exist_ok=True)
    LOCAL.mkdir(parents=True,exist_ok=True)
    old=DUAL/'build/tb_t08_dual_precision.sv'
    bench=d/'tb_t08_format_sequence.sv'
    text=old.read_text().replace(old.stem,bench.stem)
    inc='verification/rtl/t08_format_sequence.svh'
    start=text.index("    apb_write(12'h000,batch_list_mode?batch_control:")
    text=text[:start]+'    run_format_sequence();$finish;\n'+text[start:]
    text=edit(text,'endmodule',f'`include "{inc}"\nendmodule')
    # This multi-command bench checks every completion, including expected errors.
    perf='verification/rtl/t06_perf_measurements.svh'
    counters=d/'measure.svh'
    freeze(counters,(ROOT/perf).read_text().split('// Sample DONE after')[0])
    freeze(bench,edit(text,perf,str(counters.relative_to(ROOT))))
    for p in [ROOT/inc,counters,bench]:
        sources[str(p.relative_to(ROOT))]=sha(p)
    exe=LOCAL/'simulation'
    cmd=prior['command'].copy()
    cmd[cmd.index(str(old))]=str(bench)
    cmd[cmd.index('--top-module')+1]=bench.stem
    cmd[cmd.index('--Mdir')+1]=str(LOCAL)
    marker=d/'binary.json'
    if marker.exists():
        info=read(marker)
        assert info['command']==cmd and info['sources']==sources and sha(exe)==info['elf_sha256']
    else:
        run_logged(cmd,d/'build.log')
        info=dict(command=cmd,sources=sources,exe=str(exe),elf_sha256=sha(exe))
        save(marker,info)
    return info


def short_inputs():
    d=OUT/'one_record'
    d.mkdir(exist_ok=True)
    original=ROOT/'experiments/t06_release_20261022/subset/bonsai'
    raw=original/'attribute.memh'
    old=BASE/'integration_20261107/inputs/bonsai/attribute.memh'
    cam=(original/'camera.memh').read_text().splitlines()
    cam[-1]='4753430100000001'
    freeze(d/'camera.memh','\n'.join(cam)+'\n')
    freeze(d/'mean.memh',(original/'mean.memh').read_text().splitlines()[0]+'\n')
    for fmt,src in [(0,raw),(1,old),(3,raw)]:
        freeze(d/f'f{fmt}.memh','\n'.join(src.read_text().splitlines()[:9])+'\n')
    words=(d/'f0.memh').read_text().split()
    record=sum(int(w,16)<<(128*i) for i,w in enumerate(words))
    packet,beats=encode_q24(record)
    assert beats<9
    freeze(d/'f2.memh',''.join(f'{(packet>>(128*i))&MASK128:032x}\n' for i in range(9)))
    save(d/'manifest.json',dict(scene='bonsai',subset_record_index=0,records=1,width=128,height=84,
         input_sha256={p.name:sha(p) for p in d.glob('*.memh')},
         source_sha256={str(p.relative_to(ROOT)):sha(p) for p in [raw,old,original/'camera.memh',original/'mean.memh']}))
    return d


def run_case(info,first,second,kind,native):
    label=f'{"native" if native else "control"}_{kind}_{first}_{second}'
    d=OUT/label
    d.mkdir(exist_ok=True)
    if native:
        def get(fmt):
            launch=read(DUAL/'real/bonsai'/f'f{fmt}'/'launch.json')
            args={k:v for arg in launch['command'] if arg.startswith('+') and '=' in arg for k,v in [arg[1:].split('=',1)]}
            assert all(sha(args[key])==h for key,h in launch['inputs'].items())
            return args
        a,b=get(first),get(second)
        assert a['MEAN']==b['MEAN'] and a['CAMERA']==b['CAMERA']
        attrs,other,mean,camera=a['ATTR'],b['ATTR'],a['MEAN'],a['CAMERA']
        profile=['+AUTO_QSU','+READ_LATENCY=0','+READ_GAP=0','+READY_PERIOD=1','+READY_LOW=0','+WRITE_RESPONSE_LATENCY=2']
    else:
        inputs=OUT/'one_record'
        attrs,other,mean,camera=inputs/f'f{first}.memh',inputs/f'f{second}.memh',inputs/'mean.memh',inputs/'camera.memh'
        profile=['+READ_LATENCY=8','+READ_GAP=2','+READY_PERIOD=4','+READY_LOW=1','+WRITE_RESPONSE_LATENCY=8']
    rgb=d/'frame.rgb'
    cmd=[info['exe'],f'+ATTR={attrs}',f'+MEAN={mean}',f'+CAMERA={camera}',f'+NEXT_ATTR={other}',f'+NEXT_FORMAT={second}',
         f'+ATTR_FORMAT={first}',f'+SEQ_KIND={kind}',f'+FRAME={d}/state.memh',f'+RGB={rgb}',f'+SORTED_TRACE={d}/sorted.txt',
         '+FRAME_MODE=0','+MAX_TIMEOUT=50000000',*profile]
    inputs={str(p):sha(p) for p in [attrs,other,mean,camera]}
    launch=dict(command=cmd,inputs=inputs,elf_sha256=info['elf_sha256'])
    marker=d/'launch.json'
    if marker.exists():
        assert read(marker)==launch
    else:
        save(marker,launch)
    ex=d/'run.execution.json'
    if ex.exists() and read(ex)['exit_code']==0:
        assert sha(d/'run.log')==read(ex)['log_sha256']
    else:
        run_logged(cmd,d/'run.log')
    log=(d/'run.log').read_text()
    assert f'PASS T08 format sequence kind={kind} final_format={second}' in log
    output={rgb.name:sha(rgb),'sorted.txt':sha(d/'sorted.txt')}
    if kind==0:
        first_rgb=d/'frame.rgb.first'
        output[first_rgb.name]=sha(first_rgb)
    if native:
        trace=b''
        for fmt,actual in [(first,first_rgb),(second,rgb)]:
            ref=DUAL/'real/bonsai'/f'f{fmt}'
            row=next(r for r in read(ref.parent/'result.json')['rows'] if r['format']==fmt)
            for fn in ('rgb.memh','sorted.txt'):
                assert sha(ref/fn)==row['outputs'][fn]
            assert bytes.fromhex((ref/'rgb.memh').read_text())==actual.read_bytes(), (label,fmt)
            trace+=(ref/'sorted.txt').read_bytes()
        assert trace==(d/'sorted.txt').read_bytes()
        assert output['frame.rgb']!=output['frame.rgb.first']
    result=dict(label=label,kind=kind,first=first,second=second,native=native,outputs=output,execution=read(ex),
                frames=[s for s in log.splitlines() if s.startswith('SEQUENCE_FRAME')])
    save(d/'result.json',result)
    return result


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        save(OUT/'status.json',dict(status='BUILDING',pid=os.getpid(),signed_off=False))
        try:
            info=build()
            short_inputs()
            rows=[]
            for fmt in range(4):
                rows.append(run_case(info,fmt,fmt,1,False))
            for f in (0,1,2,3):
                fresh=run_case(info,f,f,0,False)
                rows.append(fresh)
                assert fresh['outputs']['frame.rgb']==fresh['outputs']['frame.rgb.first']
            for first,second in [(1,2),(2,1),(0,3),(3,0)]:
                recovered=run_case(info,first,second,2,False)
                assert recovered['outputs']['frame.rgb']==sha(OUT/f'control_0_{second}_{second}/frame.rgb')
                rows.append(recovered)
            for a,b in [(0,1),(3,2)]:
                assert sha(OUT/f'control_1_{a}_{a}/frame.rgb')==sha(OUT/f'control_1_{b}_{b}/frame.rgb')
            reference=bytes.fromhex((OLD/'f1_m0/RGB.memh').read_text())
            assert (OUT/'control_1_1_1/frame.rgb').read_bytes()==reference
            save(OUT/'control_report.json',dict(results=rows,signed_off=False))
            save(OUT/'status.json',dict(status='RUNNING_NATIVE_FRAME_SWITCH',pid=os.getpid(),signed_off=False))
            with ThreadPoolExecutor(max_workers=2) as pool:
                native=list(pool.map(lambda pair:run_case(info,*pair,0,True),[(1,2),(2,1)]))
            assert all(sha(ROOT/p)==digest for p,digest in info['sources'].items())
            save(OUT/'report.json',dict(control=rows,native=native,script_sha256=sha(__file__),signed_off=False))
            save(OUT/'status.json',dict(status='FRAME_AND_CONTINUATION_CHECKED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise


if __name__=='__main__':
    main()
