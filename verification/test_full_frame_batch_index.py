from __future__ import annotations

import unittest

import numpy as np

from scripts.build_full_frame_batch_index import INDEX_DTYPE, pack_batches, pack_mean_records, round_shift_away_from_zero, rtl_depth_q16, validate_batches


class FullFrameBatchIndexTests(unittest.TestCase):
    def test_round_shift_matches_rtl_half_away_from_zero(self):
        values = np.asarray([0, 1 << 19, -(1 << 19), (3 << 19), -(3 << 19)], dtype=np.int64)
        np.testing.assert_array_equal(round_shift_away_from_zero(values, 20), [0, 1, -1, 2, -2])

    def test_identity_depth_and_translation(self):
        mean = np.asarray([[0.0, 0.0, 2.0], [0.0, 0.0, -2.0]], dtype=np.float32)
        depth, overflow = rtl_depth_q16(mean, np.asarray([0, 0, 1 << 20]), 3 << 16)
        np.testing.assert_array_equal(depth, [5 << 16, 1 << 16])
        self.assertFalse(bool(np.any(overflow)))

    def test_batches_respect_group_capacity_and_order(self):
        depths = np.asarray([1, 1, 2, 3, 3, 4, 5, 6, 6, 7], dtype=np.int32)
        batches = pack_batches(depths, capacity=3, groups=4)
        self.assertEqual(sum(batch["count"] for batch in batches), len(depths))
        self.assertLessEqual(max(max(batch["group_counts"]) for batch in batches), 3)
        for batch in batches:
            self.assertLessEqual(len(batch["group_counts"]), 4)
            self.assertEqual(sum(batch["group_counts"]), batch["count"])

    def test_oversized_equal_depth_run_is_split_only_at_batch_boundary(self):
        depths = np.asarray([9] * 8, dtype=np.int32)
        batches = pack_batches(depths, capacity=3, groups=4)
        self.assertEqual([batch["count"] for batch in batches], [3, 3, 2])
        self.assertTrue(all(len(batch["group_counts"]) == 1 for batch in batches))

    def test_mean_record_matches_rtl_bit_layout(self):
        gid = np.asarray([0x89ABCDEF], dtype=np.uint32)
        mean = np.asarray([[1.0, -2.0, 3.0]], dtype=np.float32)
        raw = int.from_bytes(pack_mean_records(gid, mean).tobytes(), "little")
        self.assertEqual(raw & 0xFFFFFFFF, 0x89ABCDEF)
        def signed(value, width):
            return value - (1 << width) if value & (1 << (width - 1)) else value
        self.assertEqual(signed((raw >> 32) & ((1 << 27) - 1), 27), 1 << 16)
        self.assertEqual(signed((raw >> 59) & ((1 << 27) - 1), 27), -(2 << 16))
        self.assertEqual(signed((raw >> 86) & ((1 << 27) - 1), 27), 3 << 16)

    def test_actual_pivots_replay_planned_group_counts(self):
        records = np.empty(7, dtype=INDEX_DTYPE)
        records["gid"] = np.arange(7, dtype=np.uint32)
        records["depth_q16"] = [1, 1, 2, 3, 4, 5, 6]
        batches = pack_batches(records["depth_q16"], capacity=2, groups=4)
        report = validate_batches(records, batches, capacity=2)
        self.assertTrue(all(report.values()))

    def test_validation_rejects_corrupt_batch_offset(self):
        records = np.empty(2, dtype=INDEX_DTYPE)
        records["gid"] = [0, 1]
        records["depth_q16"] = [1, 2]
        batches = pack_batches(records["depth_q16"], capacity=2, groups=4)
        batches[0]["offset_records"] = 1
        with self.assertRaises(ValueError):
            validate_batches(records, batches, capacity=2)


if __name__ == "__main__":
    unittest.main()
