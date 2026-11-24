from __future__ import annotations

from dataclasses import dataclass, field
from math import ceil, log2
from typing import Iterable, Literal

from model.reference.model import Camera, Gaussian3D, RenderConfig

from .b0 import TrafficReport
from .scoreboard import BlockTask, ScoreboardConfig, ScoreboardReport, simulate_scoreboard
from .workload import CycleWorkload, RasterTaskSpec, build_cycle_workload


@dataclass(frozen=True)
class R0Mode:
    name: str
    projection_lanes: int
    sort_lanes: int
    alpha_lanes: int

    @property
    def total_lanes(self) -> int:
        return self.projection_lanes + self.sort_lanes + self.alpha_lanes


DEFAULT_MODES = (
    R0Mode("balanced", projection_lanes=3, sort_lanes=2, alpha_lanes=3),
    R0Mode("projection_priority", projection_lanes=4, sort_lanes=2, alpha_lanes=2),
    R0Mode("sort_priority", projection_lanes=2, sort_lanes=4, alpha_lanes=2),
    R0Mode("raster_priority", projection_lanes=2, sort_lanes=1, alpha_lanes=5),
)


@dataclass(frozen=True)
class R0Config:
    frequency_hz: float = 500e6
    total_elastic_lanes: int = 8
    modes: tuple[R0Mode, ...] = DEFAULT_MODES
    policy: Literal["dynamic", "fixed"] = "dynamic"
    fixed_mode: str = "balanced"
    reconfiguration_cycles: int = 12
    depth_throughput: int = 4
    depth_latency: int = 8
    grouping_comparators: int = 28
    grouping_control_cycles: int = 2
    grouping_pivots: int = 7
    minimum_epoch_gaussians: int = 32
    projection_latency: int = 40
    sort_comparators_per_lane: int = 8
    sort_latency: int = 6
    sh_throughput: int = 1
    sh_latency: int = 16
    blend_arrays: int = 2
    alpha_latency: int = 14
    blend_latency: int = 4
    result_queue_depth: int = 24
    fp_bytes: int = 2
    id_bytes: int = 4
    model_sh_coefficients: int = 48

    def __post_init__(self):
        positive = (
            "frequency_hz", "total_elastic_lanes", "depth_throughput", "depth_latency",
            "grouping_comparators", "grouping_control_cycles", "grouping_pivots", "minimum_epoch_gaussians", "projection_latency",
            "sort_comparators_per_lane", "sort_latency", "sh_throughput", "sh_latency", "blend_arrays",
            "alpha_latency", "blend_latency", "result_queue_depth", "fp_bytes", "id_bytes",
            "model_sh_coefficients",
        )
        for name in positive:
            if getattr(self, name) <= 0:
                raise ValueError(f"{name} must be positive")
        if self.reconfiguration_cycles < 0:
            raise ValueError("reconfiguration_cycles must be non-negative")
        if not self.modes:
            raise ValueError("at least one R0 mode is required")
        names = [mode.name for mode in self.modes]
        if len(names) != len(set(names)):
            raise ValueError("R0 mode names must be unique")
        for mode in self.modes:
            if min(mode.projection_lanes, mode.sort_lanes, mode.alpha_lanes) <= 0:
                raise ValueError("each mode allocation must be positive")
            if mode.total_lanes != self.total_elastic_lanes:
                raise ValueError("every R0 mode must use exactly total_elastic_lanes")
        if self.fixed_mode not in names:
            raise ValueError("fixed_mode is not present in modes")


@dataclass
class R0GroupReport:
    group_index: int
    group_end_index: int
    mode: str
    start_cycle: int
    end_cycle: int
    reconfiguration_cycles: int
    input_gaussians: int
    projected_gaussians: int
    sort_comparisons: int
    block_tasks: int
    projection_cycles: int
    sort_cycles: int
    sh_cycles: int
    raster_cycles: int
    scoreboard_stall_cycles: int
    result_queue_stall_cycles: int
    alpha_utilization: float
    blend_utilization: float


@dataclass
class R0Report:
    total_cycles: int
    seconds_per_frame: float
    fps: float
    policy: str
    total_elastic_lanes: int
    reconfigurations: int
    reconfiguration_cycles: int
    selected_modes: list[str]
    mode_histogram: dict[str, int]
    input_gaussians: int
    depth_visible_gaussians: int
    projected_gaussians: int
    sorted_ids: list[int]
    block_tasks: int
    block_pixels: int
    candidate_blocks: int
    skipped_terminated_blocks: int
    traffic: TrafficReport
    groups: list[R0GroupReport] = field(default_factory=list)


def _sort_comparisons(size: int) -> int:
    if size <= 1:
        return 0
    stages = ceil(log2(size))
    padded = 1 << stages
    return padded * stages * (stages + 1) // 4


def _global_ready(workload: CycleWorkload, config: R0Config) -> int:
    depth_busy = ceil(workload.input_gaussians / config.depth_throughput) if workload.input_gaussians else 0
    depth_end = config.depth_latency + depth_busy
    grouping = workload.grouping
    grouping_cycles = (
        ceil((grouping.comparator_evaluations + grouping.pivot_sort_comparisons) / config.grouping_comparators)
        + grouping.partition_rounds * config.grouping_control_cycles
    )
    return depth_end + grouping_cycles


def _schedule_epoch(
    group_index: int,
    group_end_index: int,
    workload: CycleWorkload,
    mode: R0Mode,
    start_cycle: int,
    reconfiguration_cycles: int,
    config: R0Config,
) -> R0GroupReport:
    epoch_start = start_cycle + reconfiguration_cycles
    projection_available = sorter_available = sh_available = epoch_start
    projection_last = sort_last = sh_last = epoch_start
    input_count = projected_count = comparisons = 0
    projection_busy_total = sort_busy_total = sh_busy_total = 0
    specs = [task for index in range(group_index, group_end_index) for task in workload.task_groups[index]]
    ids_in_epoch = {task.task_id for task in specs}
    tasks: list[BlockTask] = []

    for index in range(group_index, group_end_index):
        group_input = len(workload.groups[index])
        group_projected = len(workload.projected_groups[index])
        input_count += group_input
        projected_count += group_projected
        projection_start = projection_available
        projection_busy = ceil(group_input / mode.projection_lanes) if group_input else 0
        projection_end = projection_start + (config.projection_latency if group_input else 0) + projection_busy
        projection_available = projection_start + projection_busy
        projection_last = max(projection_last, projection_end)
        projection_busy_total += projection_busy

        group_comparisons = _sort_comparisons(group_projected)
        comparisons += group_comparisons
        sort_start = max(projection_end, sorter_available)
        sort_busy = ceil(group_comparisons / (mode.sort_lanes * config.sort_comparators_per_lane)) if group_comparisons else 0
        sort_end = sort_start + (config.sort_latency if group_projected else 0) + sort_busy
        sorter_available = sort_start + sort_busy
        sort_last = max(sort_last, sort_end)
        sort_busy_total += sort_busy

        sh_start = max(sort_end, sh_available)
        sh_busy = ceil(group_projected / config.sh_throughput) if group_projected else 0
        sh_available = sh_start + sh_busy
        sh_last = max(sh_last, sh_start + (config.sh_latency if group_projected else 0) + sh_busy)
        sh_busy_total += sh_busy
        for task in workload.task_groups[index]:
            tasks.append(
                BlockTask(
                    task_id=task.task_id,
                    gaussian_order=task.gaussian_order,
                    gid=task.gid,
                    block_id=task.block_id,
                    ready_cycle=sh_start + config.sh_latency + ceil((task.sh_index + 1) / config.sh_throughput),
                    pixel_count=task.pixel_count,
                    predecessor=task.predecessor if task.predecessor in ids_in_epoch else None,
                )
            )
    raster_config = ScoreboardConfig(
        alpha_arrays=mode.alpha_lanes,
        blend_arrays=config.blend_arrays,
        alpha_latency=config.alpha_latency,
        blend_latency=config.blend_latency,
        result_queue_depth=config.result_queue_depth,
    )
    raster = simulate_scoreboard(tasks, raster_config, enforce_dependencies=True)
    end_cycle = max(projection_last, sort_last, sh_last, raster.end_cycle)
    return R0GroupReport(
        group_index=group_index,
        group_end_index=group_end_index,
        mode=mode.name,
        start_cycle=start_cycle,
        end_cycle=end_cycle,
        reconfiguration_cycles=reconfiguration_cycles,
        input_gaussians=input_count,
        projected_gaussians=projected_count,
        sort_comparisons=comparisons,
        block_tasks=len(tasks),
        projection_cycles=projection_busy_total,
        sort_cycles=sort_busy_total,
        sh_cycles=sh_busy_total,
        raster_cycles=raster.total_cycles,
        scoreboard_stall_cycles=raster.scoreboard_stall_cycles,
        result_queue_stall_cycles=raster.result_queue_stall_cycles,
        alpha_utilization=raster.alpha_utilization,
        blend_utilization=raster.blend_utilization,
    )


def simulate_r0(
    gaussians: Iterable[Gaussian3D],
    camera: Camera,
    render_config: RenderConfig = RenderConfig(),
    config: R0Config = R0Config(),
) -> R0Report:
    source = list(gaussians)
    workload = build_cycle_workload(
        source, camera, render_config, config.grouping_pivots, minimum_group_size=config.minimum_epoch_gaussians
    )
    cycle = _global_ready(workload, config)
    fixed = next(mode for mode in config.modes if mode.name == config.fixed_mode)
    if config.policy == "fixed":
        group_reports = [_schedule_epoch(0, len(workload.groups), workload, fixed, cycle, 0, config)] if workload.groups else []
        if group_reports:
            cycle = group_reports[-1].end_cycle
    else:
        # Dynamic programming gives the globally shortest mode sequence under
        # the group-boundary barrier and explicit switching cost. A greedy
        # choice can be locally attractive but force a costly switch later.
        group_count = len(workload.groups)
        states: list[dict[str | None, tuple[int, list[R0GroupReport]]]] = [dict() for _ in range(group_count + 1)]
        states[0][None] = (cycle, [])
        for start in range(group_count):
            for previous_name, (previous_cycle, history) in states[start].items():
                for end in range(start + 1, group_count + 1):
                    for preference, mode in enumerate(config.modes):
                        if previous_name == mode.name:
                            continue  # Adjacent equal-mode epochs should be one pipelined epoch.
                        switch = config.reconfiguration_cycles if previous_name is not None else 0
                        report = _schedule_epoch(start, end, workload, mode, previous_cycle, switch, config)
                        candidate = (report.end_cycle, history + [report])
                        current = states[end].get(mode.name)
                        if current is None or candidate[0] < current[0]:
                            states[end][mode.name] = candidate
        final_states = states[group_count]
        if final_states:
            _, group_reports = min(final_states.values(), key=lambda item: item[0])
            cycle = group_reports[-1].end_cycle
        else:
            group_reports = []

    reconfigurations = sum(
        left.mode != right.mode for left, right in zip(group_reports, group_reports[1:])
    )
    reconfiguration_total = sum(report.reconfiguration_cycles for report in group_reports)

    # Same logical byte definitions as B0, derived from the shared workload.
    fp = config.fp_bytes
    traffic = TrafficReport()
    traffic.depth_attribute_bytes = workload.input_gaussians * 3 * fp
    traffic.geometry_attribute_bytes = len(workload.depth_records) * (3 + 3 + 4 + 1) * fp
    projected_count = sum(len(group) for group in workload.projected_groups)
    traffic.sh_attribute_bytes = projected_count * config.model_sh_coefficients * fp
    traffic.output_bytes = camera.width * camera.height * 3 * fp
    traffic.dram_read_bytes = (
        traffic.depth_attribute_bytes + traffic.geometry_attribute_bytes + traffic.sh_attribute_bytes
    )
    traffic.dram_write_bytes = traffic.output_bytes
    record_bytes = 4 + config.id_bytes
    traffic.sort_record_bytes = (len(workload.depth_records) * 2 + projected_count * 2) * record_bytes
    traffic.image_state_bytes = workload.block_pixels * (3 + 1) * fp * 2
    projected_feature_bytes = workload.block_tasks * (2 + 3 + 1 + 3) * fp
    traffic.sram_read_bytes = traffic.sort_record_bytes // 2 + traffic.image_state_bytes // 2 + projected_feature_bytes
    traffic.sram_write_bytes = traffic.sort_record_bytes // 2 + traffic.image_state_bytes // 2
    histogram = {mode.name: 0 for mode in config.modes}
    for report in group_reports:
        histogram[report.mode] += 1
    seconds = cycle / config.frequency_hz if cycle else 0.0
    return R0Report(
        total_cycles=cycle,
        seconds_per_frame=seconds,
        fps=(1.0 / seconds if seconds else 0.0),
        policy=config.policy,
        total_elastic_lanes=config.total_elastic_lanes,
        reconfigurations=reconfigurations,
        reconfiguration_cycles=reconfiguration_total,
        selected_modes=[report.mode for report in group_reports],
        mode_histogram=histogram,
        input_gaussians=workload.input_gaussians,
        depth_visible_gaussians=len(workload.depth_records),
        projected_gaussians=sum(len(group) for group in workload.projected_groups),
        sorted_ids=workload.sorted_ids,
        block_tasks=workload.block_tasks,
        block_pixels=workload.block_pixels,
        candidate_blocks=workload.candidate_blocks,
        skipped_terminated_blocks=workload.skipped_terminated_blocks,
        traffic=traffic,
        groups=group_reports,
    )
