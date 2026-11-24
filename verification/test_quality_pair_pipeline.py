from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


class QualityPairPipelineTests(unittest.TestCase):
    def test_prepare_pair_and_evaluate_identical_image(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            manifest = work / "manifest.json"
            state = work / "frame.memh"
            reference = work / "reference.png"
            pairs = work / "pairs"
            metrics = work / "metrics.json"
            manifest.write_text(json.dumps({"width": 1, "height": 1}), encoding="utf-8")
            word = 4096 | (2048 << 13) | (1024 << 26) | (32768 << 39)
            state.write_text(f"{word:032x}\n", encoding="ascii")
            Image.new("RGB", (1, 1), (255, 128, 64)).save(reference)
            subprocess.run([
                sys.executable, str(ROOT / "scripts/prepare_rtl_quality_pairs.py"),
                "--entry", "one", str(state), str(manifest), str(reference),
                "--output-root", str(pairs),
            ], cwd=ROOT, check=True, capture_output=True, text=True)
            subprocess.run([
                sys.executable, str(ROOT / "scripts/evaluate_image_quality.py"),
                str(pairs / "reference"), str(pairs / "candidate"), "--output", str(metrics),
            ], cwd=ROOT, check=True, capture_output=True, text=True)
            report = json.loads(metrics.read_text(encoding="utf-8"))
            self.assertEqual(report["pair_count"], 1)
            self.assertEqual(report["aggregate_mean"]["psnr"], float("inf"))
            self.assertAlmostEqual(report["aggregate_mean"]["ssim"], 1.0)
            self.assertIsNone(report["images"][0]["lpips"])


if __name__ == "__main__":
    unittest.main()
