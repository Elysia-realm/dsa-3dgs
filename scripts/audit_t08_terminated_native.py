"""Audit each completed native whole-block case against the frozen root-enabled frame."""
from pathlib import Path
import sys
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_terminated_blocks import OUT,NATIVE
from scripts.read_rgb888_frame import decode_rgb888
from scripts.t08_common import read,save,sha


def audit(scene):
    d=OUT/'native'/scene
    before=NATIVE/'real'/scene/'1'
    row=read(d/'result.json')
    prior=read(before/'result.json')
    launch=read(d/'launch.json')
    assert launch['baseline_result_sha256']==sha(before/'result.json')
    assert launch['inputs']==read(before/'launch.json')['inputs'] and launch['command']==read(d/'run.command.json')
    assert row['execution']==read(d/'run.execution.json') and row['execution']['exit_code']==0
    assert sha(d/'run.log')==row['execution']['log_sha256']
    assert all(sha(d/f)==h for f,h in row['hashes'].items())
    assert all(row['hashes'][f]==prior['hashes'][f] for f in ('rgb.memh','frame.png','sorted.txt'))
    assert sha(before/'state.memh')==prior['hashes']['state.memh']
    grid=read(NATIVE/'reference'/scene/'samples.json')
    assert launch['inputs']['CAMERA']==grid['inputs'][prior['meta']['inputs']['CAMERA']]
    rgb=decode_rgb888(bytes.fromhex((d/'rgb.memh').read_text()),grid['width'],grid['height'])
    assert rgb.tobytes()==Image.open(d/'frame.png').tobytes()
    delta=np.array([rgb[p['y'],p['x']].astype(int)-p['rgb'] for p in grid['samples']])
    assert delta.shape==(81,3)
    changed_words=0
    changed_t=0
    changed_last_writer=0
    pixels=0
    with (d/'state.memh').open('rb') as a,(before/'state.memh').open('rb') as b:
        for x,y in zip(a,b,strict=True):
            pixels+=1
            if x==y:continue
            v,w=int(x,16),int(y,16)
            assert ((v>>55)&65535)==((w>>55)&65535)==1 and v%(1<<39)==w%(1<<39)
            assert v>>118==w>>118==0
            t,u=(v>>39)&65535,(w>>39)&65535
            assert max(t,u)<=7
            changed_words+=1
            changed_t+=int(t!=u)
            changed_last_writer+=int((v>>71)!=(w>>71))
    assert pixels==grid['width']*grid['height'] and changed_words==row['terminal_changes']
    c,o=row['counters'],prior['counters']
    assert c['REAL_RGB']['error']==0 and c['REAL_RGB']['reads']==pixels
    assert c['REAL_T08']==o['REAL_T08'] and c['REAL_COARSE_BLOCK']['skipped']>0
    cycles=c['REAL_END_TO_END']['command_cycles']
    total_bytes=16*c['REAL_SHARED_BUS']['beats']
    baseline_bytes=prior['actual_data_bus_bytes']
    saved_reads=o['REAL_PERF']['state_reads']-c['REAL_PERF']['state_reads']
    saved_writes=o['REAL_PERF']['state_writes']-c['REAL_PERF']['state_writes']
    assert baseline_bytes-total_bytes==16*(saved_reads+saved_writes)
    assert saved_writes==row['r_grants_saved'] and prior['cycles']-cycles==row['cycles_saved']
    return dict(scene=scene,camera=grid['camera'],record_count=grid['gaussians'],pixels=pixels,
                verified_skips=c['REAL_COARSE_BLOCK']['skipped'],terminal_word_changes=changed_words,
                terminal_t_changes=changed_t,last_write_metadata_changes=changed_last_writer,
                cycles_before=prior['cycles'],cycles_after=cycles,cycle_savings_percent=100*row['cycles_saved']/prior['cycles'],
                r_grants_saved=row['r_grants_saved'],state_read_beats_saved=saved_reads,state_write_beats_saved=saved_writes,
                total_bytes_before=baseline_bytes,total_bytes_after=total_bytes,traffic_savings_percent=100*(1-total_bytes/baseline_bytes),
                assumed_200mhz_fps=200e6/cycles,required_data_gbps_at_30fps=total_bytes*30/1e9,
                sampled_mae_rgb8=float(np.abs(delta).mean()),sampled_max=int(np.abs(delta).max()),
                evidence_sha256={str(p.relative_to(ROOT)):sha(p) for p in [d/'result.json',before/'result.json',
                                NATIVE/'reference'/scene/'samples.json',Path(__file__)]},signed_off=False)


if __name__=='__main__':
    for scene in ('train','truck'):
        dest=OUT/'native'/scene
        if (dest/'result.json').is_file():
            save(dest/'audit.json',audit(scene))
