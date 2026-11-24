from __future__ import annotations

import unittest

from scripts.plan_full_frame_execution import capacity_plan, required_bits


class FullFrameExecutionPlanTests(unittest.TestCase):
    def test_required_bits_covers_zero_and_boundaries(self):
        self.assertEqual(required_bits(0), 1)
        self.assertEqual(required_bits(7), 3)
        self.assertEqual(required_bits(8), 4)

    def test_capacity_plan_uses_ceiling_without_empty_extra_batch(self):
        exact = capacity_plan(32, 8, 4)
        self.assertEqual(exact.conservative_batch_count, 4)
        self.assertEqual(exact.optimistic_batch_count, 1)
        partial = capacity_plan(33, 8, 4)
        self.assertEqual(partial.conservative_batch_count, 5)
        self.assertEqual(partial.optimistic_batch_count, 2)

    def test_empty_scene_requires_no_batch(self):
        plan = capacity_plan(0, 256, 4)
        self.assertEqual(plan.conservative_batch_count, 0)
        self.assertEqual(plan.optimistic_batch_count, 0)

    def test_invalid_capacity_is_rejected(self):
        with self.assertRaises(ValueError):
            capacity_plan(1, 0)


if __name__ == "__main__":
    unittest.main()
