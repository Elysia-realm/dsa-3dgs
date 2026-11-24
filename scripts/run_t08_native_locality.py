"""Replay actual cache fill/update streams in bounded native-resolution windows."""
import fcntl
import itertools
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.run_t08_early_advance import OUT as PREVIOUS, matching_source
from scripts.t08_common import BASE, MAX_COUNT, MAX_PIXELS, SCENES, WORK, read, run_logged, save, sha

OUT = BASE / 'native_locality_20261122'
ORIGINAL = OUT
MONITOR = 'verification/rtl/t08_native_locality_monitor.svh'
ATTRIBUTION = 'verification/rtl/t08_gaussian_work_monitor.svh'


def build():
    prior = read(PREVIOUS/'build/full/1/binary.json')
    sources = dict(prior['source_sha256'])
    matching_source()
    assert all(sha(ROOT/f)==h for f,h in sources.items())
    top = 'tb_t08_native_locality'
    bench = OUT / 'build' / (top+'.sv')
    previous_bench = PREVIOUS/'build/full/1/tb_t08_integrated.sv'
    body = previous_bench.read_text().replace('tb_t08_integrated',top)
    assert body.count('endmodule') == 1
    if OUT != ORIGINAL:
        monitor = (ROOT/MONITOR).read_text()
        monitor = monitor.replace('obs_active=1;', 'obs_active=1;work_initial_accepted=t07_accepted;')
        monitor = monitor.replace('if(obs_active)begin', 'if(obs_active)begin\n    work_sample();')
        monitor = monitor.replace('if(obs_count==65536)begin', 'if(obs_count==65536)begin\n        work_report();')
        body=body.replace('endmodule', monitor+f'\n`include "{ATTRIBUTION}"\nendmodule')
        sources[ATTRIBUTION]=sha(ROOT/ATTRIBUTION)
    else:
        body = body.replace('endmodule',f'`include "{MONITOR}"\nendmodule')
    bench.parent.mkdir(parents=True,exist_ok=True)
    if bench.exists(): assert bench.read_text()==body
    else: bench.write_text(body)
    sources.update({MONITOR:sha(ROOT/MONITOR), str(bench.relative_to(ROOT)):sha(bench)})
    work = WORK / OUT.name / 'build'
    work.mkdir(parents=True,exist_ok=True)
    cmd = list(prior['command'])
    cmd[cmd.index(str(previous_bench))] = str(bench)
    cmd[cmd.index('--top-module')+1] = top
    cmd[cmd.index('--Mdir')+1] = str(work)
    cmd = [f'-DTB_MAX_COUNT={MAX_COUNT}' if a.startswith('-DTB_MAX_COUNT=') else
           f'-DTB_MAX_PIXELS={MAX_PIXELS}' if a.startswith('-DTB_MAX_PIXELS=') else a for a in cmd]
    marker = bench.parent/'binary.json'
    exe = work/'simulation'
    if marker.exists():
        info = read(marker)
        assert info['command']==cmd and sources==info['sources'] and sha(exe)==info['elf_sha256']
        return info
    run_logged(cmd,bench.parent/'build.log')
    assert all(sha(ROOT/f)==h for f,h in sources.items())
    info = dict(command=cmd, sources=sources, exe=str(exe), elf_sha256=sha(exe), parameters=prior['parameters'])
    save(marker,info)
    return info


def analyze(path,pixels):
    rows=[]
    with path.open() as stream:
        for window,threshold in enumerate((4096,65536)):
            tag,number,start_req,start=stream.readline().split()
            assert tag=='W' and int(number)==window and int(start_req)>=threshold
            dirty={};evictions=updates=fills=same_index_pairs=0
            def events():
                nonlocal summary
                for line in stream:
                    fields=line.split()
                    if fields[0]=='E':
                        summary=list(map(int,fields[1:]))
                        return
                    tag,cycle,pixel=fields
                    assert tag in ('F','U') and 0<=int(pixel)<pixels
                    yield int(cycle),tag,int(pixel)
            summary=None
            for cycle,group in itertools.groupby(events(),key=lambda event:event[0]):
                batch={kind:pixel for _,kind,pixel in group}
                fill,update=batch.get('F'),batch.get('U')
                # A simultaneous architected update wins over a fill of its index.
                if fill is not None:
                    fills+=1
                    index=fill%4096
                    if update is not None and update%4096==index:
                        same_index_pairs+=1
                    elif index in dirty and dirty[index]!=fill:
                        evictions+=1
                        del dirty[index]
                if update is not None:
                    updates+=1
                    index=update%4096
                    evictions+=int(index in dirty and dirty[index]!=update)
                    dirty[index]=update
            assert summary and summary[0]==window and updates==65536
            writes=evictions+len(dirty)
            assert 0<writes<=updates and 0<=summary[2]<=summary[1]
            rows.append(dict(window=window, start_requests=int(start_req),end_requests=summary[3],
                cycles=summary[4]-int(start)+1, state_updates=updates, fills=fills,
                queries=summary[1],hits=summary[2],same_index_fill_update=same_index_pairs,
                modeled_evictions=evictions,modeled_terminal_flush=len(dirty),
                modeled_write_beats=writes,modeled_write_reduction_percent=100*(1-writes/updates)))
        assert not stream.read().strip()
    return rows


def capture(scene,info):
    d=OUT/scene;d.mkdir(parents=True,exist_ok=True)
    native=read(BASE/'inputs/native'/scene/'manifest.json')
    original=PREVIOUS/'real/full/1'/scene/'f1'
    cmd=read(original/'run.command.json')
    cmd[0]=info['exe']
    inputs={}
    for i,a in enumerate(cmd):
        key,_,value=a.partition('=')
        if key=='+CAMERA': value=native['inputs']['CAMERA'];cmd[i]=key+'='+value
        if key in ('+ATTR','+MEAN','+CAMERA'): inputs[key[1:]]=sha(Path(value))
        if key in ('+FRAME','+RGB','+SORTED_TRACE'): cmd[i]=key+'='+str(d/Path(value).name)
    expected=dict(read(original/'launch.json')['input_sha256'],CAMERA=native['input_sha256']['CAMERA'])
    assert expected==inputs and inputs['MEAN']==native['input_sha256']['MEAN']
    trace=d/'events.txt';cmd.append('+LOCALITY_TRACE='+str(trace))
    if OUT != ORIGINAL:cmd.append('+WORK_TRACE='+str(d/'gaussian_work.txt'))
    marker=d/'launch.json'
    launch=dict(command=cmd, binary_sha256=info['elf_sha256'],input_sha256=inputs,scene=scene,camera=SCENES[scene],
                gaussians=native['gaussians'],width=native['width'],height=native['height'],source_sha256=info['sources'])
    if marker.exists():
        assert read(marker)==launch
        ex=read(d/'run.execution.json')
        assert ex['exit_code']==0 and sha(d/'run.log')==ex['log_sha256']
    else:
        save(marker,launch);ex=run_logged(cmd,d/'run.log')
    assert f"T08_LOCALITY_CAPTURE_COMPLETE width={native['width']} height={native['height']} n={native['gaussians']}" in (d/'run.log').read_text()
    rows=analyze(trace,native['width']*native['height'])
    result=dict(status='CAPTURED_TWO_WINDOWS',scene=scene,windows=rows,trace_sha256=sha(trace),execution=ex,
                launch_sha256=sha(marker),complete_frame=False,signed_off=False)
    if OUT != ORIGINAL:
        assert result['trace_sha256']==read(ORIGINAL/scene/'result.json')['trace_sha256']
        result['work_trace_sha256']=sha(d/'gaussian_work.txt')
        result['work_attribution']=attribute_work(d/'gaussian_work.txt',native)
    save(d/'result.json',result);print(scene,rows,flush=True)
    return result


def attribute_work(path,native):
    windows=[{},{}]
    with path.open() as stream:
        for line in stream:
            window,gid,blocks,rejected,tasks,commits,terminated,x0,y0,x1,y1,overflow=map(int,line.split())
            assert window in (0,1) and gid not in windows[window] and 0<=gid<native['gaussians']
            assert rejected<=blocks and terminated<=commits
            if blocks:assert 0<=x0<x1<=native['width'] and 0<=y0<y1<=native['height']
            windows[window][gid]=dict(gid=gid,blocks=blocks,rejected=rejected,tasks=tasks,commits=commits,
                terminated=terminated,bbox=[x0,y0,x1,y1] if blocks else None,descriptor_overflow=bool(overflow) if blocks else None)
    result=[]
    for index,records in enumerate(windows):
        work=list(records.values())
        totals={k:sum(r[k] for r in work) for k in ('blocks','rejected','tasks','commits','terminated')}
        assert totals['commits']>0
        result.append(dict(window=index,observed_gids=len(work),totals=totals,
             top_by_tasks=sorted(work,key=lambda r:r['tasks'],reverse=True)[:8],
             top_by_commits=sorted(work,key=lambda r:r['commits'],reverse=True)[:8]))
    return result


def main():
    global OUT
    if sys.argv[1:]==['--attribute-work']:OUT=BASE/'native_gaussian_work_20261122'
    elif sys.argv[1:]:raise SystemExit('expected --attribute-work or no arguments')
    assert ROOT.as_posix()=='/mnt/d/3DGS'
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        save(OUT/'status.json',dict(status='RUNNING',pid=os.getpid(),signed_off=False))
        try:
            info=build()
            with ThreadPoolExecutor(max_workers=3) as pool:
                rows=list(pool.map(lambda s:capture(s,info),SCENES))
            matching_source()
            save(OUT/'report.json',dict(status='TRACE_DIAGNOSTIC_COMPLETE',results=rows,
                 scope='Two windows each initialized clean and flushed at end. Fixed fill/update schedule, no stalls or port cost modeled; cycle gains unmeasured.',signed_off=False))
            save(OUT/'status.json',dict(status='TRACE_DIAGNOSTIC_COMPLETE',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise


if __name__=='__main__':
    main()
