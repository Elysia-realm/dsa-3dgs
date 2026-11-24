from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.read_rgb888_frame import aligned_row_stride, decode_rgb888


class T04RgbFrameTests(unittest.TestCase):
    def test_stride_and_rgb_byte_order(self):
        self.assertEqual(aligned_row_stride(1), 16)
        self.assertEqual(aligned_row_stride(83), 256)
        raw = bytes([1, 2, 3, 4, 5, 6] + [0] * 10)
        frame = decode_rgb888(raw, 2, 1)
        self.assertEqual(frame.tolist(), [[[1, 2, 3], [4, 5, 6]]])

    def test_multiple_rows_skip_padding(self):
        raw = bytes([10, 20, 30] + [0] * 13 + [40, 50, 60] + [0] * 13)
        frame = decode_rgb888(raw, 1, 2)
        self.assertEqual(frame[:, 0].tolist(), [[10, 20, 30], [40, 50, 60]])

    def test_rejects_truncated_or_invalid_stride(self):
        with self.assertRaises(ValueError):
            decode_rgb888(bytes(15), 1, 1)
        with self.assertRaises(ValueError):
            decode_rgb888(bytes(16), 2, 1, 4)


if __name__ == "__main__":
    unittest.main()
