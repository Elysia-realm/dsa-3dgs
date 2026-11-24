from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.reference import Camera, Gaussian3D, RenderConfig, render_gaussianwise, render_pixelwise


def camera(width=32, height=24):
    return Camera(width, height, fx=24.0, fy=24.0, cx=(width - 1) / 2, cy=(height - 1) / 2)


def gaussian(gid, mean, opacity=0.7, rgb=(1.0, 0.0, 0.0), scale=(0.20, 0.20, 0.20), quat=(1, 0, 0, 0)):
    return Gaussian3D(
        gid=gid,
        mean=np.asarray(mean, dtype=np.float32),
        scale=np.asarray(scale, dtype=np.float32),
        quaternion=np.asarray(quat, dtype=np.float32),
        opacity=opacity,
        rgb=np.asarray(rgb, dtype=np.float32),
    )


class ReferenceModelTests(unittest.TestCase):
    def compare_modes(self, gaussians, config=RenderConfig(block_size=4, group_size=2)):
        pixel = render_pixelwise(gaussians, camera(), config)
        gaussian_mode = render_gaussianwise(gaussians, camera(), config)
        np.testing.assert_allclose(gaussian_mode.rgb, pixel.rgb, rtol=1e-6, atol=1e-6)
        np.testing.assert_allclose(gaussian_mode.transmittance, pixel.transmittance, rtol=1e-6, atol=1e-6)
        np.testing.assert_array_equal(gaussian_mode.terminated, pixel.terminated)
        self.assertEqual(gaussian_mode.sorted_ids, pixel.sorted_ids)
        self.assertEqual(gaussian_mode.contributing_ids, pixel.contributing_ids)
        return gaussian_mode

    def test_single_gaussian(self):
        result = self.compare_modes([gaussian(1, (0, 0, 3))])
        center = result.rgb[12, 16]
        self.assertGreater(float(center[0]), 0.5)
        self.assertEqual(float(center[1]), 0.0)

    def test_front_to_back_order(self):
        back = gaussian(2, (0, 0, 4), opacity=0.8, rgb=(0, 0, 1))
        front = gaussian(1, (0, 0, 2), opacity=0.8, rgb=(1, 0, 0))
        result = self.compare_modes([back, front])
        self.assertEqual(result.sorted_ids, [1, 2])
        center = result.rgb[12, 16]
        self.assertGreater(float(center[0]), float(center[2]))

    def test_stable_equal_depth_uses_gid(self):
        a = gaussian(9, (-0.05, 0, 3), rgb=(0, 1, 0))
        b = gaussian(3, (0.05, 0, 3), rgb=(1, 0, 0))
        result = self.compare_modes([a, b])
        self.assertEqual(result.sorted_ids, [3, 9])

    def test_outside_and_behind_are_culled(self):
        items = [
            gaussian(1, (0, 0, -2)),
            gaussian(2, (100, 0, 3)),
            gaussian(3, (0, 0, 3), rgb=(0, 1, 0)),
        ]
        result = self.compare_modes(items)
        self.assertEqual(result.sorted_ids, [3])
        self.assertEqual(result.stats.screen_culled_gaussians, 2)

    def test_low_opacity_is_pruned(self):
        config = RenderConfig(alpha_threshold=1 / 255, block_size=4)
        result = self.compare_modes([gaussian(1, (0, 0, 3), opacity=1e-4)], config)
        self.assertEqual(result.sorted_ids, [])
        self.assertTrue(np.all(result.rgb == 0))

    def test_per_pixel_early_termination(self):
        items = [gaussian(i, (0, 0, 2 + i * 0.05), opacity=0.99, rgb=(1, 1, 1)) for i in range(12)]
        result = self.compare_modes(items, RenderConfig(block_size=4, group_size=3, transmittance_threshold=1e-4))
        self.assertGreater(result.stats.terminated_pixels, 0)
        self.assertGreater(result.stats.skipped_terminated_pixels, 0)

    def test_anisotropic_rotated_gaussian(self):
        angle = np.deg2rad(45.0) / 2.0
        q = (np.cos(angle), 0, 0, np.sin(angle))
        item = gaussian(1, (0, 0, 3), scale=(0.45, 0.06, 0.06), quat=q)
        result = self.compare_modes([item])
        mask = result.rgb[..., 0] > 0.02
        ys, xs = np.nonzero(mask)
        self.assertGreater(np.ptp(xs), 2)
        self.assertGreater(np.ptp(ys), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
