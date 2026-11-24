"""Validate archived T04 evidence without rerunning the simulations."""
import hashlib
import json
import unittest
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / 'experiments/t04_20261005/real_rgb/real_rgb_report.json'


class T04RealRgbEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = json.loads(REPORT.read_text(encoding='utf-8'))

    def test_current_rtl_matches_all_report_hashes(self):
        status=json.loads((ROOT/'verification/implementation_status.json').read_text(encoding='utf-8'))
        if status.get('t04_real_rgb_report_matches_current_rtl') is False:
            self.skipTest('T04 source hashes retained as historical evidence; current integration hashes checked by test_t05_evidence')
        for relative, expected in self.report['source_sha256'].items():
            with self.subTest(source=relative):
                self.assertEqual(hashlib.sha256((ROOT/relative).read_bytes()).hexdigest(), expected)

    def test_five_scenes_and_both_profiles_completed(self):
        self.assertEqual(self.report['status'], 'PASS')
        self.assertEqual(self.report['failed'], 0)
        scenes = {r['scene'] for r in self.report['results']}
        self.assertGreaterEqual(len(scenes), 5)
        self.assertEqual(len(scenes), self.report['scene_count'])
        self.assertEqual(len(self.report['results']), self.report['run_count'])
        for scene in scenes:
            entries = [r for r in self.report['results'] if r['scene'] == scene]
            self.assertEqual({r['profile'] for r in entries}, {'ideal', 'limited'})
            self.assertEqual(len({r['rgb_sha256'] for r in entries}), 1)
            manifest = json.loads((REPORT.parent/scene/'manifest.json').read_text())
            self.assertTrue(Path(manifest['source_ply']).is_file())
            self.assertEqual(len(set(manifest['original_gaussian_indices'])), 8192)
            for r in entries:
                self.assertEqual(r['status'], 'PASS')
                self.assertEqual(r['returncode'], 0)
                self.assertEqual(r['rgb_byte_mismatches'], 0)
                self.assertEqual(r['camera_index'], manifest['camera_index'])
                self.assertEqual(r['batches'], 64)
                self.assertTrue(any('error=00000000' in x for x in r['summary']))

    def test_png_is_exact_dma_capture_and_matches_state_oracle(self):
        for result in self.report['results']:
            with self.subTest(scene=result['scene'], profile=result['profile']):
                folder = REPORT.parent/result['scene']/result['profile']
                captured = bytes(int(x, 16) for x in (folder/'frame_rgb.memh').read_text().split())
                raw = (folder/'frame.rgb').read_bytes()
                self.assertEqual(captured, raw)
                self.assertEqual(hashlib.sha256(raw).hexdigest(), result['rgb_sha256'])
                w, h = result['width'], result['height']
                stride = (w*3+15)&~15
                self.assertEqual(len(raw), stride*h)
                image = Image.open(folder/'frame.png')
                self.assertEqual(image.size, (w,h))
                self.assertEqual(image.tobytes(), b''.join(raw[y*stride:y*stride+w*3] for y in range(h)))
                words = [int(x,16) for x in (folder/'state.memh').read_text().split()]
                self.assertEqual(len(words), w*h)
                for index, word in enumerate(words):
                    y, x = divmod(index, w)
                    if (word>>55)&65535 == 1:
                        expected = bytes(min(255, (((word>>(13*c))&8191)*255+2048)//4096) for c in range(3))
                    else:
                        expected = b'\0\0\0'
                    self.assertEqual(raw[y*stride+x*3:y*stride+x*3+3], expected)
                self.assertIn('PASS: tb_real_dma_workload', (folder/'run.log').read_text())


if __name__ == '__main__':
    unittest.main()
