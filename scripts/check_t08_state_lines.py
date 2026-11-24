"""Compare the frozen native address windows with a verified 16-line write-back buffer."""
from collections import Counter
import fcntl
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_ddr_windows import OUT as WINDOWS, CFG, EXE, PORTS
from scripts.t08_common import BASE,WORK,SCENES,read,save,sha,run_logged
from scripts.run_t08_precision_rgb import freeze

OUT=BASE/'state_lines_20261123'
LOCAL=WORK/OUT.name
RTL=ROOT/'rtl/dma/pixel_state_line_buffer.sv'
BENCH=ROOT/'verification/rtl/tb_t08_state_line_buffer.sv'


def source_rows(scene):
    d=WINDOWS/scene
    info=read(d/'result.json')
    assert sha(d/'bursts.txt')==info['raw_trace_sha256'] and sha(d/'run.log')==info['execution']['log_sha256']
    per_window=[[] for _ in range(4)]
    for line in (d/'bursts.txt').read_text().splitlines():
        win,t,port,addr,n=line.split()
        per_window[int(win)].append((int(t),int(port),int(addr,16),int(n)))
    for i,rows in enumerate(per_window):
        r=info['results'][i]
        model=d/f'w{i}'
        assert r==read(model/'result.json') and sha(model/'model.stats')==r['stats_sha256']
        assert r['execution']['exit_code']==0 and sha(model/'run.log')==r['execution']['log_sha256']
        deck=[]
        for tick,port,addr,n in rows:
            assert r['first_tick']<=tick<r['end_tick_exclusive']
            typ='W' if port in (4,6) else 'R'
            deck.extend(f'0x{a:x} {typ}\n' for a in range(addr&~63,addr+16*n,64))
        assert (model/'lines.trace').read_text()==''.join(deck)
        assert sha(model/'lines.trace')==read(model/'launch.json')['trace_sha256']
        assert len(rows)==r['axi_bursts'] and len(deck)==r['line_requests']
        assert dict(Counter(PORTS[p] for _,p,_,_ in rows))==r['port_bursts']
    return info,per_window


def oracle(lines,entries):
    tags=[None]*entries
    dirty=[False]*entries
    deck=[]
    for op,addr,_,_ in lines:
        line=addr&~63
        slot=(addr>>6)%entries
        if line!=tags[slot]:
            if dirty[slot]:deck.append((tags[slot],'W'))
            deck.append((line,'R'))
            tags[slot]=line
            dirty[slot]=False
        if op==1:dirty[slot]=True
    deck.extend((tags[i],'W') for i in range(entries) if dirty[i])
    return deck


def hardware(d,ops,exe):
    d.mkdir(parents=True,exist_ok=True)
    inputs=d/'stimulus.txt'
    trace=d/'buffer.trace'
    freeze(inputs,''.join(f'{op} {addr:016x} {value:032x} {mask:04x}\n' for op,addr,value,mask in ops))
    ex=run_logged([str(exe),f'+DECK={inputs}',f'+TRACE={trace}'],d/'run.log')
    log=(d/'run.log').read_text()
    match=re.search(r'PASS T08 state line buffer operations=(\d+) reads=(\d+) writes=(\d+) bench_cycles=(\d+)',log)
    assert match
    operations,reads,writes,cycles=map(int,match.groups())
    actual=[(int(a,16),t) for a,t in (line.split() for line in trace.read_text().splitlines())]
    assert operations==len(ops)+1 and sum(t=='R' for _,t in actual)==reads and len(actual)==reads+writes
    return actual,dict(execution=ex,reads=reads,writes=writes,bench_cycles=cycles,
                       stimulus_sha256=sha(inputs),trace_sha256=sha(trace))


def main():
    baseline=read(WINDOWS/'report.json')
    assert len(baseline['results'])==5 and all(sha(p)==h for p,h in baseline['model']['hashes'].items())
    summary=[]
    data={}
    for scene in SCENES:
        info,windows=source_rows(scene)
        assert info==next(r for r in baseline['results'] if r['scene']==scene)
        data[scene]=(info,windows)
        for r in info['results']:
            summary.append(dict(scene=scene,window=r['window'],line_amplification=64*r['line_requests']/r['addressed_axi_bytes'],
                                useful_GBps=r['saturated_useful_GBps'],controller_reported_bytes=r['controller_reported_transfer_bytes']))
    save(WINDOWS/'audit.json',dict(results=summary,report_sha256=sha(WINDOWS/'report.json'),signed_off=False))
    verilator=read(WINDOWS/'build/binary.json')['command'][0]
    LOCAL.mkdir(parents=True,exist_ok=True)
    run_logged([verilator,'--binary','--build','-j','2','--timing','--assert','-Wno-fatal',
                '--top-module',BENCH.stem,'--Mdir',str(LOCAL),'-o','simulation',str(RTL),str(BENCH)],OUT/'build.log')
    exe=LOCAL/'simulation'
    pattern=0xffeeddccbbaa99887766554433221100
    ops=[(op,addr,pattern,mask) for op,addr,mask in [
        (0,0x1000,0),(1,0x1000,0x55aa),(0,0x1000,0),(1,0x1010,0xffff),(4,0x1400,0),
        (0,0x1010,0),(3,0x1400,0),(0,0x1000,0),(1,0x1410,0xa55a),(5,0,0),
        (0,0x1410,0),(2,0,0),(0,0x1010,0),(6,0x1011,0),(1,0x1000,0),(2,0,0)]]
    _,directed=hardware(OUT/'protocol',ops,exe)
    results=[]
    for scene,(info,windows) in data.items():
        for i in (2,3):
            d=OUT/scene/f'w{i}'
            base=info['results'][i]
            ops=[]
            backing=0x70000000+((info['width']*3+15)//16*16)*info['height']
            limit=backing+info['width']*info['height']*16
            for _,port,addr,n in windows[i]:
                assert port in (5,6) and n==1 and backing<=addr and addr+16<=limit
                # Address/order are captured; distinct deterministic write values exercise all 128 bits.
                value=((addr*0x9e3779b9+len(ops)) * 0x123456789abcdef11234567)&((1<<128)-1)
                ops.append((int(port==6),addr,value,65535))
            actual,bench=hardware(d,ops,exe)
            assert actual==oracle(ops,16),(scene,i)
            sizes={n:len(oracle(ops,n)) for n in (1,4,16)}
            ex=run_logged([str(EXE),str(CFG),'--mode=dram','--stats',str(d/'model.stats'),str(d/'buffer.trace')],d/'lpddr.log',cwd=d)
            stats=(d/'model.stats').read_text()
            def field(name):
                return float(re.search(r'^\s*ramulator\.'+name+r'\s+([\d.eE+-]+)',stats,re.M)[1])
            assert field('incoming_requests')==len(actual)
            cycles=int(field('dram_cycles'))
            row=dict(scene=scene,window=i,axi_bytes=base['addressed_axi_bytes'],axi_bursts=len(ops),
                     direct_line_requests=base['line_requests'],modeled_counts=sizes,verified_rtl_line_requests=len(actual),
                     direct_dram_cycles=base['dram_cycles'],buffered_dram_cycles=cycles,
                     direct_useful_GBps=base['saturated_useful_GBps'],buffered_useful_GBps=base['addressed_axi_bytes']*1.2/cycles,
                     bench=bench,model_execution=ex,model_stats_sha256=sha(d/'model.stats'))
            save(d/'result.json',row)
            results.append(row)
    save(OUT/'report.json',dict(results=results,directed=directed,rtl_sha256=sha(RTL),bench_sha256=sha(BENCH),
         binary_sha256=sha(exe),script_sha256=sha(__file__),baseline_sha256=sha(WINDOWS/'audit.json'),
         scope='Standalone ordered buffer, 16 direct-mapped 64B lines, off-chip read allocate, complete-line writeback and drain. Actual captured state addresses with synthetic checked payloads. Separate saturated LPDDR4 replay; real AXI concurrency and renderer cycles not measured.',signed_off=False))


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        main()
