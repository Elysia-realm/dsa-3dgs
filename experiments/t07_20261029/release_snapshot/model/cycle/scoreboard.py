from __future__ import annotations

import heapq
from dataclasses import dataclass, field


@dataclass(frozen=True)
class BlockTask:
    task_id: int
    gaussian_order: int
    gid: int
    block_id: int
    ready_cycle: int
    pixel_count: int
    predecessor: int | None = None


@dataclass(frozen=True)
class ScoreboardConfig:
    alpha_arrays: int = 1
    blend_arrays: int = 1
    alpha_latency: int = 14
    blend_latency: int = 4
    result_queue_depth: int = 16

    def __post_init__(self):
        for name in ("alpha_arrays", "blend_arrays", "alpha_latency", "blend_latency", "result_queue_depth"):
            if getattr(self, name) <= 0:
                raise ValueError(f"{name} must be positive")


@dataclass
class ScoreboardReport:
    start_cycle: int = 0
    end_cycle: int = 0
    total_cycles: int = 0
    tasks: int = 0
    alpha_issues: int = 0
    blend_issues: int = 0
    scoreboard_stall_cycles: int = 0
    result_queue_stall_cycles: int = 0
    input_wait_cycles: int = 0
    max_result_queue: int = 0
    alpha_busy_slots: int = 0
    blend_busy_slots: int = 0
    alpha_utilization: float = 0.0
    blend_utilization: float = 0.0
    completion_cycles: dict[int, int] = field(default_factory=dict)


def simulate_scoreboard(
    tasks: list[BlockTask], config: ScoreboardConfig = ScoreboardConfig(), enforce_dependencies: bool = True
) -> ScoreboardReport:
    """Cycle simulation of alpha issue, finite result queue and ordered blending."""
    report = ScoreboardReport(tasks=len(tasks))
    if not tasks:
        return report
    ordered = sorted(tasks, key=lambda task: (task.gaussian_order, task.task_id))
    report.start_cycle = min(task.ready_cycle for task in ordered)
    cycle = report.start_cycle
    issue_index = 0
    alpha_inflight: list[tuple[int, int, BlockTask]] = []
    blend_inflight: list[tuple[int, int, BlockTask]] = []
    pending: list[BlockTask] = []
    completed: set[int] = set()
    serial = 0

    max_cycles = max(task.ready_cycle for task in ordered) + len(ordered) * (
        config.alpha_latency + config.blend_latency + 8
    ) + 1024
    while len(completed) < len(ordered):
        progressed = False
        while alpha_inflight and alpha_inflight[0][0] <= cycle:
            _, _, task = heapq.heappop(alpha_inflight)
            pending.append(task)
            progressed = True
        while blend_inflight and blend_inflight[0][0] <= cycle:
            done_cycle, _, task = heapq.heappop(blend_inflight)
            completed.add(task.task_id)
            report.completion_cycles[task.task_id] = done_cycle
            progressed = True

        blend_slots = config.blend_arrays
        issued_blend = 0
        while blend_slots > 0 and pending:
            candidate_index = None
            for index, task in enumerate(pending):
                if not enforce_dependencies or task.predecessor is None or task.predecessor in completed:
                    candidate_index = index
                    break
            if candidate_index is None:
                break
            task = pending.pop(candidate_index)
            serial += 1
            heapq.heappush(blend_inflight, (cycle + config.blend_latency, serial, task))
            report.blend_issues += 1
            report.blend_busy_slots += 1
            issued_blend += 1
            blend_slots -= 1
            progressed = True
        if pending and issued_blend < config.blend_arrays:
            blocked = all(
                enforce_dependencies and task.predecessor is not None and task.predecessor not in completed
                for task in pending
            )
            if blocked:
                report.scoreboard_stall_cycles += 1

        alpha_slots = config.alpha_arrays
        issued_alpha = 0
        while alpha_slots > 0 and issue_index < len(ordered):
            task = ordered[issue_index]
            if task.ready_cycle > cycle:
                break
            occupied = len(pending) + len(alpha_inflight)
            if occupied >= config.result_queue_depth:
                break
            serial += 1
            heapq.heappush(alpha_inflight, (cycle + config.alpha_latency, serial, task))
            issue_index += 1
            alpha_slots -= 1
            issued_alpha += 1
            report.alpha_issues += 1
            report.alpha_busy_slots += 1
            progressed = True
        if issue_index < len(ordered) and ordered[issue_index].ready_cycle <= cycle and issued_alpha < config.alpha_arrays:
            if len(pending) + len(alpha_inflight) >= config.result_queue_depth:
                report.result_queue_stall_cycles += 1
        elif issue_index < len(ordered) and ordered[issue_index].ready_cycle > cycle and not alpha_inflight and not pending:
            report.input_wait_cycles += 1

        report.max_result_queue = max(report.max_result_queue, len(pending) + len(alpha_inflight))
        if cycle > max_cycles:
            raise RuntimeError("scoreboard simulation exceeded safety bound; possible dependency cycle")
        cycle += 1

    report.end_cycle = max(report.completion_cycles.values())
    report.total_cycles = report.end_cycle - report.start_cycle
    capacity_cycles = max(1, report.total_cycles)
    report.alpha_utilization = report.alpha_busy_slots / (capacity_cycles * config.alpha_arrays)
    report.blend_utilization = report.blend_busy_slots / (capacity_cycles * config.blend_arrays)
    return report

