from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.fixed import AlphaFixedConfig, alpha_block_float_codes, alpha_fixed, alpha_fixed_cholesky_block_float, alpha_fixed_cholesky_shared_scale, alpha_fixed_shared_scale, alpha_float, blend_codes, cholesky_factors, encode_block_float_gaussian, encode_pixel_delta, image_metrics, psnr, ssim


class AlphaFixedTests(unittest.TestCase):
    def test_projection_encoding_drives_integer_oracle(self):
        encoded = encode_block_float_gaussian(
            100.25, 80.5, 0, 0, 1920, 1080, 0.25, 0.05, 0.5, 0.7
        )
        dx, dy = encode_pixel_delta(101, 81, 100.25, 80.5, encoded["coordinate_shift"])
        alpha, passed = alpha_block_float_codes(
            dx, dy, encoded["l00_q12"], encoded["l10_q12"], encoded["l11_q12"],
            encoded["coordinate_shift"], encoded["factor_shift"], encoded["opacity_q12"],
        )
        self.assertGreater(int(alpha), 0)
        self.assertTrue(bool(passed))

    def test_integer_oracle_center_and_far_codes(self):
        alpha, passed = alpha_block_float_codes(
            np.array([0, 16 << 10]), np.array([0, 16 << 10]),
            np.array([1 << 12, 1 << 12]), np.array([0, 0]),
            np.array([1 << 12, 1 << 12]), 0, 0,
            np.array([2867, 2867]),
        )
        self.assertEqual(int(alpha[0]), 2867)
        self.assertTrue(bool(passed[0]))
        self.assertFalse(bool(passed[1]))

    def test_block_float_handles_large_coordinate_and_small_factor(self):
        reference = alpha_float(65536.0, 32768.0, 1.0e-9, 0.0, 2.0e-9, 0.8)
        candidate = alpha_fixed_cholesky_block_float(
            65536.0, 32768.0, 1.0e-9, 0.0, 2.0e-9, 0.8,
            12, -17, apply_threshold=False,
        )
        self.assertLess(abs(float(reference) - float(candidate)), 0.02)

    def test_cholesky_reconstructs_positive_semidefinite_conic(self):
        l00, l10, l11 = cholesky_factors(4.0, 1.0, 2.0)
        self.assertAlmostEqual(float(l00 * l00), 4.0)
        self.assertAlmostEqual(float(l00 * l10), 1.0)
        self.assertAlmostEqual(float(l10 * l10 + l11 * l11), 2.0)

    def test_cholesky_quantization_cannot_make_quadratic_negative(self):
        rng = np.random.default_rng(19)
        candidate = alpha_fixed_cholesky_shared_scale(
            rng.uniform(-16, 16, 1000), rng.uniform(-16, 16, 1000),
            np.full(1000, 1.0), np.full(1000, 0.75), np.full(1000, 1.0),
            np.full(1000, 0.8), np.zeros(1000, dtype=np.int64),
            apply_threshold=False,
        )
        self.assertTrue(np.all(candidate <= 0.8003))
        self.assertTrue(np.all(candidate >= 0.0))

    def test_shared_power_of_two_scale_preserves_wide_gaussian(self):
        reference = alpha_float(65536.0, 32768.0, 1.0e-9, 0.0, 2.0e-9, 0.8)
        candidate = alpha_fixed_shared_scale(
            65536.0, 32768.0, 1.0e-9, 0.0, 2.0e-9, 0.8, 12,
            AlphaFixedConfig(conic_fractional_bits=16), apply_threshold=False,
        )
        self.assertLess(abs(float(reference) - float(candidate)), 0.02)

    def test_center_alpha_tracks_opacity(self):
        config = AlphaFixedConfig(exp_lut_entries=256)
        value = float(alpha_fixed(0, 0, 1, 0, 1, 0.7, config))
        self.assertAlmostEqual(value, 0.7, places=3)

    def test_far_sample_is_pruned(self):
        self.assertEqual(float(alpha_fixed(10, 10, 1, 0, 1, 0.9)), 0.0)

    def test_random_domain_error_is_bounded(self):
        rng = np.random.default_rng(17)
        count = 20000
        dx = rng.uniform(-3, 3, count)
        dy = rng.uniform(-3, 3, count)
        a = rng.uniform(0.05, 3.0, count)
        c = rng.uniform(0.05, 3.0, count)
        b_limit = np.sqrt(a * c) * 0.8
        b = rng.uniform(-1, 1, count) * b_limit
        opacity = rng.uniform(0.01, 1.0, count)
        reference = alpha_float(dx, dy, a, b, c, opacity)
        candidate = alpha_fixed(dx, dy, a, b, c, opacity)
        self.assertLess(float(np.quantile(np.abs(reference - candidate), 0.99)), 0.02)


class ImageMetricTests(unittest.TestCase):
    def test_identity_is_perfect(self):
        rng = np.random.default_rng(2)
        image = rng.random((32, 32, 3))
        self.assertTrue(np.isinf(psnr(image, image)))
        self.assertAlmostEqual(ssim(image, image), 1.0, places=9)

    def test_noise_reduces_quality(self):
        rng = np.random.default_rng(3)
        image = rng.random((32, 32, 3))
        noisy = np.clip(image + rng.normal(0, 0.02, image.shape), 0, 1)
        metrics = image_metrics(image, noisy)
        self.assertGreater(metrics["psnr"], 25)
        self.assertLess(metrics["ssim"], 1.0)
        self.assertIsNone(metrics["lpips"])


class BlendFixedTests(unittest.TestCase):
    def test_front_to_back_blend_codes(self):
        result = blend_codes((0, 0, 0), 65535, (4096, 2048, 0), 2048)
        self.assertEqual(result.rgb_q12, (2048, 1024, 0))
        self.assertEqual(result.transmittance_q16, 32768)
        self.assertFalse(result.newly_terminated)

    def test_termination_pulses_only_on_crossing(self):
        result = blend_codes((0, 0, 0), 8, (4096, 4096, 4096), 2048)
        self.assertTrue(result.newly_terminated)
        again = blend_codes(result.rgb_q12, result.transmittance_q16, (4096, 4096, 4096), 2048)
        self.assertFalse(again.newly_terminated)


if __name__ == "__main__":
    unittest.main()
