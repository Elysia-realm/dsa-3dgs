from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

from scripts.build_full_frame_batch_index import INDEX_DTYPE
from scripts.build_full_frame_rtl_batch import load_index_records


class FullFrameRtlBatchTests(unittest.TestCase):
    def test_index_slice_preserves_global_gid_and_depth(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "index.bin"
            records = np.empty(4, dtype=INDEX_DTYPE)
            records["gid"] = [1_000_001, 7, 99_000, 42]
            records["depth_q16"] = [10, 11, 12, 13]
            path.write_bytes(records.tobytes())
            selected = load_index_records(path, 1, 2)
            np.testing.assert_array_equal(selected["gid"], [7, 99_000])
            np.testing.assert_array_equal(selected["depth_q16"], [11, 12])

    def test_index_slice_rejects_out_of_range(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "index.bin"
            records = np.empty(1, dtype=INDEX_DTYPE)
            path.write_bytes(records.tobytes())
            with self.assertRaises(ValueError):
                load_index_records(path, 1, 1)


if __name__ == "__main__":
    unittest.main()
