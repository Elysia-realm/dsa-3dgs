"""Reconstruct RTL radix partitions from complete sorted traces and bound local subtree traffic."""
from bisect import bisect_left
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,SCENES,read,save,sha
from scripts.run_t08_early_advance import OUT as EARLY

OUT=BASE/'qsu_subtree_budget_20261122'
SIZES=(32,64,128,256)


def analyze(scene):
    d=EARLY/'real/full/1'/scene/'f1'
    report=read(d/'result.json')
    trace=d/'sorted.txt'
    assert sha(trace)==report['outputs']['sorted.txt'] and sha(d/'run.log')==report['outputs']['run.log']
    qsu=report['counters']['REAL_QSU']
    keys=[]
    with trace.open() as inp:
        for line in inp:
            depth,gid,seq=map(int,line.split())
            assert -(1<<26)<=depth<1<<26 and 0<=gid<1<<32 and 0<=seq<1<<32
            keys.append(((depth+(1<<26))<<64)|(gid<<32)|seq)
    n=len(keys)
    assert n==qsu['input'] and all(a<b for a,b in zip(keys,keys[1:]))
    pending=[(0,n,n+1)]
    partitions=leaves=visits=0
    saved={k:0 for k in SIZES}
    roots={k:0 for k in SIZES}
    while pending:
        lo,hi,parent=pending.pop()
        count=hi-lo
        if count<=16:
            leaves+=1
            continue
        partitions+=1
        visits+=count
        for k in SIZES:
            if count<=k:
                saved[k]+=count
                roots[k]+=int(parent>k)
        shift=max(0,(keys[lo]^keys[hi-1]).bit_length()-3)
        prefix=(keys[lo]>>(shift+3))<<(shift+3)
        start=lo
        for bucket in range(1,9):
            end=hi if bucket==8 else bisect_left(keys,prefix+(bucket<<shift),start,hi)
            if end>start:
                assert end-start<count
                pending.append((start,end,count))
            start=end
    reads=2*n+visits
    writes=n+visits
    assert (partitions,leaves,reads,writes)==(qsu['partitions'],qsu['leaves'],qsu['axi_reads'],qsu['axi_writes']),scene
    candidates=[]
    for k in SIZES:
        # Parent scatter still writes each record, and a selected subtree must be loaded once.
        # Only the internal scatter reads/writes after that load disappear from the external port.
        count=saved[k]
        candidates.append(dict(capacity=k,ping_pong_payload_bytes=2*k*91//8,subtree_loads=roots[k],
                              saved_read_beats=count,saved_write_beats=count,remaining_reads=reads-count,
                              remaining_writes=writes-count,remaining_bytes=(reads+writes-2*count)*16,
                              independent_read_port_multiple_at_200mhz_30fps=(reads-count)*30/200e6))
    result=dict(scene=scene,records=n,partitions=partitions,leaves=leaves,reads=reads,writes=writes,
                candidates=candidates,trace_sha256=sha(trace),source_report_sha256=sha(d/'result.json'))
    save(OUT/scene/'result.json',result)
    return result


if __name__=='__main__':
    rows=[analyze(scene) for scene in SCENES]
    save(OUT/'report.json',dict(results=rows,script_sha256=sha(__file__),signed_off=False,
         scope='Five width128 full-model sorting traces with measured AXI count anchors. Proposed combination of child precount and two local scratch banks. Ideal traffic, excludes control, ports, stalls, PPA and raster performance.'))
