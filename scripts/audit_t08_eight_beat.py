"""Audit full128 shared-memory Q24 frames, slot projections and TT cost for selection."""
from pathlib import Path
import sys
from PIL import Image
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_eight_beat_header import OUT,LINE
from scripts.run_t08_attribute_line_header import BASELINE
from scripts.run_t08_dual_full import FLOAT,compare_states
from scripts.read_rgb888_frame import decode_rgb888
from scripts.t08_common import SCENES,read,save,sha


def main():
    projections={r['scene']:r for r in read(LINE/'decision.json')['results']}
    source=read(OUT/'build/binary.json')
    assert sha(source['exe'])==source['elf_sha256'] and all(sha(ROOT/p)==h for p,h in source['sources'].items())
    report=read(OUT/'full128_report.json')
    assert len(report['results'])==len(SCENES) and read(OUT/'status.json')['status']=='EIGHT_BEAT_COMPARED'
    results=[]
    for s,row in zip(SCENES,report['results'],strict=True):
        d=OUT/'full128'/s
        olddir=BASELINE/'full128'/s/'f2_t1'
        compact=read(olddir/'result.json')
        raw=read(olddir.parent/'f3_t1/result.json')
        line=read(LINE/'full128'/s/'result.json')
        assert row['scene']==s and row==read(d/'result.json')
        ex=read(d/'run.execution.json')
        assert ex==row['execution'] and ex['exit_code']==0 and sha(d/'run.log')==ex['log_sha256']
        assert all(sha(d/p)==h for p,h in row['hashes'].items())
        launch=read(d/'launch.json')
        assert launch['command']==read(d/'run.command.json') and launch['elf_sha256']==source['elf_sha256']
        assert launch['inputs']==read(olddir/'launch.json')['input_sha256'] and launch['ref_sha256']==sha(olddir/'result.json')
        for f in ('rgb.memh','frame.png','sorted.txt'):
            assert row['hashes'][f]==compact['hashes'][f]==raw['hashes'][f]==line['hashes'][f]
        assert sha(olddir/'state.memh')==compact['hashes']['state.memh']
        assert compare_states(d/'state.memh',olddir/'state.memh')==row['terminal_t_differences']
        oracle=next(r for r in read(FLOAT/'audit.json')['results'] if r['scene']==s)
        fp=FLOAT/s/'float_floor_0.30078125_jac_clamp.png'
        assert sha(fp)==oracle['float_sha256'] and launch['inputs']['CAMERA']==oracle['input_sha256']['camera.memh']
        rgb=decode_rgb888(bytes.fromhex((d/'rgb.memh').read_text()),oracle['width'],oracle['height'])
        assert rgb.tobytes()==Image.open(d/'frame.png').tobytes()
        mae=float(np.abs(rgb.astype(np.int16)-np.asarray(Image.open(fp).convert('RGB')).astype(np.int16)).mean())
        projected=projections[s]['eight_projection']
        c=row['counters']
        dma=c['REAL_DMA_COUNTS']
        assert (row['attr_bytes'],dma['attribute_bursts'])==(projected['bytes'],projected['bursts'])
        assert c['REAL_T08']['requests']==projections[s]['records'] and c['REAL_T08']['precomputed']==c['REAL_T08']['world_precomputed']>0
        assert c['REAL_LPDDR']['qsu_b']==dma['qsu_write_bursts'] and c['REAL_LPDDR']['out_b']==dma['output_write_bursts']
        cycles=row['cycles']
        results.append(dict(scene=s,camera=oracle['camera'],gaussians=oracle['gaussians'],width=oracle['width'],height=oracle['height'],
            cycles=cycles,raw_cycles=raw['cycles'],split_cycles=compact['cycles'],line_cycles=line['cycles'],
            pct_saved_vs_raw=100*(1-cycles/raw['cycles']),pct_saved_vs_split=100*(1-cycles/compact['cycles']),
            attribute_bytes=row['attr_bytes'],raw_bytes=raw['counters']['REAL_DMA_COUNTS']['attribute_beats']*16,
            pct_bytes_saved_vs_raw=100*(1-row['attr_bytes']/projections[s]['raw_bytes']),
            attribute_bursts=dma['attribute_bursts'],logical_requests=c['REAL_T08']['requests'],
            byte_padding=row['attr_bytes']-row['old_attr_bytes'],all_line_requests=c['REAL_LPDDR']['lines'],
            terminal_t_differences=row['terminal_t_differences'],internal_mae_rgb8=mae,
            image_sha256=row['hashes']['frame.png'],case_sha256=sha(d/'result.json')))
    cost=read(OUT/'mapping/report.json')
    for r in cost['results']:
        assert all(sha(p)==h for p,h in r['hashes'].items())
    save(OUT/'full128_decision.json',dict(results=results,script_sha256=sha(__file__),
         report_sha256=sha(OUT/'full128_report.json'),cost_sha256=sha(OUT/'mapping/report.json'),
         decision='Retain the eight-beat v2 command for development. Stop changing the initial burst size; require mapped gate and native shared-memory regressions, integrated timing and official quality before release.',
         signed_off=False))
    for r in results:
        print(r['scene'],r['cycles'],round(r['pct_saved_vs_raw'],3),round(r['pct_saved_vs_split'],3),
              round(r['pct_bytes_saved_vs_raw'],3),r['internal_mae_rgb8'])


if __name__=='__main__':
    main()
