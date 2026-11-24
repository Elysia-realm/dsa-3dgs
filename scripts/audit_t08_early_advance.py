"""Summarize attributable DMA timing changes and retain scene-level evidence."""
from pathlib import Path
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.run_t08_early_advance import OUT, matching_source, references, wait_for_current
from scripts.read_rgb888_frame import decode_rgb888
from scripts.t08_common import BASE, T07, read, save, sha


def check_full_image(scene, directory, input_sha256):
    float_root = ROOT / 'experiments/t01_resume_20261025/fresh_float'
    filepath = float_root / scene / 'float_floor_0.30078125_jac_clamp.png'
    oracle = next(r for r in read(float_root / 'audit.json')['results'] if r['scene'] == scene)
    assert sha(filepath) == oracle['float_sha256']
    assert input_sha256['MEAN'] == oracle['input_sha256']['mean.memh']
    assert input_sha256['CAMERA'] == oracle['input_sha256']['camera.memh']
    prior = read(T07 / 'real/full/C' / scene / 'result.json')
    assert prior['independent_float_mae'] == oracle['mae']
    raw = bytes(int(x, 16) for x in (directory / 'rgb.memh').read_text().split())
    pixels = decode_rgb888(raw, oracle['width'], oracle['height'])
    output = directory / 'audit_frame.png'
    if not output.exists():
        Image.fromarray(pixels).save(output)
    assert Image.open(output).tobytes() == pixels.tobytes()
    expected = np.asarray(Image.open(filepath).convert('RGB'))
    assert expected.shape == pixels.shape
    mae = float(np.abs(pixels.astype(np.int16) - expected.astype(np.int16)).mean())
    assert mae == oracle['mae'], (scene, mae, oracle['mae'])
    return dict(mae_rgb8=mae, internal_reference_sha256=oracle['float_sha256'],
                candidate_image_sha256=sha(output), scope='Width128 independent internal float reference')


def audit(kind):
    report = OUT / f'{kind}_report.json'
    if not report.exists():
        return None
    matching_source()
    results = read(report)['results']
    pairs = {(r['scene'], r['case'], r['early_advance']): r for r in results}
    workloads = list(references(kind))
    assert len(results) == len(pairs) == len(workloads) * 2
    comparisons = []
    for scene, key, reference, _ in workloads:
        off, on = (pairs[scene, key, e] for e in (0, 1))
        assert off['input_sha256'] == on['input_sha256']
        assert off['previous_cycles'] == on['previous_cycles']
        if kind != 'continuous':
            assert off['command_cycles'] == off['previous_cycles']
        for row in (off, on):
            directory = OUT / 'real' / kind / str(row['early_advance']) / scene / key
            assert all(sha(directory / f) == h for f, h in row['outputs'].items())
        fmt0 = pairs.get((scene, 'f0', 1)) if kind == 'full' else None
        if kind in ('subset', 'continuous'):
            fmt0 = pairs[scene, key.removesuffix('_f1')+'_f0', 1] if key.endswith('_f1') else on
        internal_float = None
        if kind == 'full' and on['format'] == 1:
            internal_float = check_full_image(scene, OUT/'real/full/1'/scene/key, on['input_sha256'])
        attr_bursts = off['counters']['REAL_DMA_COUNTS']['attribute_bursts']
        # Repeat bench reports DMA counts for the timed frame and REAL_T08
        # requests across the pair of frames. Do not subtract these scopes.
        attr_records = off['counters']['REAL_T08']['requests'] if kind != 'repeat' else None
        if attr_records is not None:
            assert attr_bursts >= attr_records
        comparisons.append(dict(scene=scene, workload=key, format=on['format'],
            baseline_cycles=off['command_cycles'], candidate_cycles=on['command_cycles'],
            saved_cycles=off['command_cycles']-on['command_cycles'],
            savings_percent=100*(1-on['command_cycles']/off['command_cycles']),
            legacy_to_continuous_off_delta_cycles=off['command_cycles']-off['previous_cycles'] if kind=='continuous' else None,
            candidate_raw_delta_percent=100*(on['command_cycles']/fmt0['command_cycles']-1) if fmt0 else None,
            attribute_bytes=16*on['counters']['REAL_DMA_COUNTS']['attribute_beats'],
            attribute_bursts=attr_bursts, attribute_records=attr_records,
            avoided_transition_cycles_local=attr_bursts-attr_records if attr_records is not None else None,
            avoided_decode_entry_cycles_local=(attr_records if on['format']==1 else 0) if attr_records is not None else None,
            independent_float=internal_float,
            baseline_reference_sha256=sha(reference / 'result.json')))
    result = dict(status='PASS_SCOPED', cases=len(results), comparisons=comparisons, report_sha256=sha(report),
                  full_model=kind=='full', target_gt_pass=False, signed_off=False)
    save(OUT / f'{kind}_audit.json', result)
    compressed = [r for r in comparisons if r['format']==1]
    print(kind, len(results), 'compressed savings range', min(r['savings_percent'] for r in compressed),
          max(r['savings_percent'] for r in compressed), flush=True)
    return result


def audit_completed_full_subset():
    partial = []
    for scene, key, origin, _ in references('full'):
        if key != 'f1':
            continue
        folder = OUT / 'real/full/1' / scene / key
        marker = folder / 'result.json'
        if not marker.exists():
            continue
        row = read(marker)
        assert all(sha(folder / f) == h for f, h in row['outputs'].items())
        image = check_full_image(scene, folder, row['input_sha256'])
        raw_marker = OUT / 'real/full/1' / scene / 'f0/result.json'
        raw_cycles = read(raw_marker)['command_cycles'] if raw_marker.exists() else None
        split = read(origin / 'result.json')['command_cycles']
        assert split == row['previous_cycles']
        cycles = row['command_cycles']
        partial.append(dict(scene=scene, candidate_cycles=cycles, frozen_split_cycles=split, candidate_raw_cycles=raw_cycles,
            savings_vs_frozen_split_percent=100*(split-cycles)/split,
            savings_vs_candidate_raw_percent=100*(raw_cycles-cycles)/raw_cycles if raw_cycles else None,
            independent_float=image, result_sha256=sha(marker)))
    if partial:
        save(OUT / 'full_partial_audit.json', dict(status='PARTIAL_FULL_MODEL_EVIDENCE', results=partial, signed_off=False))
        print('Full compressed candidates checked:', [(r['scene'], r['candidate_cycles']) for r in partial], flush=True)


if __name__ == '__main__':
    if '--after-full' in sys.argv:
        wait_for_current('full')
    for name in ('subset', 'mixed', 'repeat', 'full', 'continuous'):
        audit(name)
    if not (OUT / 'full_report.json').exists():
        audit_completed_full_subset()
