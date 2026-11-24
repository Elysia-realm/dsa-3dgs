"""Regenerate the five independent float diagnostics from the accepted full inputs."""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import numpy as np
from PIL import Image
from scripts import diagnose_t06_low_resolution as reference
from scripts.t01_resume_common import BASE, FULL, read, save, sha, run_logged, frozen

def main():
    frozen()
    out = BASE / 'fresh_float'
    out.mkdir(exist_ok=True)
    files = ['scripts/diagnose_t06_low_resolution.py', 'scripts/build_full_frame_rtl_batch.py',
             'model/io/scene.py', 'scripts/check_t01_float_provenance.py']
    source_hashes = {f: sha(ROOT / f) for f in files}
    raw = read(BASE / 'encoding/input_encoding_report.json')['raw_ply']
    rows = []
    for scene in ['bonsai', 'counter', 'room', 'train', 'truck']:
        current = read(BASE / 'real/full' / scene / 'result.json')
        inputs = {f: sha(FULL / scene / f) for f in
                  ['manifest.json', 'expected_sorted.txt', 'camera.memh', 'mean.memh', 'attribute.memh']}
        for f, h in current['input_sha256'].items():
            assert inputs[f] == h.upper(), (scene, f)
        ply = ROOT / raw[scene]['path']
        assert sha(ply) == raw[scene]['sha256'].upper()
        cmd = [sys.executable, str(ROOT / files[0]), '--scenes', scene, '--floors',
               '0.30078125', '--clamp', '--input-root', str(FULL), '--output-root', str(out)]
        execution = run_logged(cmd, out / scene / 'run.log')
        image = out / scene / 'float_floor_0.30078125_jac_clamp.png'
        result = read(image.with_suffix('.json'))
        assert result['processed_depth_sorted_prefix'] == result['total_depth_visible']
        assert sha(image) == current['float_reference_sha256'].upper(), ('reference changed', scene)
        rtl = np.frombuffer((BASE / 'real/full' / scene / 'frame.rgb').read_bytes(), dtype=np.uint8)
        pixels = np.asarray(Image.open(image)).reshape(-1)
        assert pixels.size == rtl.size
        mae = float(np.mean(np.abs(pixels.astype(float) - rtl)))
        assert abs(mae - current['independent_float_mae']) < 1e-12 and mae <= 5
        # Detect concurrent changes to source or inputs during regeneration.
        assert all(sha(ROOT / f) == h for f, h in source_hashes.items())
        assert all(sha(FULL / scene / f) == h for f, h in inputs.items())
        assert sha(ply) == raw[scene]['sha256'].upper()
        rows.append(dict(scene=scene, camera=current['camera_index'], gaussians=current['gaussians'],
                         full_scene=True, width=current['width'], height=current['height'],
                         input_sha256=inputs, raw_ply=raw[scene], float_sha256=sha(image),
                         rtl_rgb_sha256=sha(BASE / 'real/full' / scene / 'frame.rgb'),
                         reference_matches_previously_used=True, mae=mae, execution=execution))
        print('PASS', scene, 'fresh reference identical; MAE', mae, flush=True)
    save(out / 'audit.json', dict(status='PASS', source_sha256=source_hashes, results=rows,
         scope='Fresh WSL float diagnostic from raw PLY and exact accepted camera/order inputs; independent arithmetic, shared source quantization/ordering; not GT or an independent sorting proof. No RTL output replaced.'))

if __name__ == '__main__':
    main()
