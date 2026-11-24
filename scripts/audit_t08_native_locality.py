"""Independently check the dirty write accounting and unlimited reuse ceiling."""
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_native_locality import OUT
from scripts.t08_common import SCENES,read,save,sha


def main():
    rows=[]
    for scene in SCENES:
        d=OUT/scene
        result=read(d/'result.json')
        trace=d/'events.txt'
        assert sha(trace)==result['trace_sha256'] and sha(d/'launch.json')==result['launch_sha256']
        assert result['execution']['exit_code']==0 and sha(d/'run.log')==result['execution']['log_sha256']
        # A second accounting: count subsequent updates to an already dirty
        # resident pixel. The first update of each residency must be written.
        dirty={};pixels=set();combined=0;updates=0;pending_fill=None
        def apply_fill(fill):
            if fill is not None and dirty.get(fill%4096)!=fill:
                dirty.pop(fill%4096,None)
        with trace.open() as stream:
            for line in stream:
                kind,*values=line.split()
                v=list(map(int,values))
                if kind=='W':
                    index=v[0];dirty.clear();pixels.clear();combined=updates=0;pending_fill=None
                elif kind=='F':
                    if pending_fill:apply_fill(pending_fill[1])
                    pending_fill=v
                elif kind=='U':
                    cycle,pixel=v
                    if pending_fill and (cycle!=pending_fill[0] or pixel%4096!=pending_fill[1]%4096):
                        apply_fill(pending_fill[1])
                    pending_fill=None
                    combined+=int(dirty.get(pixel%4096)==pixel)
                    dirty[pixel%4096]=pixel;pixels.add(pixel);updates+=1
                elif kind=='E':
                    if pending_fill:apply_fill(pending_fill[1])
                    window=result['windows'][index]
                    assert index==v[0] and updates==window['state_updates']==65536
                    assert updates-combined==window['modeled_write_beats']
                    assert len(pixels)<=updates-combined<=updates
                    rows.append(dict(scene=scene,window=index,updates=updates,distinct_pixels=len(pixels),
                         modeled_saved_writes=combined,unlimited_saved_writes_ceiling=updates-len(pixels)))
                else:raise ValueError(kind)
    assert len(rows)==10
    save(OUT/'reuse_ceiling_audit.json',dict(status='PASS_WINDOW_ACCOUNTING',windows=rows,signed_off=False))
    for row in rows:print(row)


if __name__=='__main__':main()
