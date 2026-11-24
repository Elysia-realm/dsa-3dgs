from __future__ import annotations

import json
import random
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from model.fixed.alpha import alpha_block_float_codes, conservative_shape_block_reject_code
from scripts.audit_shape_resource_guard import audit
from scripts.run_shared_pe_validation import semantic_frame_sha256, sha256


def rtl_delta(pixel: int, mean_y_q8: int, coordinate_shift: int) -> int:
    delta = (pixel << 8) - mean_y_q8
    if coordinate_shift >= 0:
        if coordinate_shift == 0:
            value = delta << 2
        else:
            magnitude = ((abs(delta) << 2) + (1 << (coordinate_shift - 1))) >> coordinate_shift
            value = -magnitude if delta < 0 else magnitude
    elif coordinate_shift <= -30:
        value = -(2**63 - 1) if delta < 0 else 2**63 - 1
    else:
        value = delta << (2 - coordinate_shift)
    return min(32767, max(-32768, value))


class ShapeBlockRejectTest(unittest.TestCase):
    def test_epoch_aware_image_digest_ignores_stale_slot_payload(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            a, b = Path(temp) / "a.memh", Path(temp) / "b.memh"
            current = (7 << 55) | (0xA55A << 39) | 0x1234
            a.write_text(f"{current:018x}\n{(6 << 55) | 0x789:018x}\n", encoding="utf-8")
            b.write_text(f"{current:018x}\n{(7 << 55) | (0xFFFF << 39):018x}\n", encoding="utf-8")
            self.assertNotEqual(sha256(a), sha256(b))
            self.assertEqual(semantic_frame_sha256(a, 7), semantic_frame_sha256(b, 7))

    def test_historical_resource_guard_is_explicitly_not_ppa(self) -> None:
        root = Path(__file__).resolve().parents[1]
        bundle = root / "experiments/shared_pe/validation_20260917_shape_resource_guard"
        with self.assertRaisesRegex(ValueError, "stale RTL evidence: rtl/raster/blend_fixed_core.sv"):
            audit(root, bundle)
        report = json.loads((bundle / "shape_resource_audit.json").read_text(encoding="utf-8"))
        self.assertTrue(report["source_current"])  # true at capture, not current now
        self.assertEqual(report["structural"]["default_shape_instances"], 0)
        self.assertEqual(report["structural"]["enabled_shape_instances"], 1)
        self.assertEqual(report["unchanged_six_scene_runs"], 144)
        self.assertEqual(report["n32_candidate_runs"], 104)
        self.assertEqual(report["n32_improved_vs_shared"], 104)
        self.assertLess(report["n32_faster_than_bypass"], 104)
        self.assertFalse(report["ppa_signed_off"])
        status = json.loads((root / "verification/implementation_status.json").read_text(encoding="utf-8"))
        self.assertEqual(status["shape_block_reject_candidate_real_runs"], report["n32_candidate_runs"])
        self.assertEqual(status["shape_block_reject_candidate_faster_than_bypass_runs"],
                         report["n32_faster_than_bypass"])
        self.assertEqual(status["shape_block_reject_candidate_default_elaboration_instances"], 0)

    def test_resource_guard_rejects_stale_rtl_digest(self) -> None:
        root = Path(__file__).resolve().parents[1]
        bundle = root / "experiments/shared_pe/validation_20260917_shape_resource_guard"
        with patch("scripts.audit_shape_resource_guard.sha256", return_value="STALE"):
            with self.assertRaisesRegex(ValueError, "stale RTL evidence"):
                audit(root, bundle)

    def test_opacity_bin_thresholds_are_sub_alpha_threshold(self) -> None:
        for opacity, axis in ((512, 2703), (1024, 2959), (2048, 3214),
                              (4096, 3413), (8191, 3637)):
            alpha, passed = alpha_block_float_codes(0, axis, 0, 0, 4096, 0, 0, opacity)
            self.assertFalse(bool(passed), (opacity, axis, int(alpha)))

    def test_random_rejections_have_no_passing_pixel(self) -> None:
        rng = random.Random(0x3D65A5)
        rejected = 0
        for _ in range(20000):
            y0 = rng.randrange(0, 1024)
            y1 = y0 + rng.randrange(1, 9)
            mean_y_q8 = rng.randrange(-128, 1152) * 256 + rng.randrange(256)
            coordinate_shift = rng.randrange(-2, 7)
            factor_shift = rng.randrange(-8, 5)
            l11 = rng.randrange(0, 32768)
            opacity = rng.randrange(0, 8192)
            if not conservative_shape_block_reject_code(
                y0, y1, mean_y_q8, coordinate_shift, factor_shift, l11, opacity
            ):
                continue
            rejected += 1
            for pixel_y in range(y0, y1):
                dy = rtl_delta(pixel_y, mean_y_q8, coordinate_shift)
                _, passed = alpha_block_float_codes(
                    0, dy, 0, 0, l11, coordinate_shift, factor_shift, opacity
                )
                self.assertFalse(bool(passed), (y0, y1, pixel_y, mean_y_q8, coordinate_shift,
                                                 factor_shift, l11, opacity, dy))
        self.assertGreater(rejected, 1000)


if __name__ == "__main__":
    unittest.main()
