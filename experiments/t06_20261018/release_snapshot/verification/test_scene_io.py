from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.io import (
    camera_from_json,
    iter_gaussian_batches,
    pack_attribute_record,
    pack_mean_record,
    parse_ply_header,
    scaled_camera,
)
from model.io.dma_workload import _sample_priority


class SceneIoTests(unittest.TestCase):
    def test_scene_wide_sample_priority_is_deterministic_and_index_sensitive(self):
        priorities = [_sample_priority(index) for index in range(32)]
        self.assertEqual(priorities, [_sample_priority(index) for index in range(32)])
        self.assertEqual(len(set(priorities)), 32)

    def test_dma_mean_and_attribute_bit_layout(self):
        mean = np.asarray((-1.0, 2.0, 3.0), dtype=np.float32)
        record = pack_mean_record(7, mean)
        self.assertEqual(record & 0xFFFFFFFF, 7)
        self.assertEqual((record >> 32) & ((1 << 27) - 1), (-65536) & ((1 << 27) - 1))
        self.assertEqual((record >> 59) & ((1 << 27) - 1), 2 * 65536)
        self.assertEqual((record >> 86) & ((1 << 27) - 1), 3 * 65536)

        sh = np.arange(48, dtype=np.float32).reshape(3, 16) / 4096.0
        attribute = pack_attribute_record(
            mean,
            np.asarray((1.0, 0.0, 0.0, 0.0), dtype=np.float32),
            np.asarray((1.0, 2.0, 3.0), dtype=np.float32),
            0.5,
            sh,
        )
        coeff_mask = (1 << (48 * 18)) - 1
        coefficients = attribute & coeff_mask
        for index in range(48):
            self.assertEqual((coefficients >> (index * 18)) & ((1 << 18) - 1), index)
        self.assertEqual((attribute >> (48 * 18)) & ((1 << 13) - 1), 2048)
        self.assertEqual(attribute.bit_length() <= 1118, True)
    def make_ply(self, path: Path):
        names = ["x", "y", "z", "opacity", "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3"]
        names += [f"f_dc_{i}" for i in range(3)] + [f"f_rest_{i}" for i in range(45)]
        dtype = np.dtype([(name, "<f4") for name in names])
        values = np.zeros(2, dtype=dtype)
        values["x"] = (1.0, 2.0)
        values["opacity"] = (0.0, np.log(3.0))
        values["scale_0"] = np.log((2.0, 3.0))
        values["scale_1"] = np.log((4.0, 5.0))
        values["scale_2"] = np.log((6.0, 7.0))
        values["rot_0"] = (2.0, 0.0)
        values["rot_1"] = (0.0, 3.0)
        for index in range(3):
            values[f"f_dc_{index}"] = index + 1
        for index in range(45):
            values[f"f_rest_{index}"] = index + 10
        header = "ply\nformat binary_little_endian 1.0\nelement vertex 2\n"
        header += "".join(f"property float {name}\n" for name in names)
        header += "end_header\n"
        path.write_bytes(header.encode("ascii") + values.tobytes())

    def test_binary_ply_transform_and_sh_layout(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.ply"
            self.make_ply(path)
            header = parse_ply_header(path)
            self.assertEqual(header.vertex_count, 2)
            batch = next(iter_gaussian_batches(path, include_sh=True))
            np.testing.assert_allclose(batch.opacity, (0.5, 0.75), rtol=1e-6)
            np.testing.assert_allclose(batch.scale, ((2, 4, 6), (3, 5, 7)), rtol=1e-6)
            np.testing.assert_allclose(np.linalg.norm(batch.quaternion, axis=1), 1.0, rtol=1e-6)
            self.assertEqual(batch.sh.shape, (2, 3, 16))
            np.testing.assert_allclose(batch.sh[0, :, 0], (1, 2, 3))
            np.testing.assert_allclose(batch.sh[0, :, 1], (10, 25, 40))
            np.testing.assert_allclose(batch.sh[0, :, 15], (24, 39, 54))
            np.testing.assert_allclose(batch.sh[0, 0, 1:], np.arange(10,25))
            from scripts.build_full_frame_rtl_batch import load_selected_gaussians
            sparse = load_selected_gaussians(path, np.asarray([0,1],dtype=np.uint32))
            np.testing.assert_array_equal(sparse['sh'], batch.sh)

    def test_camera_position_maps_to_origin(self):
        record = {
            "width": 640,
            "height": 480,
            "fx": 500.0,
            "fy": 510.0,
            "position": [1.0, 2.0, 3.0],
            "rotation": [[0.0, -1.0, 0.0], [1.0, 0.0, 0.0], [0.0, 0.0, 1.0]],
        }
        camera = camera_from_json(record)
        homogeneous = np.asarray((1.0, 2.0, 3.0, 1.0), dtype=np.float32)
        np.testing.assert_allclose(camera.world_to_camera @ homogeneous, (0, 0, 0, 1), atol=1e-6)

    def test_rejects_ascii_ply(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ascii.ply"
            path.write_text("ply\nformat ascii 1.0\nelement vertex 0\nend_header\n", encoding="ascii")
            with self.assertRaises(ValueError):
                parse_ply_header(path)

    def test_scaled_camera_preserves_aspect_and_fov(self):
        camera = camera_from_json({
            "width": 4000, "height": 3000, "fx": 3200.0, "fy": 3300.0,
            "position": [0, 0, 0], "rotation": [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
        })
        scaled = scaled_camera(camera, 1920)
        self.assertEqual((scaled.width, scaled.height), (1920, 1440))
        self.assertAlmostEqual(scaled.fx / scaled.width, camera.fx / camera.width)
        self.assertAlmostEqual(scaled.fy / scaled.height, camera.fy / camera.height)


if __name__ == "__main__":
    unittest.main(verbosity=2)
