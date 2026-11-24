from __future__ import annotations

from bisect import bisect_right
from dataclasses import dataclass, field
from typing import Generic, Iterable, TypeVar


T = TypeVar("T")
DepthKey = tuple[float, int]


@dataclass(frozen=True)
class DepthRecord(Generic[T]):
    depth: float
    gid: int
    payload: T

    @property
    def key(self) -> DepthKey:
        return (float(self.depth), int(self.gid))


@dataclass
class GroupingReport:
    input_records: int = 0
    output_groups: int = 0
    partition_rounds: int = 0
    comparator_evaluations: int = 0
    pivot_sort_comparisons: int = 0
    max_group_size: int = 0
    recursion_depth: int = 0
    group_sizes: list[int] = field(default_factory=list)


def _sample_pivots(records: list[DepthRecord[T]], pivot_count: int) -> tuple[list[DepthKey], int]:
    """Select and sort a tiny deterministic sample, feasible for an RCA front end."""
    count = min(pivot_count, len(records) - 1)
    if count <= 0:
        return [], 0
    # Spread sample locations across arrival order. Sorting only count pivots is
    # intentionally distinct from sorting the full group.
    indices = [((i + 1) * len(records)) // (count + 1) for i in range(count)]
    pivots = sorted({records[min(index, len(records) - 1)].key for index in indices})
    # Small-sort comparison upper bound; exact network choice belongs to RTL.
    comparisons = len(pivots) * max(0, len(pivots).bit_length() - 1)
    return pivots, comparisons


def hierarchical_depth_groups(
    records: Iterable[DepthRecord[T]], max_group_size: int = 256, pivot_count: int = 7
) -> tuple[list[list[DepthRecord[T]]], GroupingReport]:
    """Hardware-style recursive multi-pivot grouping with strict group ordering.

    Each partition stage compares records with a small sorted pivot set. Final
    groups are ordered, but records inside a group remain unsorted. A stable GID
    tie-breaker makes equal-depth records deterministic and prevents degenerate
    all-equal-depth partitions.
    """
    if max_group_size <= 0:
        raise ValueError("max_group_size must be positive")
    if pivot_count <= 0:
        raise ValueError("pivot_count must be positive")
    source = list(records)
    report = GroupingReport(input_records=len(source))
    if not source:
        return [], report

    output: list[list[DepthRecord[T]]] = []
    work: list[tuple[list[DepthRecord[T]], int]] = [(source, 1)]
    safety = 0
    while work:
        current, depth = work.pop()
        report.recursion_depth = max(report.recursion_depth, depth)
        if len(current) <= max_group_size:
            output.append(current)
            continue

        report.partition_rounds += 1
        pivots, pivot_comparisons = _sample_pivots(current, pivot_count)
        report.pivot_sort_comparisons += pivot_comparisons
        if not pivots:
            raise RuntimeError("unable to select grouping pivots")
        bins: list[list[DepthRecord[T]]] = [[] for _ in range(len(pivots) + 1)]
        for record in current:
            # bisect models parallel pivot comparison plus popcount/rank logic.
            bins[bisect_right(pivots, record.key)].append(record)
        report.comparator_evaluations += len(current) * len(pivots)
        nonempty = [bucket for bucket in bins if bucket]

        if len(nonempty) == 1 and len(nonempty[0]) == len(current):
            # A monotonic or adversarial arrival order can make a sampled pivot
            # land at an extreme. Use min/max midpoint as a hardware-friendly
            # retry; GID participates in the key, so progress is guaranteed.
            low = min(current, key=lambda item: item.key).key
            high = max(current, key=lambda item: item.key).key
            midpoint_depth = (low[0] + high[0]) * 0.5
            midpoint_gid = (low[1] + high[1]) // 2 if low[0] == high[0] else -2**31
            midpoint = (midpoint_depth, midpoint_gid)
            left = [record for record in current if record.key <= midpoint]
            right = [record for record in current if record.key > midpoint]
            report.comparator_evaluations += len(current)
            if not left or not right:
                # Last-resort deterministic selection models a controller retry,
                # not a datapath full sort. It is reachable only pathologically.
                ordered_keys = sorted(record.key for record in current)
                midpoint = ordered_keys[len(ordered_keys) // 2 - 1]
                left = [record for record in current if record.key <= midpoint]
                right = [record for record in current if record.key > midpoint]
            nonempty = [left, right]

        # LIFO work queue: push far-to-near so near groups are emitted first.
        for bucket in reversed(nonempty):
            work.append((bucket, depth + 1))
        safety += 1
        if safety > max(1024, len(source) * 8):
            raise RuntimeError("depth grouping did not converge")

    output.sort(key=lambda group: min(record.key for record in group))
    # A pivot equals an input key; bisect_right assigns equals consistently, so
    # these assertions should always hold and catch future algorithm changes.
    for index in range(len(output) - 1):
        if max(record.key for record in output[index]) > min(record.key for record in output[index + 1]):
            raise AssertionError("depth groups violate global order")
    report.output_groups = len(output)
    report.group_sizes = [len(group) for group in output]
    report.max_group_size = max(report.group_sizes, default=0)
    if report.max_group_size > max_group_size:
        raise AssertionError("depth group exceeds configured capacity")
    return output, report

