from __future__ import annotations

import json
import sys
from math import ceil, log2
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.cycle import R1Config
from model.io import discover_scenes, iter_gaussian_batches, read_cameras, scaled_camera


BLOCK_SIZE = 8
DEPTH_GROUP_SIZE = 256
PROFILE_WINDOW = 4096
ALPHA_THRESHOLD = 1.0 / 255.0
NEAR = 0.2
FAR = 1.0e5
COVARIANCE_REGULARIZER = 0.3
SIGMA_LIMIT = 3.0


def rotation_matrices(quaternion):
    w, x, y, z = quaternion.T
    result = np.empty((len(quaternion), 3, 3), dtype=np.float32)
    result[:, 0, 0] = 1 - 2 * (y * y + z * z)
    result[:, 0, 1] = 2 * (x * y - w * z)
    result[:, 0, 2] = 2 * (x * z + w * y)
    result[:, 1, 0] = 2 * (x * y + w * z)
    result[:, 1, 1] = 1 - 2 * (x * x + z * z)
    result[:, 1, 2] = 2 * (y * z - w * x)
    result[:, 2, 0] = 2 * (x * z - w * y)
    result[:, 2, 1] = 2 * (y * z + w * x)
    result[:, 2, 2] = 1 - 2 * (x * x + y * y)
    return result


def projected_block_counts(batch, camera):
    count = len(batch.mean)
    blocks = np.zeros(count, dtype=np.int32)
    mean_camera = batch.mean @ camera.world_to_camera[:3, :3].T + camera.world_to_camera[:3, 3]
    depth = mean_camera[:, 2].astype(np.float32)
    visible = (depth >= NEAR) & (depth <= FAR) & (batch.opacity >= ALPHA_THRESHOLD)
    index = np.flatnonzero(visible)
    if not len(index):
        return depth, visible, blocks

    xyz = mean_camera[index]
    z = xyz[:, 2]
    x = xyz[:, 0]
    y = xyz[:, 1]
    mean_x = camera.fx * x / z + camera.cx
    mean_y = camera.fy * y / z + camera.cy

    rotation = rotation_matrices(batch.quaternion[index])
    view_rotation = camera.world_to_camera[:3, :3]
    transformed = np.einsum("ij,njk->nik", view_rotation, rotation, optimize=True)
    transformed *= batch.scale[index, None, :]
    j00 = camera.fx / z
    j02 = -camera.fx * x / (z * z)
    j11 = camera.fy / z
    j12 = -camera.fy * y / (z * z)
    row0 = j00[:, None] * transformed[:, 0, :] + j02[:, None] * transformed[:, 2, :]
    row1 = j11[:, None] * transformed[:, 1, :] + j12[:, None] * transformed[:, 2, :]
    cov00 = np.einsum("ni,ni->n", row0, row0) + COVARIANCE_REGULARIZER
    cov11 = np.einsum("ni,ni->n", row1, row1) + COVARIANCE_REGULARIZER
    cov01 = np.einsum("ni,ni->n", row0, row1)
    discriminant = np.sqrt(np.maximum(0.0, (cov00 - cov11) ** 2 + 4.0 * cov01 * cov01))
    max_eigenvalue = 0.5 * (cov00 + cov11 + discriminant)
    opacity_radius = np.sqrt(np.maximum(0.0, 2.0 * np.log(batch.opacity[index] / ALPHA_THRESHOLD)))
    radius = np.maximum(1, np.ceil(np.minimum(SIGMA_LIMIT, opacity_radius) * np.sqrt(max_eigenvalue))).astype(np.int64)

    x0 = np.maximum(0, np.floor(mean_x).astype(np.int64) - radius)
    y0 = np.maximum(0, np.floor(mean_y).astype(np.int64) - radius)
    x1 = np.minimum(camera.width, np.floor(mean_x).astype(np.int64) + radius + 1)
    y1 = np.minimum(camera.height, np.floor(mean_y).astype(np.int64) + radius + 1)
    on_screen = (x0 < x1) & (y0 < y1)
    bx = np.where(on_screen, (x1 - 1) // BLOCK_SIZE - x0 // BLOCK_SIZE + 1, 0)
    by = np.where(on_screen, (y1 - 1) // BLOCK_SIZE - y0 // BLOCK_SIZE + 1, 0)
    blocks[index] = np.minimum(bx * by, np.iinfo(np.int32).max).astype(np.int32)
    return depth, visible, blocks


def bitonic_comparisons(size):
    size = np.asarray(size, dtype=np.int64)
    result = np.zeros_like(size)
    valid = size > 1
    stages = np.ceil(np.log2(np.maximum(size[valid], 1))).astype(np.int64)
    padded = 1 << stages
    result[valid] = padded * stages * (stages + 1) // 4
    return result


def profile_windows(depth, depth_visible, blocks):
    indices = np.flatnonzero(depth_visible)
    order = indices[np.argsort(depth[indices], kind="stable")]
    ordered_blocks = blocks[order]
    window_count = ceil(len(order) / PROFILE_WINDOW) if len(order) else 0
    windows = []
    config = R1Config()
    for window_index in range(window_count):
        start = window_index * PROFILE_WINDOW
        stop = min(len(order), start + PROFILE_WINDOW)
        window_blocks = ordered_blocks[start:stop]
        projected = int(np.count_nonzero(window_blocks))
        block_tasks = int(window_blocks.astype(np.int64).sum())
        group_projected = np.add.reduceat(
            (window_blocks > 0).astype(np.int64), np.arange(0, len(window_blocks), DEPTH_GROUP_SIZE)
        )
        comparisons = int(bitonic_comparisons(group_projected).sum())
        cycles = {}
        for mode in config.modes:
            projection_cycles = ceil(len(window_blocks) / mode.projection_lanes)
            sort_cycles = ceil(comparisons / (mode.sort_lanes * config.sort_comparators_per_lane)) if comparisons else 0
            raster_cycles = ceil(block_tasks / mode.raster_lanes) if block_tasks else 0
            sh_cycles = projected  # Dedicated one-result/cycle SH unit.
            cycles[mode.name] = max(projection_cycles, sort_cycles, raster_cycles, sh_cycles)
        best = min(cycles, key=lambda name: (cycles[name], name))
        windows.append(
            {
                "input_gaussians": stop - start,
                "projected_gaussians": projected,
                "candidate_blocks": block_tasks,
                "sort_comparisons": comparisons,
                "best_mode": best,
                "mode_cycles": cycles,
            }
        )
    return windows


def dynamic_mode_summary(windows, switch_cost=12):
    if not windows:
        return {"cycles": 0, "switches": 0, "mode_histogram": {}, "runs": []}
    names = tuple(windows[0]["mode_cycles"])
    states = {name: (windows[0]["mode_cycles"][name], [name]) for name in names}
    for window in windows[1:]:
        next_states = {}
        for name in names:
            candidates = []
            for previous, (cycles, history) in states.items():
                candidates.append((cycles + (switch_cost if previous != name else 0) + window["mode_cycles"][name], history + [name]))
            next_states[name] = min(candidates, key=lambda item: item[0])
        states = next_states
    cycles, sequence = min(states.values(), key=lambda item: item[0])
    runs = []
    start = 0
    for index in range(1, len(sequence) + 1):
        if index == len(sequence) or sequence[index] != sequence[start]:
            runs.append({"window_start": start, "window_end": index, "mode": sequence[start]})
            start = index
    histogram = {name: sequence.count(name) for name in names}
    return {"cycles": cycles, "switches": len(runs) - 1, "mode_histogram": histogram, "runs": runs}


def percentiles(value):
    if not len(value):
        return {"0": 0, "0.5": 0, "0.9": 0, "0.99": 0, "1": 0}
    return {str(q): float(v) for q, v in zip((0, 0.5, 0.9, 0.99, 1), np.quantile(value, (0, 0.5, 0.9, 0.99, 1)))}


def main():
    report = {
        "metadata": {
            "date": "2026-08-04",
            "camera_selection": "middle camera by JSON order",
            "resolution": "aspect-preserving, longest dimension 1920",
            "block_size": BLOCK_SIZE,
            "depth_group_size": DEPTH_GROUP_SIZE,
            "profile_window_gaussians": PROFILE_WINDOW,
            "limitations": [
                "candidate bbox blocks only; no exact per-pixel alpha or early-termination trace",
                "one representative camera per scene",
                "R1 area credits and service rates remain uncalibrated",
            ],
        },
        "scenes": {},
    }
    for scene in discover_scenes(ROOT / "data"):
        cameras = read_cameras(scene.cameras_json)
        camera_index = len(cameras) // 2
        camera = scaled_camera(cameras[camera_index], 1920)
        depth_parts = []
        visible_parts = []
        block_parts = []
        for batch in iter_gaussian_batches(scene.final_ply, batch_size=131072, include_sh=False):
            depth, visible, blocks = projected_block_counts(batch, camera)
            depth_parts.append(depth)
            visible_parts.append(visible)
            block_parts.append(blocks)
        depth = np.concatenate(depth_parts)
        visible = np.concatenate(visible_parts)
        blocks = np.concatenate(block_parts)
        windows = profile_windows(depth, visible, blocks)
        dynamic = dynamic_mode_summary(windows, switch_cost=12)
        projected = blocks > 0
        best_histogram = {mode.name: sum(window["best_mode"] == mode.name for window in windows) for mode in R1Config().modes}
        fixed_cycles = {
            mode.name: sum(window["mode_cycles"][mode.name] for window in windows) for mode in R1Config().modes
        }
        best_fixed = min(fixed_cycles, key=fixed_cycles.get) if fixed_cycles else None
        report["scenes"][scene.name] = {
            "camera_index": camera_index,
            "resolution": [camera.width, camera.height],
            "input_gaussians": len(depth),
            "depth_visible_gaussians": int(np.count_nonzero(visible)),
            "projected_gaussians": int(np.count_nonzero(projected)),
            "depth_visible_ratio": float(np.mean(visible)),
            "projection_survival_ratio": float(np.count_nonzero(projected) / max(1, np.count_nonzero(visible))),
            "candidate_blocks": int(blocks.astype(np.int64).sum()),
            "blocks_per_projected_gaussian": percentiles(blocks[projected]),
            "profile_windows": len(windows),
            "local_best_mode_histogram": best_histogram,
            "best_fixed_mode": best_fixed,
            "fixed_mode_cycles": fixed_cycles,
            "dynamic": dynamic,
            "dynamic_vs_best_fixed_ratio": dynamic["cycles"] / fixed_cycles[best_fixed] if best_fixed else None,
        }
        print(scene.name, report["scenes"][scene.name])
    output = ROOT / "experiments" / "real_workload_profiles.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
