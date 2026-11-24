"""Trace accepted native AXI bursts and replay bounded windows through frozen Ramulator LPDDR4."""
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import fcntl
import os
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_terminated_blocks import OUT as PREVIOUS
from scripts.run_t08_q24_compact import freeze,edit
from scripts.t08_common import BASE,WORK,SCENES,read,save,sha,run_logged

OUT=BASE/'ddr_windows_20261123'
LOCAL=WORK/OUT.name
RAM=Path.home()/'eda/src-20261024/ramulator'
CFG=RAM/'configs/LPDDR4-config.cfg'
EXE=RAM/'ramulator'
PORTS=('camera','mean','attribute','qsu_read','qsu_write','state_read','output_write')


def build():
    prior=read(PREVIOUS/'build/binary.json')
    sources=prior['sources'].copy()
    assert all(sha(ROOT/p)==h for p,h in sources.items())
    cmd=prior['command'].copy()
    d=OUT/'build'
    d.mkdir(parents=True,exist_ok=True)
    LOCAL.mkdir(parents=True,exist_ok=True)
    old=PREVIOUS/'build/tb_t08_terminated_blocks.sv'
    bench=d/'tb_t08_ddr_addresses.sv'
    inc=ROOT/'verification/rtl/t08_ddr_address_windows.svh'
    freeze(bench,edit(old.read_text().replace(old.stem,bench.stem),'endmodule',f'`include "{inc.relative_to(ROOT)}"\nendmodule'))
    cmd[cmd.index(str(old))]=str(bench)
    cmd[cmd.index('--top-module')+1]=bench.stem
    cmd[cmd.index('--Mdir')+1]=str(LOCAL)
    for p in [bench,inc]:
        sources[str(p.relative_to(ROOT))]=sha(p)
    marker=d/'binary.json'
    exe=LOCAL/'simulation'
    if marker.exists():
        info=read(marker)
        assert info['sources']==sources and info['command']==cmd and info['elf_sha256']==sha(exe)
    else:
        run_logged(cmd,d/'build.log')
        info=dict(command=cmd,exe=str(exe),elf_sha256=sha(exe),sources=sources)
        save(marker,info)
    return info


def ramulator(window,d,rows,start,stop):
    folder=d/f'w{window}'
    folder.mkdir(exist_ok=True)
    deck=folder/'lines.trace'
    lines=[]
    counts=Counter()
    axi=0
    partial=0
    masks=Counter()
    for _,port,addr,n in rows:
        end=addr+n*16
        assert n in range(1,257) and addr%16==0 and addr//4096==(end-1)//4096
        typ='W' if port in (4,6) else 'R'
        counts[PORTS[port]]+=1
        axi+=n*16
        for line in range(addr&~63,end,64):
            lines.append(f'0x{line:x} {typ}\n')
            covered=min(line+64,end)-max(line,addr)
            masks[typ]+=covered
            partial+=int(covered<64)
    assert sum(masks.values())==axi and lines
    freeze(deck,''.join(lines))
    cfg=read(OUT/'model.json')
    stats=folder/'model.stats'
    cmd=[str(EXE),str(CFG),'--mode=dram','--stats',str(stats),str(deck)]
    contract=dict(command=cmd,model=cfg,trace_sha256=sha(deck))
    marker=folder/'launch.json'
    if marker.exists():
        assert read(marker)==contract
    else:
        save(marker,contract)
    ex=folder/'run.execution.json'
    if ex.exists() and read(ex)['exit_code']==0:
        assert sha(folder/'run.log')==read(ex)['log_sha256']
    else:
        run_logged(cmd,folder/'run.log',cwd=folder)
    fields={}
    for line in stats.read_text().splitlines():
        match=re.match(r'\s*ramulator\.(\S+)\s+([-+\d.eE]+)(?:\s|$)',line)
        if match:
            fields[match[1]]=float(match[2])
    cycles=int(fields['dram_cycles'])
    assert fields['incoming_requests']==len(lines) and cycles>0
    assert fields['maximum_bandwidth']==19.2e9 and max(r[2]+16*r[3] for r in rows)<=fields['dram_capacity']
    physical=sum(int(fields[f'{op}_transaction_bytes_{ch}']) for op in ('read','write') for ch in (0,1))
    result=dict(window=window,first_tick=start,end_tick_exclusive=stop,axi_bursts=len(rows),port_bursts=dict(counts),
                addressed_axi_bytes=axi,axi_read_bytes=masks['R'],axi_write_bytes=masks['W'],line_requests=len(lines),
                partial_line_requests=partial,
                dram_cycles=cycles,controller_reported_transfer_bytes=physical,
                saturated_useful_GBps=axi*1.2/cycles,rtl_issue_demand_GBps_at_200mhz=axi*.2/(stop-start),
                stats_sha256=sha(stats),execution=read(ex))
    save(folder/'result.json',result)
    return result


def capture(scene,info):
    d=OUT/scene
    d.mkdir(exist_ok=True)
    orig=read(PREVIOUS/'full128'/scene/'launch.json')
    meta=read(BASE/'inputs/native'/scene/'manifest.json')
    cmd=orig['command'].copy()
    cmd[0]=info['exe']
    trace=d/'bursts.txt'
    paths=dict(CAMERA=meta['inputs']['CAMERA'],FRAME=d/'unused_state',RGB=d/'unused_rgb',SORTED_TRACE=d/'sorted_prefix.txt')
    cmd=['+'+k+'='+str(paths[k]) if (k:=a.partition('=')[0][1:]) in paths else a for a in cmd]
    cmd.append(f'+DDR_TRACE={trace}')
    hashes={k:sha(a.partition('=')[2]) for a in cmd if (k:=a.partition('=')[0][1:]) in ('ATTR','MEAN','CAMERA')}
    assert hashes=={**orig['inputs'],'CAMERA':meta['input_sha256']['CAMERA']}
    contract=dict(command=cmd,inputs=hashes,elf_sha256=info['elf_sha256'],meta=meta)
    marker=d/'launch.json'
    if marker.exists():
        assert read(marker)==contract
    else:
        save(marker,contract)
    ex=d/'run.execution.json'
    if ex.exists() and read(ex)['exit_code']==0:
        assert sha(d/'run.log')==read(ex)['log_sha256']
    else:
        run_logged(cmd,d/'run.log')
    log=(d/'run.log').read_text()
    assert 'PASS T08 DDR address windows' in log and 'disjoint=1' in log
    marks=re.findall(r'^DDR_WINDOW window=(\d+) start=(\d+) stop=(\d+) bursts=(\d+)$',log,re.M)
    assert [int(x[0]) for x in marks]==list(range(4))
    windows=[[] for _ in marks]
    for line in trace.read_text().splitlines():
        i,t,port,addr,n=line.split()
        windows[int(i)].append((int(t),int(port),int(addr,16),int(n)))
    results=[]
    for data,(idx,start,stop,count) in zip(windows,marks,strict=True):
        start,stop=int(start),int(stop)
        assert stop-start==8192 and len(data)==int(count)
        assert all(start<=r[0]<stop for r in data) and data==sorted(data,key=lambda r:(r[0],r[1]))
        results.append(ramulator(int(idx),d,data,start,stop))
    row=dict(scene=scene,camera=meta['camera_index'],gaussians=meta['gaussians'],width=meta['width'],height=meta['height'],
             results=results,raw_trace_sha256=sha(trace),execution=read(ex),signed_off=False)
    save(d/'result.json',row)
    return row


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            save(OUT/'status.json',dict(status='BUILDING',pid=os.getpid(),signed_off=False))
            binary=build()
            model=dict(hashes={str(p):sha(p) for p in [CFG,EXE,RAM/'src/Main.cpp',RAM/'src/LPDDR4.h',RAM/'src/Memory.h']},
                       configuration='LPDDR4_2400, two channels, one rank each, 1200 MHz DRAM clock, 64-byte transactions',
                       policy='Cold saturated DRAM replay per window, no interburst merge, one request per touched line per AXI burst, no explicit partial-write RMW. Fixed same-tick port tie ordering. No RTL feedback.')
            marker=OUT/'model.json'
            if marker.exists():
                assert model==read(marker)
            else:
                save(marker,model)
            save(OUT/'status.json',dict(status='CAPTURING_AND_REPLAYING',pid=os.getpid(),signed_off=False))
            with ThreadPoolExecutor(max_workers=3) as pool:
                results=list(pool.map(lambda s:capture(s,binary),SCENES))
            assert all(sha(ROOT/p)==h for p,h in binary['sources'].items()) and all(sha(p)==h for p,h in model['hashes'].items())
            save(OUT/'report.json',dict(results=results,model=model,script_sha256=sha(__file__),signed_off=False,
                 scope='Four 8192-cycle address windows per native full-model input. Isolated trace throughput; not five completed frames, a physical board measurement or an AXI/LPDDR closed loop.'))
            save(OUT/'status.json',dict(status='NATIVE_WINDOWS_REPLAYED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise
