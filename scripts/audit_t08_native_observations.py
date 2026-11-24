"""Bind each finished native render to its independent sample grid and measured port traffic."""
from pathlib import Path
import sys
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_qsu_native_full import OUT,SCENES
from scripts.t08_common import read,save,sha
from scripts.read_rgb888_frame import decode_rgb888


def audit(scene,mode,ref):
    d=OUT/'real'/scene/str(mode)
    r=read(d/'result.json')
    launch=read(d/'launch.json')
    ex=read(d/'run.execution.json')
    assert ex==r['execution'] and ex['exit_code']==0 and ex['log_sha256']==sha(d/'run.log')
    assert all(sha(d/name)==h for name,h in r['hashes'].items())
    assert r['meta']==launch['meta'] and r['meta']['camera_index']==ref['camera']
    assert ref['inputs'][r['meta']['ply']]==r['meta']['ply_sha256']
    assert ref['inputs'][r['meta']['inputs']['CAMERA']]==launch['inputs']['CAMERA']
    assert launch['command']==read(d/'run.command.json')
    rgb=decode_rgb888(bytes.fromhex((d/'rgb.memh').read_text()),ref['width'],ref['height'])
    assert rgb.tobytes()==Image.open(d/'frame.png').tobytes()
    points=[]
    for entry in ref['samples']:
        x,y=entry['x'],entry['y']
        points.append(dict(x=x,y=y,actual=rgb[y,x].tolist(),reference=entry['rgb']))
    assert len(points)==len({(v['x'],v['y']) for v in points})==81
    delta=np.array([v['actual'] for v in points])-np.array([v['reference'] for v in points])
    c=r['counters']
    perf=c['REAL_PERF']
    dma=c['REAL_DMA_COUNTS']
    scan=c['REAL_RGB']
    assert scan['reads']==ref['width']*ref['height'] and scan['epoch']==1 and scan['error']==0
    beats={k:dma[k+'_beats'] for k in ('camera','mean','attribute','qsu_read','qsu_write')}
    beats.update(state_read=perf['state_reads'],state_write=perf['state_writes'],
                 final_scan_read=scan['reads'],final_rgb_write=scan['write_beats'])
    total=sum(beats.values())
    assert total==c['REAL_SHARED_BUS']['beats'] and 16*total==r['actual_data_bus_bytes']
    assert c['REAL_T08']['world_precomputed']==c['REAL_T08']['precomputed']>0
    return dict(scene=scene,enabled=mode,reference_sha256=sha(OUT/'reference'/scene/'samples.json'),
                source_result_sha256=sha(d/'result.json'),points=points,sampled_mae_rgb8=float(np.abs(delta).mean()),
                sampled_max_channel_error=int(np.abs(delta).max()),data_beats=beats,total_data_bytes=16*total,
                state_update_byte_percent=100*(beats['state_read']+beats['state_write'])/total,
                command_cycles=r['cycles'],cycles_over_200mhz_30fps_budget=r['cycles']*30/200e6,
                shared_R_grants=c['REAL_SHARED_PE']['R'],assumed_fps_200mhz=200e6/r['cycles'],
                bandwidth_required_at_30fps_GBps=16*total*30/1e9,host_wall_s=ex['wall_seconds'])


if __name__=='__main__':
    ref_report=read(OUT/'reference/report.json')
    for ref in ref_report['results']:
        s=ref['scene']
        assert s in SCENES and ref==read(OUT/'reference'/s/'samples.json')
        assert all(sha(p)==h for p,h in ref['sources'].items())
        for mode in (0,1):
            d=OUT/'real'/s/str(mode)
            if (d/'result.json').is_file():
                save(d/'observation_audit.json',audit(s,mode,ref))
