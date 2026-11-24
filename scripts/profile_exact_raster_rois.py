from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.io import discover_scenes, iter_gaussian_batches, read_cameras, scaled_camera
from scripts.profile_real_workloads import (
    ALPHA_THRESHOLD,
    BLOCK_SIZE,
    COVARIANCE_REGULARIZER,
    FAR,
    NEAR,
    SIGMA_LIMIT,
    rotation_matrices,
    bitonic_comparisons,
    dynamic_mode_summary,
)
from model.cycle import R1Config


@dataclass
class TraceStats:
    projected_roi_gaussians: int = 0
    candidate_blocks: int = 0
    skipped_terminated_blocks: int = 0
    active_block_visits: int = 0
    candidate_pixels: int = 0
    alpha_evaluations: int = 0
    alpha_pruned: int = 0
    blend_updates: int = 0
    skipped_terminated_pixels: int = 0
    terminated_pixels: int = 0


def project_roi(batch, camera, roi):
    rx0, ry0, rx1, ry1 = roi
    count = len(batch.mean)
    mean_camera = batch.mean @ camera.world_to_camera[:3, :3].T + camera.world_to_camera[:3, 3]
    depth = mean_camera[:, 2]
    visible = (depth >= NEAR) & (depth <= FAR) & (batch.opacity >= ALPHA_THRESHOLD)
    index = np.flatnonzero(visible)
    if not len(index):
        return None

    xyz = mean_camera[index]
    z, x, y = xyz[:, 2], xyz[:, 0], xyz[:, 1]
    mean_x = camera.fx * x / z + camera.cx
    mean_y = camera.fy * y / z + camera.cy
    rotation = rotation_matrices(batch.quaternion[index])
    transformed = np.einsum("ij,njk->nik", camera.world_to_camera[:3, :3], rotation, optimize=True)
    transformed *= batch.scale[index, None, :]
    j00, j02 = camera.fx / z, -camera.fx * x / (z * z)
    j11, j12 = camera.fy / z, -camera.fy * y / (z * z)
    row0 = j00[:, None] * transformed[:, 0, :] + j02[:, None] * transformed[:, 2, :]
    row1 = j11[:, None] * transformed[:, 1, :] + j12[:, None] * transformed[:, 2, :]
    cov00 = np.einsum("ni,ni->n", row0, row0) + COVARIANCE_REGULARIZER
    cov11 = np.einsum("ni,ni->n", row1, row1) + COVARIANCE_REGULARIZER
    cov01 = np.einsum("ni,ni->n", row0, row1)
    determinant = cov00 * cov11 - cov01 * cov01
    finite = (determinant > 1.0e-12) & np.isfinite(determinant)
    index = index[finite]
    if not len(index):
        return None
    mean_x, mean_y, z = mean_x[finite], mean_y[finite], z[finite]
    cov00, cov11, cov01, determinant = cov00[finite], cov11[finite], cov01[finite], determinant[finite]
    discriminant = np.sqrt(np.maximum(0.0, (cov00 - cov11) ** 2 + 4.0 * cov01 * cov01))
    max_eigenvalue = 0.5 * (cov00 + cov11 + discriminant)
    opacity = batch.opacity[index]
    opacity_radius = np.sqrt(np.maximum(0.0, 2.0 * np.log(opacity / ALPHA_THRESHOLD)))
    radius = np.maximum(1, np.ceil(np.minimum(SIGMA_LIMIT, opacity_radius) * np.sqrt(max_eigenvalue))).astype(np.int32)
    center_x, center_y = np.floor(mean_x).astype(np.int32), np.floor(mean_y).astype(np.int32)
    screen_x0, screen_y0 = np.maximum(0, center_x - radius), np.maximum(0, center_y - radius)
    screen_x1 = np.minimum(camera.width, center_x + radius + 1)
    screen_y1 = np.minimum(camera.height, center_y + radius + 1)
    x0, y0 = np.maximum(rx0, screen_x0), np.maximum(ry0, screen_y0)
    x1, y1 = np.minimum(rx1, screen_x1), np.minimum(ry1, screen_y1)
    overlap = (x0 < x1) & (y0 < y1)
    if not np.any(overlap):
        return None
    index = index[overlap]
    inv = 1.0 / determinant[overlap]
    return {
        "gid": batch.start + index.astype(np.int64),
        "depth": z[overlap].astype(np.float32),
        "mean_x": mean_x[overlap].astype(np.float32),
        "mean_y": mean_y[overlap].astype(np.float32),
        "conic00": (cov11[overlap] * inv).astype(np.float32),
        "conic01": (-cov01[overlap] * inv).astype(np.float32),
        "conic11": (cov00[overlap] * inv).astype(np.float32),
        "opacity": opacity[overlap].astype(np.float32),
        "x0": x0[overlap], "y0": y0[overlap], "x1": x1[overlap], "y1": y1[overlap],
        "screen_x0": screen_x0[overlap], "screen_y0": screen_y0[overlap],
        "screen_x1": screen_x1[overlap], "screen_y1": screen_y1[overlap],
    }


def collect_projected(scene, camera, roi):
    parts = []
    for batch in iter_gaussian_batches(scene.final_ply, batch_size=131072, include_sh=False):
        projected = project_roi(batch, camera, roi)
        if projected is not None:
            parts.append(projected)
    if not parts:
        return {}
    result = {name: np.concatenate([part[name] for part in parts]) for name in parts[0]}
    order = np.lexsort((result["gid"], result["depth"]))
    return {name: value[order] for name, value in result.items()}


def subset_projected(projected, roi):
    if not projected:
        return {}
    rx0, ry0, rx1, ry1 = roi
    overlap = (
        (projected["x0"] < rx1) & (projected["x1"] > rx0)
        & (projected["y0"] < ry1) & (projected["y1"] > ry0)
    )
    if not np.any(overlap):
        return {}
    result = {name: value[overlap].copy() for name, value in projected.items()}
    result["x0"] = np.maximum(result["x0"], rx0)
    result["y0"] = np.maximum(result["y0"], ry0)
    result["x1"] = np.minimum(result["x1"], rx1)
    result["y1"] = np.minimum(result["y1"], ry1)
    return result


def trace(projected, roi, transmittance_threshold: float | None = 1.0e-4, window_size: int = 4096):
    rx0, ry0, rx1, ry1 = roi
    transmittance = np.ones((ry1 - ry0, rx1 - rx0), dtype=np.float32)
    terminated = np.zeros_like(transmittance, dtype=np.bool_)
    stats = TraceStats(projected_roi_gaussians=len(projected.get("gid", ())))
    windows = []
    if not projected:
        return stats, transmittance, windows
    for item in range(len(projected["gid"])):
        window_index = item // window_size
        if window_index == len(windows):
            windows.append({
                "input_gaussians": min(window_size, len(projected["gid"]) - item),
                "candidate_blocks": 0,
                "skipped_terminated_blocks": 0,
                "active_block_visits": 0,
                "alpha_evaluations": 0,
                "alpha_pruned": 0,
                "blend_updates": 0,
            })
        window = windows[window_index]
        x0, y0 = int(projected["x0"][item]), int(projected["y0"][item])
        x1, y1 = int(projected["x1"][item]), int(projected["y1"][item])
        for by in range(y0 // BLOCK_SIZE, (y1 - 1) // BLOCK_SIZE + 1):
            py0, py1 = max(y0, by * BLOCK_SIZE), min(y1, (by + 1) * BLOCK_SIZE)
            for bx in range(x0 // BLOCK_SIZE, (x1 - 1) // BLOCK_SIZE + 1):
                px0, px1 = max(x0, bx * BLOCK_SIZE), min(x1, (bx + 1) * BLOCK_SIZE)
                stats.candidate_blocks += 1
                window["candidate_blocks"] += 1
                local_y = slice(py0 - ry0, py1 - ry0)
                local_x = slice(px0 - rx0, px1 - rx0)
                done = terminated[local_y, local_x]
                pixels = done.size
                stats.candidate_pixels += pixels
                if bool(np.all(done)):
                    stats.skipped_terminated_blocks += 1
                    window["skipped_terminated_blocks"] += 1
                    stats.skipped_terminated_pixels += pixels
                    continue
                stats.active_block_visits += 1
                window["active_block_visits"] += 1
                stats.skipped_terminated_pixels += int(np.count_nonzero(done))
                yy, xx = np.mgrid[py0:py1, px0:px1]
                active = ~done
                dx = xx.astype(np.float32) - projected["mean_x"][item]
                dy = yy.astype(np.float32) - projected["mean_y"][item]
                exponent = -0.5 * (
                    projected["conic00"][item] * dx * dx
                    + 2.0 * projected["conic01"][item] * dx * dy
                    + projected["conic11"][item] * dy * dy
                )
                exponent = np.minimum(exponent, 0.0)
                alpha = np.minimum(0.99, projected["opacity"][item] * np.exp(exponent))
                stats.alpha_evaluations += int(np.count_nonzero(active))
                window["alpha_evaluations"] += int(np.count_nonzero(active))
                pass_alpha = active & (alpha >= ALPHA_THRESHOLD)
                stats.alpha_pruned += int(np.count_nonzero(active & ~pass_alpha))
                window["alpha_pruned"] += int(np.count_nonzero(active & ~pass_alpha))
                stats.blend_updates += int(np.count_nonzero(pass_alpha))
                window["blend_updates"] += int(np.count_nonzero(pass_alpha))
                local_t = transmittance[local_y, local_x]
                local_t[pass_alpha] *= (1.0 - alpha[pass_alpha]).astype(np.float32)
                if transmittance_threshold is None:
                    new_terminated = np.zeros_like(pass_alpha)
                else:
                    new_terminated = pass_alpha & (local_t < transmittance_threshold) & ~done
                stats.terminated_pixels += int(np.count_nonzero(new_terminated))
                terminated[local_y, local_x] |= new_terminated
    return stats, transmittance, windows


def add_r1_window_cycles(windows):
    config = R1Config()
    for window in windows:
        gaussian_count = window["input_gaussians"]
        comparisons = int(bitonic_comparisons(np.asarray([gaussian_count], dtype=np.int64))[0])
        cycles = {}
        for mode in config.modes:
            projection_cycles = int(np.ceil(gaussian_count / mode.projection_lanes))
            sort_cycles = int(np.ceil(comparisons / (mode.sort_lanes * config.sort_comparators_per_lane)))
            raster_cycles = int(np.ceil(window["active_block_visits"] / mode.raster_lanes))
            cycles[mode.name] = max(projection_cycles, sort_cycles, raster_cycles)
        window["mode_cycles"] = cycles
        window["best_mode"] = min(cycles, key=lambda name: (cycles[name], name))
    return windows


def roi_from_anchor(camera, size, anchor):
    cx = int(round((camera.width - 1) * anchor[0]))
    cy = int(round((camera.height - 1) * anchor[1]))
    x0 = min(max(0, cx - size // 2), camera.width - size)
    y0 = min(max(0, cy - size // 2), camera.height - size)
    return x0, y0, x0 + size, y0 + size


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--max-dimension", type=int, default=960)
    parser.add_argument("--roi-size", type=int, default=64)
    parser.add_argument("--output", type=Path, default=ROOT / "experiments" / "exact_raster_roi_profiles.json")
    args = parser.parse_args()
    representatives = {"garden": 184, "train": 150, "bonsai": 291}
    scenes = {scene.name: scene for scene in discover_scenes(ROOT / "data")}
    report = {
        "metadata": {
            "date": "2026-08-04",
            "method": "full-scene projection followed by exact per-pixel alpha/blend traces in a 3x3 ROI grid",
            "max_dimension": args.max_dimension,
            "roi_size": args.roi_size,
            "alpha_threshold": ALPHA_THRESHOLD,
            "transmittance_threshold": 1.0e-4,
            "selection": {
                "garden": "largest candidate-model dynamic gain",
                "train": "no-switch control workload",
                "bonsai": "low-gain indoor control workload",
            },
        },
        "scenes": {},
    }
    for name, camera_index in representatives.items():
        scene = scenes[name]
        cameras = read_cameras(scene.cameras_json)
        camera = scaled_camera(cameras[camera_index], args.max_dimension)
        anchors = ((0.25, 0.25), (0.50, 0.25), (0.75, 0.25),
                   (0.25, 0.50), (0.50, 0.50), (0.75, 0.50),
                   (0.25, 0.75), (0.50, 0.75), (0.75, 0.75))
        roi_boxes = [roi_from_anchor(camera, args.roi_size, anchor) for anchor in anchors]
        union_roi = (
            min(roi[0] for roi in roi_boxes), min(roi[1] for roi in roi_boxes),
            max(roi[2] for roi in roi_boxes), max(roi[3] for roi in roi_boxes),
        )
        union_projected = collect_projected(scene, camera, union_roi)
        roi_results = []
        for anchor, roi in zip(anchors, roi_boxes):
            projected = subset_projected(union_projected, roi)
            enabled, transmittance, windows = trace(projected, roi, 1.0e-4)
            disabled, _, disabled_windows = trace(projected, roi, None)
            windows = add_r1_window_cycles(windows)
            dynamic = dynamic_mode_summary(windows, switch_cost=12)
            fixed_cycles = {
                mode.name: sum(window["mode_cycles"][mode.name] for window in windows)
                for mode in R1Config().modes
            }
            best_fixed = min(fixed_cycles, key=fixed_cycles.get) if fixed_cycles else None
            roi_results.append({
                "anchor": list(anchor),
                "roi": list(roi),
                "early_termination": asdict(enabled),
                "termination_disabled": asdict(disabled),
                "alpha_evaluation_ratio": enabled.alpha_evaluations / max(1, disabled.alpha_evaluations),
                "active_block_ratio": enabled.active_block_visits / max(1, disabled.active_block_visits),
                "blend_ratio": enabled.blend_updates / max(1, disabled.blend_updates),
                "best_fixed_mode": best_fixed,
                "fixed_mode_cycles": fixed_cycles,
                "dynamic": dynamic,
                "dynamic_vs_best_fixed_ratio": (
                    dynamic["cycles"] / fixed_cycles[best_fixed] if best_fixed else None
                ),
                "window_best_mode_histogram": {
                    mode.name: sum(window["best_mode"] == mode.name for window in windows)
                    for mode in R1Config().modes
                },
                "final_transmittance": {
                    "mean": float(np.mean(transmittance)),
                    "p50": float(np.quantile(transmittance, 0.5)),
                    "p90": float(np.quantile(transmittance, 0.9)),
                    "terminated_fraction": enabled.terminated_pixels / (args.roi_size * args.roi_size),
                },
            })
        alpha_ratios = [roi["alpha_evaluation_ratio"] for roi in roi_results]
        block_ratios = [roi["active_block_ratio"] for roi in roi_results]
        result = {
            "camera_index": camera_index,
            "resolution": [camera.width, camera.height],
            "roi_count": len(roi_results),
            "alpha_evaluation_ratio": {
                "min": min(alpha_ratios), "median": float(np.median(alpha_ratios)), "max": max(alpha_ratios)
            },
            "active_block_ratio": {
                "min": min(block_ratios), "median": float(np.median(block_ratios)), "max": max(block_ratios)
            },
            "rois": roi_results,
        }
        report["scenes"][name] = result
        print(name, json.dumps(result, ensure_ascii=False))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(args.output)


if __name__ == "__main__":
    main()
