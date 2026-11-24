from __future__ import annotations

from dataclasses import dataclass, field
from math import ceil, log2
from typing import Iterable

import numpy as np

from model.reference.math3d import ProjectedGaussian, alpha_at, project_gaussian
from model.reference.model import Camera, Gaussian3D, RenderConfig

from .grouping import DepthRecord, GroupingReport, hierarchical_depth_groups
from .scoreboard import BlockTask, ScoreboardConfig, ScoreboardReport, simulate_scoreboard


@dataclass(frozen=True)
class B0Config:
    frequency_hz: float = 1.0e9
    depth_throughput: int = 4
    depth_latency: int = 8
    grouping_comparators: int = 28
    grouping_control_cycles: int = 2
    grouping_pivots: int = 7
    projection_throughput: int = 1
    projection_latency: int = 40
    sort_comparators: int = 16
    sort_latency: int = 6
    sh_throughput: int = 1
    sh_latency: int = 16
    scoreboard: ScoreboardConfig = field(default_factory=ScoreboardConfig)
    fp_bytes: int = 2
    id_bytes: int = 4
    model_sh_coefficients: int = 48

    def __post_init__(self):
        positive = (
            "frequency_hz",
            "depth_throughput",
            "depth_latency",
            "grouping_comparators",
            "grouping_control_cycles",
            "grouping_pivots",
            "projection_throughput",
            "projection_latency",
            "sort_comparators",
            "sort_latency",
            "sh_throughput",
            "sh_latency",
            "fp_bytes",
            "id_bytes",
            "model_sh_coefficients",
        )
        for name in positive:
            if getattr(self, name) <= 0:
                raise ValueError(f"{name} must be positive")


@dataclass
class StageReport:
    start_cycle: int = 0
    end_cycle: int = 0
    busy_cycles: int = 0
    operations: int = 0


@dataclass
class TrafficReport:
    dram_read_bytes: int = 0
    dram_write_bytes: int = 0
    sram_read_bytes: int = 0
    sram_write_bytes: int = 0
    depth_attribute_bytes: int = 0
    geometry_attribute_bytes: int = 0
    sh_attribute_bytes: int = 0
    output_bytes: int = 0
    image_state_bytes: int = 0
    sort_record_bytes: int = 0


@dataclass
class RasterTraceReport:
    candidate_blocks: int = 0
    issued_blocks: int = 0
    skipped_terminated_blocks: int = 0
    active_pixel_tests: int = 0
    alpha_pruned_pixels: int = 0
    blend_updates: int = 0
    terminated_pixels: int = 0


@dataclass
class B0Report:
    total_cycles: int
    seconds_per_frame: float
    fps: float
    input_gaussians: int
    depth_visible_gaussians: int
    projected_gaussians: int
    screen_culled_gaussians: int
    sorted_ids: list[int]
    group_sizes_before_projection: list[int]
    group_sizes_after_projection: list[int]
    grouping: GroupingReport
    depth_stage: StageReport
    projection_stage: StageReport
    sort_stage: StageReport
    sh_stage: StageReport
    raster: ScoreboardReport
    raster_ideal: ScoreboardReport
    raster_trace: RasterTraceReport
    traffic: TrafficReport
    block_tasks: int
    block_pixels: int
    scoreboard_overhead_cycles: int


def _depth_record(gaussian: Gaussian3D, camera: Camera, config: RenderConfig) -> DepthRecord[Gaussian3D] | None:
    homogeneous = np.append(gaussian.mean, np.float32(1.0)).astype(np.float32)
    depth = float((camera.world_to_camera @ homogeneous)[2])
    if not config.near <= depth <= config.far:
        return None
    return DepthRecord(depth=depth, gid=gaussian.gid, payload=gaussian)


def _sort_comparisons(size: int) -> int:
    if size <= 1:
        return 0
    stages = ceil(log2(size))
    # Comparator count for a padded bitonic sorting network.
    padded = 1 << stages
    return padded * stages * (stages + 1) // 4


def _trace_gaussian_blocks(
    projected: ProjectedGaussian,
    camera: Camera,
    render_config: RenderConfig,
    transmittance: np.ndarray,
    terminated: np.ndarray,
    trace: RasterTraceReport,
):
    """Run exact alpha/T semantics to remove work already terminated in front."""
    x0, y0, x1, y1 = projected.bbox
    block = render_config.block_size
    blocks_per_row = ceil(camera.width / block)
    for by in range(y0 // block, (y1 - 1) // block + 1):
        py0, py1 = max(y0, by * block), min(y1, (by + 1) * block)
        for bx in range(x0 // block, (x1 - 1) // block + 1):
            trace.candidate_blocks += 1
            px0, px1 = max(x0, bx * block), min(x1, (bx + 1) * block)
            active = ~terminated[py0:py1, px0:px1]
            active_count = int(np.count_nonzero(active))
            if active_count == 0:
                trace.skipped_terminated_blocks += 1
                continue
            trace.issued_blocks += 1
            trace.active_pixel_tests += active_count
            for y in range(py0, py1):
                for x in range(px0, px1):
                    if terminated[y, x]:
                        continue
                    alpha = alpha_at(projected, x, y, render_config)
                    if alpha < render_config.alpha_threshold:
                        trace.alpha_pruned_pixels += 1
                        continue
                    transmittance[y, x] *= np.float32(1.0 - alpha)
                    trace.blend_updates += 1
                    if transmittance[y, x] < render_config.transmittance_threshold:
                        terminated[y, x] = True
                        trace.terminated_pixels += 1
            yield by * blocks_per_row + bx, active_count


def simulate_b0(
    gaussians: Iterable[Gaussian3D], camera: Camera, render_config: RenderConfig = RenderConfig(), config: B0Config = B0Config()
) -> B0Report:
    """Simulate the fixed-function B0 pipeline with group overlap and scoreboard."""
    source = list(gaussians)
    depth_records = [record for gaussian in source if (record := _depth_record(gaussian, camera, render_config))]
    groups, grouping = hierarchical_depth_groups(
        depth_records, max_group_size=render_config.group_size, pivot_count=config.grouping_pivots
    )

    depth_busy = ceil(len(source) / config.depth_throughput) if source else 0
    depth_end = config.depth_latency + depth_busy
    grouping_cycles = (
        ceil((grouping.comparator_evaluations + grouping.pivot_sort_comparisons) / config.grouping_comparators)
        + grouping.partition_rounds * config.grouping_control_cycles
    )
    global_ready = depth_end + grouping_cycles
    depth_stage = StageReport(0, depth_end, depth_busy, len(source))

    projection_available = global_ready
    sorter_available = global_ready
    sh_available = global_ready
    projected_flat: list[ProjectedGaussian] = []
    group_sizes_after: list[int] = []
    tasks: list[BlockTask] = []
    previous_by_block: dict[int, int] = {}
    task_id = 0
    gaussian_order = 0
    raster_trace = RasterTraceReport()
    transmittance = np.ones((camera.height, camera.width), dtype=np.float32)
    terminated = np.zeros((camera.height, camera.width), dtype=np.bool_)
    projection_busy_total = 0
    sort_busy_total = 0
    sh_busy_total = 0
    projection_first = None
    projection_last = global_ready
    sort_first = None
    sort_last = global_ready
    sh_first = None
    sh_last = global_ready

    for group in groups:
        projection_start = projection_available
        projection_busy = ceil(len(group) / config.projection_throughput)
        projection_end = projection_start + config.projection_latency + projection_busy
        projection_available = projection_start + projection_busy
        projection_busy_total += projection_busy
        projection_first = projection_start if projection_first is None else min(projection_first, projection_start)
        projection_last = max(projection_last, projection_end)

        projected_group = [
            item for record in group if (item := project_gaussian(record.payload, camera, render_config)) is not None
        ]
        projected_group.sort(key=lambda item: (item.depth, item.source.gid))
        projected_flat.extend(projected_group)
        group_sizes_after.append(len(projected_group))

        sort_start = max(projection_end, sorter_available)
        comparisons = _sort_comparisons(len(projected_group))
        sort_busy = ceil(comparisons / config.sort_comparators) if comparisons else 0
        sort_end = sort_start + (config.sort_latency if projected_group else 0) + sort_busy
        sorter_available = sort_start + sort_busy
        sort_busy_total += sort_busy
        sort_first = sort_start if sort_first is None else min(sort_first, sort_start)
        sort_last = max(sort_last, sort_end)

        sh_start = max(sort_end, sh_available)
        for index, projected in enumerate(projected_group):
            sh_ready = sh_start + config.sh_latency + ceil((index + 1) / config.sh_throughput)
            for block_id, pixel_count in _trace_gaussian_blocks(
                projected, camera, render_config, transmittance, terminated, raster_trace
            ):
                predecessor = previous_by_block.get(block_id)
                tasks.append(
                    BlockTask(
                        task_id=task_id,
                        gaussian_order=gaussian_order,
                        gid=projected.source.gid,
                        block_id=block_id,
                        ready_cycle=sh_ready,
                        pixel_count=pixel_count,
                        predecessor=predecessor,
                    )
                )
                previous_by_block[block_id] = task_id
                task_id += 1
            gaussian_order += 1
        sh_busy = ceil(len(projected_group) / config.sh_throughput) if projected_group else 0
        sh_available = sh_start + sh_busy
        sh_busy_total += sh_busy
        sh_first = sh_start if sh_first is None else min(sh_first, sh_start)
        sh_last = max(sh_last, sh_start + (config.sh_latency if projected_group else 0) + sh_busy)

    raster = simulate_scoreboard(tasks, config.scoreboard, enforce_dependencies=True)
    raster_ideal = simulate_scoreboard(tasks, config.scoreboard, enforce_dependencies=False)
    total_cycles = max(global_ready, projection_last, sort_last, sh_last, raster.end_cycle)
    seconds = total_cycles / config.frequency_hz if total_cycles else 0.0

    projection_stage = StageReport(
        projection_first or global_ready, projection_last, projection_busy_total, len(depth_records)
    )
    sort_stage = StageReport(sort_first or global_ready, sort_last, sort_busy_total, sum(group_sizes_after))
    sh_stage = StageReport(sh_first or global_ready, sh_last, sh_busy_total, len(projected_flat))

    fp = config.fp_bytes
    traffic = TrafficReport()
    traffic.depth_attribute_bytes = len(source) * 3 * fp
    # Re-read geometry after depth grouping: mean, scale, quaternion, opacity.
    traffic.geometry_attribute_bytes = len(depth_records) * (3 + 3 + 4 + 1) * fp
    traffic.sh_attribute_bytes = len(projected_flat) * config.model_sh_coefficients * fp
    traffic.output_bytes = camera.width * camera.height * 3 * fp
    traffic.dram_read_bytes = (
        traffic.depth_attribute_bytes + traffic.geometry_attribute_bytes + traffic.sh_attribute_bytes
    )
    traffic.dram_write_bytes = traffic.output_bytes
    record_bytes = 4 + config.id_bytes
    traffic.sort_record_bytes = (len(depth_records) * 2 + len(projected_flat) * 2) * record_bytes
    traffic.image_state_bytes = sum(task.pixel_count for task in tasks) * (3 + 1) * fp * 2
    projected_feature_bytes = len(tasks) * (2 + 3 + 1 + 3) * fp
    traffic.sram_read_bytes = traffic.sort_record_bytes // 2 + traffic.image_state_bytes // 2 + projected_feature_bytes
    traffic.sram_write_bytes = traffic.sort_record_bytes // 2 + traffic.image_state_bytes // 2

    return B0Report(
        total_cycles=total_cycles,
        seconds_per_frame=seconds,
        fps=(1.0 / seconds if seconds else 0.0),
        input_gaussians=len(source),
        depth_visible_gaussians=len(depth_records),
        projected_gaussians=len(projected_flat),
        screen_culled_gaussians=len(depth_records) - len(projected_flat),
        sorted_ids=[item.source.gid for item in projected_flat],
        group_sizes_before_projection=[len(group) for group in groups],
        group_sizes_after_projection=group_sizes_after,
        grouping=grouping,
        depth_stage=depth_stage,
        projection_stage=projection_stage,
        sort_stage=sort_stage,
        sh_stage=sh_stage,
        raster=raster,
        raster_ideal=raster_ideal,
        raster_trace=raster_trace,
        traffic=traffic,
        block_tasks=len(tasks),
        block_pixels=sum(task.pixel_count for task in tasks),
        scoreboard_overhead_cycles=max(0, raster.end_cycle - raster_ideal.end_cycle),
    )
