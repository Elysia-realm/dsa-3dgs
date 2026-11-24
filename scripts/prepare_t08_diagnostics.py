"""Freeze native-camera inputs and necessary service budgets; no rendering claims."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.t08_common import BASE, T07, SCENES, MAX_COUNT, MAX_PIXELS, freeze_baseline, read, save, sha
from model.io.scene import discover_scenes, read_cameras, parse_ply_header
from model.io.dma_workload import camera_fixed, CAMERA_DESCRIPTOR_TAG


def prepare():
    freeze_baseline()
    scenes = {s.name: s for s in discover_scenes(ROOT / 'data')}
    rows = []
    for name, index in SCENES.items():
        scene = scenes[name]
        original = ROOT / 'experiments/t06_full_precount_mem_20261022' / name
        old = read(original / 'manifest.json')
        reference = read(T07 / 'real/full/C' / name / 'result.json')
        assert old['full_scene'] and old['camera_index'] == index
        camera = read_cameras(scene.cameras_json)[index]
        count = parse_ply_header(scene.final_ply).vertex_count
        assert count == old['gaussians'] == reference['gaussians'] and count <= MAX_COUNT
        assert sha(scene.final_ply) == old['source_ply_sha256'].upper()
        w, h = camera.width, camera.height
        assert 0 < w < 65536 and 0 < h < 65536 and w * h <= MAX_PIXELS
        fixed = camera_fixed(camera)
        words = [*fixed['rotation_q20'], *fixed['translation_q16'], *fixed['position_q16'],
                 *fixed['fx_fy_cx_cy_q16'], *fixed['near_far_q16'], fixed['regularizer_q8'],
                 0, 0, 0, w, h, (CAMERA_DESCRIPTOR_TAG << 32) | count]
        previous = [int(s, 16) for s in (original / 'camera.memh').read_text().split()]
        words = [int(v) & ((1 << 64) - 1) for v in words]
        assert len(words) == len(previous) == 28
        # Only intrinsics and dimensions change. Original unsorted means and
        # QSU depth visibility/order are independent of those fields.
        changed = [i for i in range(28) if previous[i] != words[i]]
        assert set(changed) <= {15, 16, 17, 18, 25, 26}, changed
        dest = BASE / 'inputs/native' / name
        dest.mkdir(parents=True, exist_ok=True)
        content = ''.join(f'{v:016x}\n' for v in words)
        camera_path = dest / 'camera.memh'
        if camera_path.exists():
            assert camera_path.read_text() == content
        else:
            camera_path.write_text(content, encoding='ascii')
        inputs = {'CAMERA': str(camera_path)}
        hashes = {'CAMERA': sha(camera_path)}
        for key, filename in [('MEAN', 'mean.memh'), ('ATTR', 'attribute.memh')]:
            path = original / filename
            digest = sha(path)
            assert digest == old['input_sha256'][filename].upper()
            assert digest == reference['input_sha256'][key].upper()
            inputs[key], hashes[key] = str(path), digest
        c = reference['counters']['REAL_DMA_COUNTS']
        stride = (w * 3 + 15) & ~15
        # This is a necessary floor, not a latency estimate: no render-state
        # misses/writes, arbitration, turnarounds, or decoder overhead included.
        fixed_read_bytes = 16 * sum(c[k] for k in ['camera_beats', 'mean_beats', 'attribute_beats', 'qsu_read_beats'])
        fixed_write_bytes = c['qsu_write_beats'] * 16
        output_read_bytes = w * h * 16
        output_write_bytes = stride * h
        floor_bytes = fixed_read_bytes + fixed_write_bytes + output_read_bytes + output_write_bytes
        budget = 200000000 / 30
        row = dict(scene=name, camera_index=index, gaussians=count, full_scene=True, width=w, height=h,
                   camera_source=str(scene.cameras_json), camera_source_sha256=sha(scene.cameras_json),
                   ply=str(scene.final_ply), ply_sha256=sha(scene.final_ply),
                   inputs=inputs, input_sha256=hashes, changed_camera_word_indices=changed,
                   software_preprocessing='PLY/fixed-format encoding only; original unsorted complete model; no CPU pivots or batches',
                   status='INPUT_PREPARED_NOT_SIMULATED', signed_off=False,
                   budget=dict(cycles_at_assumed_200MHz_30FPS=budget,
                     assumed_frequency_verified=False, model_parameter_bytes_uncompressed=count * 160,
                     attribute_record_bytes=144, sh_payload_bits_per_record=864,
                     low_resolution_reference_sha256=sha(T07 / 'real/full/C' / name / 'result.json'),
                     invariant_frontend_read_bytes=fixed_read_bytes,
                     invariant_qsu_write_bytes=fixed_write_bytes,
                     invariant_traffic_assumption='same means/extrinsics/near/far => same depth-visible set and deterministic QSU; confirm in native RTL results',
                     final_rgb_state_read_bytes=output_read_bytes, final_rgb_write_bytes=output_write_bytes,
                     shared_total_bytes_necessary_floor=floor_bytes,
                     shared_GBps_necessary_floor_at_30FPS=floor_bytes * 30 / 1e9,
                     shared_128bit_beats_necessary_floor=floor_bytes // 16,
                     shared_128bit_beats_per_cycle_required=floor_bytes / 16 / budget,
                     attribute_beats_per_cycle_required=c['attribute_beats'] / budget,
                     qsu_read_beats_per_cycle_required=c['qsu_read_beats'] / budget,
                     termination_table_entries=256, image_blocks=((w+7)//8)*((h+7)//8),
                     native_render_state_traffic=None, native_frame_cycles=None,
                     calibrated_shared_DDR=False))
        marker = dest / 'manifest.json'
        if marker.exists():
            assert read(marker) == row
        else:
            save(marker, row)
        rows.append(row)
        print('PREPARED', name, count, f'{w}x{h}', 'shared bandwidth floor GB/s', round(floor_bytes*30/1e9, 3), flush=True)
    report = dict(status='INPUTS_AND_NECESSARY_BUDGET_ONLY', signed_off=False, scenes=rows,
                  excludes=['native RTL result pending', 'render-state traffic', 'DDR arbitration/timing', 'GT quality', 'verified hardware frequency'],
                  script_sha256=sha(Path(__file__)),
                  source_sha256={f:sha(ROOT/f) for f in ['scripts/t08_common.py','model/io/scene.py','model/io/dma_workload.py']})
    save(BASE / 'entry_budget.json', report)


if __name__ == '__main__':
    prepare()
