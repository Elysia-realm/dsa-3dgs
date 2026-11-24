from __future__ import annotations

import random
import sys
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.cycle import (
    B0Config,
    BlockTask,
    DepthRecord,
    ScoreboardConfig,
    hierarchical_depth_groups,
    simulate_b0,
    simulate_scoreboard,
    R0Config,
    R0Mode,
    build_cycle_workload,
    simulate_r0,
    R1Config,
    R1Mode,
    R1ResourceCosts,
    simulate_r1,
)
from model.reference import Camera, Gaussian3D, RenderConfig
from model.reference.math3d import project_gaussian


def make_camera(width=32, height=24):
    return Camera(width, height, fx=24.0, fy=24.0, cx=(width - 1) / 2, cy=(height - 1) / 2)


def make_gaussian(gid, mean, scale=(0.2, 0.2, 0.2), opacity=0.7):
    return Gaussian3D(
        gid=gid,
        mean=np.asarray(mean, dtype=np.float32),
        scale=np.asarray(scale, dtype=np.float32),
        quaternion=np.asarray((1, 0, 0, 0), dtype=np.float32),
        opacity=opacity,
        rgb=np.asarray((0.4, 0.6, 0.2), dtype=np.float32),
    )


class GroupingTests(unittest.TestCase):
    def assert_valid(self, records, capacity, pivots=7):
        groups, report = hierarchical_depth_groups(records, capacity, pivots)
        self.assertEqual(sum(len(group) for group in groups), len(records))
        self.assertLessEqual(max(map(len, groups), default=0), capacity)
        flattened = [record for group in groups for record in sorted(group, key=lambda item: item.key)]
        self.assertEqual([item.key for item in flattened], sorted(item.key for item in records))
        for left, right in zip(groups, groups[1:]):
            self.assertLessEqual(max(item.key for item in left), min(item.key for item in right))
        return groups, report

    def test_random_grouping_preserves_global_order(self):
        rng = random.Random(7)
        records = [DepthRecord(rng.uniform(0.2, 20.0), gid, gid) for gid in range(1003)]
        groups, report = self.assert_valid(records, 64)
        self.assertGreater(len(groups), 1)
        self.assertGreater(report.comparator_evaluations, 0)

    def test_equal_depth_uses_gid_and_converges(self):
        records = [DepthRecord(3.0, gid, gid) for gid in reversed(range(513))]
        groups, _ = self.assert_valid(records, 32)
        ids = [item.gid for group in groups for item in sorted(group, key=lambda item: item.key)]
        self.assertEqual(ids, list(range(513)))

    def test_monotonic_adversarial_arrival(self):
        records = [DepthRecord(float(gid), gid, gid) for gid in range(777)]
        self.assert_valid(records, 48, pivots=3)

    def test_randomized_properties(self):
        rng = random.Random(13)
        for _ in range(25):
            count = rng.randint(0, 400)
            capacity = rng.randint(4, 64)
            records = [DepthRecord(round(rng.uniform(0.2, 8.0), 2), gid, None) for gid in range(count)]
            rng.shuffle(records)
            self.assert_valid(records, capacity, pivots=rng.randint(1, 9))


class ScoreboardTests(unittest.TestCase):
    def test_overlapping_blocks_create_dependency_stall(self):
        tasks = []
        task_id = 0
        predecessor = {}
        for order in range(10):
            for block in range(2):
                tasks.append(BlockTask(task_id, order, order, block, 0, 64, predecessor.get(block)))
                predecessor[block] = task_id
                task_id += 1
        config = ScoreboardConfig(alpha_arrays=4, blend_arrays=2, alpha_latency=2, blend_latency=6, result_queue_depth=8)
        ordered = simulate_scoreboard(tasks, config, enforce_dependencies=True)
        ideal = simulate_scoreboard(tasks, config, enforce_dependencies=False)
        self.assertEqual(len(ordered.completion_cycles), len(tasks))
        self.assertGreater(ordered.scoreboard_stall_cycles, 0)
        self.assertGreater(ordered.end_cycle, ideal.end_cycle)

    def test_disjoint_blocks_have_no_scoreboard_stall(self):
        tasks = [BlockTask(i, i, i, i, 0, 64, None) for i in range(20)]
        report = simulate_scoreboard(
            tasks, ScoreboardConfig(alpha_arrays=2, blend_arrays=2, alpha_latency=3, blend_latency=3, result_queue_depth=16)
        )
        self.assertEqual(report.scoreboard_stall_cycles, 0)
        self.assertEqual(len(report.completion_cycles), len(tasks))

    def test_small_queue_applies_backpressure(self):
        tasks = [BlockTask(i, i, i, i, 0, 64, None) for i in range(30)]
        report = simulate_scoreboard(
            tasks, ScoreboardConfig(alpha_arrays=4, blend_arrays=1, alpha_latency=2, blend_latency=8, result_queue_depth=3)
        )
        self.assertGreater(report.result_queue_stall_cycles, 0)
        self.assertLessEqual(report.max_result_queue, 3)

    def test_queue_depth_sensitivity(self):
        tasks = [BlockTask(i, i, i, i, 0, 64, None) for i in range(48)]
        base = dict(alpha_arrays=4, blend_arrays=1, alpha_latency=3, blend_latency=8)
        shallow = simulate_scoreboard(tasks, ScoreboardConfig(result_queue_depth=3, **base))
        deep = simulate_scoreboard(tasks, ScoreboardConfig(result_queue_depth=32, **base))
        self.assertGreater(shallow.result_queue_stall_cycles, deep.result_queue_stall_cycles)
        self.assertGreaterEqual(shallow.end_cycle, deep.end_cycle)


class B0Tests(unittest.TestCase):
    def test_b0_is_deterministic_and_reports_traffic(self):
        items = []
        for gid in range(40):
            x = ((gid % 5) - 2) * 0.08
            y = (((gid // 5) % 4) - 1.5) * 0.08
            z = 2.0 + gid * 0.04
            items.append(make_gaussian(gid, (x, y, z), scale=(0.25, 0.16, 0.12), opacity=0.75))
        render_config = RenderConfig(block_size=4, group_size=8)
        architecture = B0Config(
            frequency_hz=500e6,
            scoreboard=ScoreboardConfig(alpha_arrays=2, blend_arrays=1, alpha_latency=5, blend_latency=6, result_queue_depth=8),
        )
        first = simulate_b0(items, make_camera(), render_config, architecture)
        second = simulate_b0(items, make_camera(), render_config, architecture)
        self.assertEqual(first.total_cycles, second.total_cycles)
        self.assertEqual(first.sorted_ids, list(range(40)))
        self.assertEqual(first.sorted_ids, second.sorted_ids)
        self.assertEqual(first.projected_gaussians, 40)
        self.assertGreater(first.block_tasks, first.projected_gaussians)
        self.assertEqual(first.block_tasks, first.raster_trace.issued_blocks)
        self.assertLessEqual(first.raster_trace.issued_blocks, first.raster_trace.candidate_blocks)
        self.assertGreater(first.traffic.dram_read_bytes, 0)
        self.assertGreater(first.traffic.sram_read_bytes, 0)
        self.assertGreater(first.fps, 0)

    def test_b0_culls_geometry_before_loading_sh(self):
        items = [make_gaussian(0, (0, 0, -1)), make_gaussian(1, (100, 0, 3)), make_gaussian(2, (0, 0, 3))]
        report = simulate_b0(items, make_camera(), RenderConfig(block_size=4, group_size=2))
        self.assertEqual(report.depth_visible_gaussians, 2)
        self.assertEqual(report.projected_gaussians, 1)
        self.assertEqual(report.traffic.sh_attribute_bytes, 48 * 2)
        self.assertEqual(report.sorted_ids, [2])

    def test_b0_task_order_matches_projected_golden_order(self):
        depths = (4.0, 1.5, 2.8, 1.5, 6.0, 3.2, 2.1)
        items = [make_gaussian(gid, (0.02 * gid, 0.0, depth)) for gid, depth in enumerate(depths)]
        camera = make_camera()
        render = RenderConfig(block_size=4, group_size=3)
        report = simulate_b0(items, camera, render)
        projected = [project_gaussian(item, camera, render) for item in items]
        golden = [item.source.gid for item in sorted((p for p in projected if p is not None), key=lambda p: (p.depth, p.source.gid))]
        self.assertEqual(report.sorted_ids, golden)

    def test_early_termination_reduces_issued_tasks(self):
        items = [make_gaussian(gid, (0.0, 0.0, 1.5 + gid * 0.01), scale=(0.55, 0.55, 0.2), opacity=1.0) for gid in range(80)]
        camera = make_camera(24, 24)
        architecture = B0Config(scoreboard=ScoreboardConfig(alpha_arrays=2, blend_arrays=2, result_queue_depth=16))
        enabled = simulate_b0(
            items,
            camera,
            RenderConfig(block_size=4, group_size=16, transmittance_threshold=1.0e-4),
            architecture,
        )
        disabled = simulate_b0(
            items,
            camera,
            RenderConfig(block_size=4, group_size=16, transmittance_threshold=1.0e-30),
            architecture,
        )
        self.assertGreater(enabled.raster_trace.skipped_terminated_blocks, 0)
        self.assertLess(enabled.block_tasks, disabled.block_tasks)

    def test_sparse_workload_has_negligible_scoreboard_cost(self):
        positions = ((-0.75, -0.55), (0.75, -0.55), (-0.75, 0.55), (0.75, 0.55))
        items = [
            make_gaussian(gid, (x, y, 2.0 + gid * 0.2), scale=(0.04, 0.04, 0.04), opacity=0.5)
            for gid, (x, y) in enumerate(positions)
        ]
        report = simulate_b0(
            items,
            make_camera(64, 48),
            RenderConfig(block_size=4, group_size=4),
            B0Config(scoreboard=ScoreboardConfig(alpha_arrays=4, blend_arrays=2, result_queue_depth=16)),
        )
        self.assertEqual(report.raster.scoreboard_stall_cycles, 0)
        self.assertEqual(report.scoreboard_overhead_cycles, 0)

    def test_dense_overlap_has_dependency_stalls(self):
        items = [make_gaussian(gid, (0.0, 0.0, 2.0 + gid * 0.02), scale=(0.12, 0.12, 0.08), opacity=0.35) for gid in range(36)]
        report = simulate_b0(
            items,
            make_camera(8, 8),
            RenderConfig(block_size=8, group_size=12, transmittance_threshold=1.0e-20),
            B0Config(scoreboard=ScoreboardConfig(alpha_arrays=4, blend_arrays=4, alpha_latency=2, blend_latency=8, result_queue_depth=16)),
        )
        self.assertGreater(report.raster.scoreboard_stall_cycles, 0)
        self.assertGreater(report.scoreboard_overhead_cycles, 0)


class R0Tests(unittest.TestCase):
    def workload(self):
        items = []
        for gid in range(48):
            x = ((gid % 4) - 1.5) * 0.05
            y = (((gid // 4) % 3) - 1.0) * 0.05
            items.append(make_gaussian(gid, (x, y, 1.7 + gid * 0.025), scale=(0.22, 0.18, 0.1), opacity=0.45))
        return items, make_camera(40, 32), RenderConfig(block_size=4, group_size=8, transmittance_threshold=1.0e-20)

    def test_r0_preserves_shared_workload_semantics(self):
        items, camera, render = self.workload()
        config = R0Config()
        graph = build_cycle_workload(items, camera, render, minimum_group_size=config.minimum_epoch_gaussians)
        report = simulate_r0(items, camera, render, config)
        self.assertEqual(report.sorted_ids, graph.sorted_ids)
        self.assertEqual(report.block_tasks, graph.block_tasks)
        self.assertEqual(report.block_pixels, graph.block_pixels)
        self.assertEqual(report.candidate_blocks, graph.candidate_blocks)
        self.assertEqual(report.skipped_terminated_blocks, graph.skipped_terminated_blocks)

    def test_all_modes_obey_equal_elastic_lane_budget(self):
        config = R0Config()
        self.assertTrue(all(mode.total_lanes == config.total_elastic_lanes for mode in config.modes))
        with self.assertRaises(ValueError):
            R0Config(modes=(R0Mode("bad", 2, 2, 2),))

    def test_zero_switch_cost_dynamic_is_no_worse_than_fixed_modes(self):
        items, camera, render = self.workload()
        dynamic = simulate_r0(items, camera, render, R0Config(policy="dynamic", reconfiguration_cycles=0))
        fixed = [
            simulate_r0(items, camera, render, R0Config(policy="fixed", fixed_mode=mode.name)).total_cycles
            for mode in R0Config().modes
        ]
        self.assertLessEqual(dynamic.total_cycles, min(fixed))

    def test_switch_cycles_are_charged_exactly(self):
        items, camera, render = self.workload()
        modes = (
            R0Mode("p", 6, 1, 1),
            R0Mode("a", 1, 1, 6),
        )
        report = simulate_r0(
            items,
            camera,
            render,
            R0Config(modes=modes, fixed_mode="p", policy="dynamic", reconfiguration_cycles=7),
        )
        self.assertEqual(report.reconfiguration_cycles, report.reconfigurations * 7)
        for left, right in zip(report.groups, report.groups[1:]):
            expected = 7 if left.mode != right.mode else 0
            self.assertEqual(right.reconfiguration_cycles, expected)

    def test_same_mode_groups_share_one_pipelined_epoch(self):
        items, camera, render = self.workload()
        report = simulate_r0(
            items,
            camera,
            render,
            R0Config(policy="fixed", fixed_mode="balanced", minimum_epoch_gaussians=1),
        )
        self.assertEqual(len(report.groups), 1)
        self.assertEqual(report.groups[0].group_index, 0)
        self.assertGreater(report.groups[0].group_end_index, 1)

    def test_high_switch_cost_cannot_improve_over_zero_cost(self):
        items, camera, render = self.workload()
        free = simulate_r0(items, camera, render, R0Config(policy="dynamic", reconfiguration_cycles=0))
        costly = simulate_r0(items, camera, render, R0Config(policy="dynamic", reconfiguration_cycles=50))
        self.assertGreaterEqual(costly.total_cycles, free.total_cycles)

    def test_fixed_mode_has_no_reconfiguration(self):
        items, camera, render = self.workload()
        report = simulate_r0(items, camera, render, R0Config(policy="fixed", fixed_mode="raster_priority"))
        self.assertEqual(report.reconfigurations, 0)
        self.assertEqual(report.reconfiguration_cycles, 0)
        self.assertEqual(set(report.selected_modes), {"raster_priority"})


class R1Tests(unittest.TestCase):
    def workload(self):
        items = [
            make_gaussian(
                gid,
                (((gid % 4) - 1.5) * 0.04, (((gid // 4) % 3) - 1.0) * 0.04, 1.8 + gid * 0.02),
                scale=(0.24, 0.20, 0.10),
                opacity=0.4,
            )
            for gid in range(48)
        ]
        return items, make_camera(40, 32), RenderConfig(block_size=4, group_size=8, transmittance_threshold=1.0e-20)

    def heterogeneous_workload(self):
        items = []
        for gid in range(128):
            items.append(make_gaussian(gid, (20.0, 0.0, 1.5 + gid * 0.005), scale=(0.1, 0.1, 0.1), opacity=0.4))
        for index in range(32):
            gid = 128 + index
            items.append(make_gaussian(gid, (0.0, 0.0, 3.0 + index * 0.012), scale=(0.35, 0.35, 0.15), opacity=0.25))
        return items, Camera(96, 96, 72.0, 72.0, 47.5, 47.5), RenderConfig(
            block_size=8, group_size=16, transmittance_threshold=1.0e-20
        )

    def test_all_modes_use_equal_area_credit_budget(self):
        config = R1Config()
        self.assertTrue(
            all(mode.area_credits(config.resource_costs) == config.area_budget_credits for mode in config.modes)
        )
        with self.assertRaises(ValueError):
            R1Config(modes=(R1Mode("bad", 1, 1, 1),))

    def test_resource_costs_must_be_positive(self):
        with self.assertRaises(ValueError):
            R1ResourceCosts(projection=0)

    def test_r1_preserves_shared_workload_semantics(self):
        items, camera, render = self.workload()
        config = R1Config(minimum_epoch_gaussians=16)
        graph = build_cycle_workload(items, camera, render, minimum_group_size=config.minimum_epoch_gaussians)
        report = simulate_r1(items, camera, render, config)
        self.assertEqual(report.sorted_ids, graph.sorted_ids)
        self.assertEqual(report.block_tasks, graph.block_tasks)
        self.assertEqual(report.block_pixels, graph.block_pixels)
        self.assertEqual(report.candidate_blocks, graph.candidate_blocks)
        self.assertEqual(report.skipped_terminated_blocks, graph.skipped_terminated_blocks)

    def test_zero_cost_dynamic_is_no_worse_than_fixed_modes(self):
        items, camera, render = self.workload()
        dynamic = simulate_r1(items, camera, render, R1Config(policy="dynamic", reconfiguration_cycles=0))
        fixed = [
            simulate_r1(items, camera, render, R1Config(policy="fixed", fixed_mode=mode.name)).total_cycles
            for mode in R1Config().modes
        ]
        self.assertLessEqual(dynamic.total_cycles, min(fixed))

    def test_heterogeneous_workload_triggers_useful_switch(self):
        items, camera, render = self.heterogeneous_workload()
        dynamic = simulate_r1(
            items, camera, render, R1Config(policy="dynamic", reconfiguration_cycles=12, minimum_epoch_gaussians=16)
        )
        fixed = [
            simulate_r1(
                items, camera, render, R1Config(policy="fixed", fixed_mode=mode.name, minimum_epoch_gaussians=16)
            ).total_cycles
            for mode in R1Config().modes
        ]
        self.assertEqual(dynamic.selected_modes, ["projection_priority", "raster_priority"])
        self.assertEqual(dynamic.reconfigurations, 1)
        self.assertEqual(dynamic.reconfiguration_cycles, 12)
        self.assertLess(dynamic.total_cycles, min(fixed))

    def test_high_switch_cost_suppresses_heterogeneous_switch(self):
        items, camera, render = self.heterogeneous_workload()
        report = simulate_r1(
            items, camera, render, R1Config(policy="dynamic", reconfiguration_cycles=48, minimum_epoch_gaussians=16)
        )
        self.assertEqual(report.reconfigurations, 0)
        self.assertEqual(report.selected_modes, ["raster_priority"])

    def test_paired_raster_lanes_help_dense_overlap(self):
        items = [
            make_gaussian(gid, (0.0, 0.0, 2.0 + gid * 0.015), scale=(0.34, 0.34, 0.12), opacity=0.3)
            for gid in range(48)
        ]
        camera = make_camera(32, 32)
        render = RenderConfig(block_size=4, group_size=12, transmittance_threshold=1.0e-20)
        raster = simulate_r1(items, camera, render, R1Config(policy="fixed", fixed_mode="raster_priority"))
        projection = simulate_r1(items, camera, render, R1Config(policy="fixed", fixed_mode="projection_priority"))
        self.assertLess(raster.total_cycles, projection.total_cycles)


if __name__ == "__main__":
    unittest.main(verbosity=2)
