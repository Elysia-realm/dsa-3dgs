from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.decode_rtl_frame import decode_state


class RtlFrameDecodeTests(unittest.TestCase):
    def test_q12_rgb_and_transmittance_layout(self):
        word = 4096 | (2048 << 13) | (1024 << 26) | (32768 << 39)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.memh"
            path.write_text(f"{word:032x}\n", encoding="ascii")
            rgb, transmittance = decode_state(path, 1, 1)
        self.assertEqual(rgb[0, 0].tolist(), [255, 128, 64])
        self.assertEqual(int(transmittance[0, 0]), 32768)


if __name__ == "__main__":
    unittest.main()
