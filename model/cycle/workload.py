from __future__ import annotations

from dataclasses import dataclass
from math import ceil
from typing import Iterable

import numpy as np

from model.reference.math3d import ProjectedGaussian, alpha_at, project_gaussian
from model.reference.model import Camera, Gaussian3D, RenderConfig

from .grouping import DepthRecord, GroupingReport, hierarchical_depth_groups


@dataclass(frozen=True)
class RasterTaskSpec:
    task_id: int
    group_index: int
    sh_index: int
    gaussian_order: int
    gid: int
    block_id: int
    pixel_count: int
    predecessor: int | None


@dataclass
class CycleWorkload:
    input_gaussians: int
    depth_records: list[DepthRecord[Gaussian3D]]
    groups: list[list[DepthRecord[Gaussian3D]]]
    projected_groups: list[list[ProjectedGaussian]]
    task_groups: list[list[RasterTaskSpec]]
    grouping: GroupingReport
    candidate_blocks: int
    issued_blocks: int
    skipped_terminated_blocks: int
    active_pixel_tests: int
    alpha_pruned_pixels: int
    blend_updates: int
    terminated_pixels: int

    @property
    def sorted_ids(self) -> list[int]:
        return [item.source.gid for group in self.projected_groups for item in group]

    @property
    def block_tasks(self) -> int:
        return sum(len(group) for group in self.task_groups)

    @property
    def block_pixels(self) -> int:
        return sum(task.pixel_count for group in self.task_groups for task in group)


def _merge_adjacent_groups(
    groups: list[list[DepthRecord[Gaussian3D]]], minimum_size: int
) -> list[list[DepthRecord[Gaussian3D]]]:
    if minimum_size <= 1 or len(groups) <= 1:
        return groups
    merged: list[list[DepthRecord[Gaussian3D]]] = []
    pending: list[DepthRecord[Gaussian3D]] = []
    for group in groups:
        pending.extend(group)
        if len(pending) >= minimum_size:
            merged.append(pending)
            pending = []
    if pending:
        if merged:
            merged[-1].extend(pending)
        else:
            merged.append(pending)
    return merged


def _depth_record(gaussian: Gaussian3D, camera: Camera, config: RenderConfig):
    homogeneous = np.append(gaussian.mean, np.float32(1.0)).astype(np.float32)
    depth = float((camera.world_to_camera @ homogeneous)[2])
    if not config.near <= depth <= config.far:
        return None
    return DepthRecord(depth=depth, gid=gaussian.gid, payload=gaussian)


def build_cycle_workload(
    gaussians: Iterable[Gaussian3D],
    camera: Camera,
    render_config: RenderConfig,
    grouping_pivots: int = 7,
    minimum_group_size: int = 1,
) -> CycleWorkload:
    """Build a schedule-independent, exact-alpha task graph shared by B0/R0 studies."""
    source = list(gaussians)
    depth_records = [record for item in source if (record := _depth_record(item, camera, render_config))]
    groups, grouping = hierarchical_depth_groups(
        depth_records, max_group_size=render_config.group_size, pivot_count=grouping_pivots
    )
    groups = _merge_adjacent_groups(groups, minimum_group_size)
    projected_groups: list[list[ProjectedGaussian]] = []
    task_groups: list[list[RasterTaskSpec]] = []
    previous_by_block: dict[int, int] = {}
    transmittance = np.ones((camera.height, camera.width), dtype=np.float32)
    terminated = np.zeros((camera.height, camera.width), dtype=np.bool_)
    blocks_per_row = ceil(camera.width / render_config.block_size)
    task_id = 0
    gaussian_order = 0
    candidate_blocks = issued_blocks = skipped_blocks = 0
    active_pixel_tests = alpha_pruned_pixels = blend_updates = terminated_pixels = 0

    for group_index, group in enumerate(groups):
        projected = [
            item for record in group if (item := project_gaussian(record.payload, camera, render_config)) is not None
        ]
        projected.sort(key=lambda item: (item.depth, item.source.gid))
        projected_groups.append(projected)
        group_tasks: list[RasterTaskSpec] = []
        for sh_index, item in enumerate(projected):
            x0, y0, x1, y1 = item.bbox
            block = render_config.block_size
            for by in range(y0 // block, (y1 - 1) // block + 1):
                py0, py1 = max(y0, by * block), min(y1, (by + 1) * block)
                for bx in range(x0 // block, (x1 - 1) // block + 1):
                    candidate_blocks += 1
                    px0, px1 = max(x0, bx * block), min(x1, (bx + 1) * block)
                    active = ~terminated[py0:py1, px0:px1]
                    active_count = int(np.count_nonzero(active))
                    if active_count == 0:
                        skipped_blocks += 1
                        continue
                    issued_blocks += 1
                    active_pixel_tests += active_count
                    block_id = by * blocks_per_row + bx
                    predecessor = previous_by_block.get(block_id)
                    group_tasks.append(
                        RasterTaskSpec(
                            task_id=task_id,
                            group_index=group_index,
                            sh_index=sh_index,
                            gaussian_order=gaussian_order,
                            gid=item.source.gid,
                            block_id=block_id,
                            pixel_count=active_count,
                            predecessor=predecessor,
                        )
                    )
                    previous_by_block[block_id] = task_id
                    task_id += 1
                    for y in range(py0, py1):
                        for x in range(px0, px1):
                            if terminated[y, x]:
                                continue
                            alpha = alpha_at(item, x, y, render_config)
                            if alpha < render_config.alpha_threshold:
                                alpha_pruned_pixels += 1
                                continue
                            transmittance[y, x] *= np.float32(1.0 - alpha)
                            blend_updates += 1
                            if transmittance[y, x] < render_config.transmittance_threshold:
                                terminated[y, x] = True
                                terminated_pixels += 1
            gaussian_order += 1
        task_groups.append(group_tasks)

    return CycleWorkload(
        input_gaussians=len(source),
        depth_records=depth_records,
        groups=groups,
        projected_groups=projected_groups,
        task_groups=task_groups,
        grouping=grouping,
        candidate_blocks=candidate_blocks,
        issued_blocks=issued_blocks,
        skipped_terminated_blocks=skipped_blocks,
        active_pixel_tests=active_pixel_tests,
        alpha_pruned_pixels=alpha_pruned_pixels,
        blend_updates=blend_updates,
        terminated_pixels=terminated_pixels,
    )
