"""Verify the complete-model four-command archive and quantify image regressions per scene."""
from pathlib import Path
import re
import sys
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_dual_full import OUT,FLOAT,compare_states
from scripts.t08_common import BASE,SCENES,read,save,sha
from scripts.read_rgb888_frame import decode_rgb888


def audit(scene,binary):
    d=OUT/'real'/scene
    result=read(d/'comparison.json')
    meta=read(BASE/'inputs/native'/scene/'manifest.json')
    oracle=next(r for r in read(FLOAT/'audit.json')['results'] if r['scene']==scene)
    assert meta['camera_index']==oracle['camera'] and meta['gaussians']==oracle['gaussians']
    fp=FLOAT/scene/'float_floor_0.30078125_jac_clamp.png'
    assert sha(fp)==oracle['float_sha256']
    reference=np.asarray(Image.open(fp).convert('RGB')).astype(np.int16)
    rows=[]
    imgs=[]
    for fmt in range(4):
        folder=d/f'f{fmt}'
        row=read(folder/'result.json')
        assert result['rows'][str(fmt)]==row
        launch=read(folder/'launch.json')
        assert binary['elf_sha256']==launch['elf_sha256']
        assert sha(folder/'run.log')==row['execution']['log_sha256'] and row['execution']['exit_code']==0
        assert all(sha(folder/name)==h for name,h in row['hashes'].items())
        assert launch['input_sha256']['MEAN']==oracle['input_sha256']['mean.memh'] and launch['input_sha256']['CAMERA']==oracle['input_sha256']['camera.memh']
        assert launch['command']==read(folder/'run.command.json')
        assert row['gaussians']==row['counters']['REAL_WORKLOAD']['gaussians']==meta['gaussians']
        assert row['reference_sha256']==sha(fp)
        img=decode_rgb888(bytes.fromhex((folder/'rgb.memh').read_text()),oracle['width'],oracle['height'])
        assert img.tobytes()==Image.open(folder/'frame.png').tobytes()
        imgs.append(img.astype(np.int16))
        delta=np.abs(imgs[-1]-reference)
        assert float(delta.mean())==row['internal_float_mae'] and int(delta.max())==row['internal_float_max']
        c=row['counters']
        log=(folder/'run.log').read_text()
        cpu=float(re.search(r'User time \(seconds\): ([\d.]+)',log)[1])
        rows.append(dict(format=fmt,command_cycles=row['command_cycles'],requests=c['REAL_T08']['requests'],
                         attr_bytes=c['REAL_DMA_COUNTS']['attribute_beats']*16,ar=c['REAL_DMA_COUNTS']['attribute_bursts'],
                         precomputed=c['REAL_T08']['world_precomputed'],internal_mae=row['internal_float_mae'],
                         host_wall_s=row['execution']['wall_seconds'],host_user_cpu_s=cpu))
    for a,b in [(0,1),(2,3)]:
        assert np.array_equal(imgs[a],imgs[b])
        compare_states(d/f'f{a}'/'state.memh',d/f'f{b}'/'state.memh')
    diff=(np.abs(imgs[2]-reference)-np.abs(imgs[1]-reference)).sum(axis=2)
    y,x=np.unravel_index(diff.argmax(),diff.shape)
    return dict(scene=scene,camera=oracle['camera'],gaussians=meta['gaussians'],full_model=True,
                width=oracle['width'],height=oracle['height'],rows=rows,ply_sha256=meta['ply_sha256'],
                mean_camera_ref_sha256=oracle['input_sha256'],comparison_sha256=sha(d/'comparison.json'),
                pixels_changed=int(np.any(imgs[1]!=imgs[2],axis=2).sum()),pixels_worse=int((diff>0).sum()),
                pixels_improved=int((diff<0).sum()),absolute_error_delta_sum=int(diff.sum()),
                worst_delta=dict(x=int(x),y=int(y),q20=imgs[1][y,x].tolist(),q24=imgs[2][y,x].tolist(),reference=reference[y,x].tolist()),
                q24_compact_cycle_delta_vs_v1=rows[2]['command_cycles']-rows[1]['command_cycles'],
                q24_compact_speedup_percent_vs_q24_raw=100*(1-rows[2]['command_cycles']/rows[3]['command_cycles']),
                q24_byte_reduction_percent=100*(1-rows[2]['attr_bytes']/rows[3]['attr_bytes']))


if __name__=='__main__':
    binary=read(OUT/'build/binary.json')
    assert sha(binary['exe'])==binary['elf_sha256'] and all(sha(ROOT/p)==h for p,h in binary['sources'].items())
    archive=read(OUT/'report.json')
    assert sha(ROOT/'scripts/run_t08_dual_full.py')==archive['script_sha256']
    assert archive['results']==[read(OUT/'real'/s/'comparison.json') for s in SCENES]
    rows=[audit(scene,binary) for scene in SCENES]
    save(OUT/'audit.json',dict(results=rows,report_sha256=sha(OUT/'report.json'),script_sha256=sha(__file__),
         scope='Width128, G/legacy-ideal, all records. Generic bench label ignored; launch MEAN/CAMERA hashes bind each scene to its reference.',
         decision='Retain Q24 command as opt-in for precision recovery and attribute DMA savings. Formal quality, timing, DDR and throughput remain open.',
         signed_off=False))
