from __future__ import annotations

import json
import math
import statistics
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.cycle import R1Config
from model.io import discover_scenes, iter_gaussian_batches, read_cameras, scaled_camera
from scripts.profile_real_workloads import (
    dynamic_mode_summary,
    percentiles,
    profile_windows,
    projected_block_counts,
)


def summarize_view(depth, visible, blocks, camera_index, camera):
    windows = profile_windows(depth, visible, blocks)
    dynamic = dynamic_mode_summary(windows, switch_cost=12)
    projected = blocks > 0
    config = R1Config()
    fixed_cycles = {
        mode.name: sum(window["mode_cycles"][mode.name] for window in windows) for mode in config.modes
    }
    best_fixed = min(fixed_cycles, key=fixed_cycles.get) if fixed_cycles else None
    return {
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
        "best_fixed_mode": best_fixed,
        "fixed_mode_cycles": fixed_cycles,
        "dynamic": {
            "cycles": dynamic["cycles"],
            "switches": dynamic["switches"],
            "mode_histogram": dynamic["mode_histogram"],
            "run_count": len(dynamic["runs"]),
        },
        "dynamic_vs_best_fixed_ratio": dynamic["cycles"] / fixed_cycles[best_fixed] if best_fixed else None,
    }


def main():
    report = {
        "metadata": {
            "date": "2026-08-04",
            "camera_selection": "first, middle and last camera by JSON order",
            "resolution": "aspect-preserving, longest dimension 1920",
            "views_per_scene": 3,
            "switch_cost_cycles": 12,
            "limitations": [
                "candidate bbox blocks only; no exact per-pixel alpha or early-termination trace",
                "provisional R1 area credits and service rates",
                "three views per scene are representative samples, not all-camera evaluation",
            ],
        },
        "scenes": {},
        "aggregate": {},
    }
    all_ratios = []
    all_switches = []
    all_best_modes = []
    for scene in discover_scenes(ROOT / "data"):
        source_cameras = read_cameras(scene.cameras_json)
        camera_indices = sorted({0, len(source_cameras) // 2, len(source_cameras) - 1})
        cameras = [scaled_camera(source_cameras[index], 1920) for index in camera_indices]
        parts = {index: {"depth": [], "visible": [], "blocks": []} for index in camera_indices}
        for batch in iter_gaussian_batches(scene.final_ply, batch_size=131072, include_sh=False):
            for index, camera in zip(camera_indices, cameras):
                depth, visible, blocks = projected_block_counts(batch, camera)
                parts[index]["depth"].append(depth)
                parts[index]["visible"].append(visible)
                parts[index]["blocks"].append(blocks)
        views = []
        for index, camera in zip(camera_indices, cameras):
            view = summarize_view(
                np.concatenate(parts[index]["depth"]),
                np.concatenate(parts[index]["visible"]),
                np.concatenate(parts[index]["blocks"]),
                index,
                camera,
            )
            views.append(view)
            all_ratios.append(view["dynamic_vs_best_fixed_ratio"])
            all_switches.append(view["dynamic"]["switches"])
            all_best_modes.append(view["best_fixed_mode"])
        ratios = [view["dynamic_vs_best_fixed_ratio"] for view in views]
        report["scenes"][scene.name] = {
            "views": views,
            "geomean_dynamic_vs_best_fixed_ratio": math.exp(statistics.mean(math.log(value) for value in ratios)),
            "best_fixed_modes": {name: sum(view["best_fixed_mode"] == name for view in views) for name in set(all_best_modes)},
            "views_with_over_1pct_dynamic_gain": sum(value < 0.99 for value in ratios),
        }
        print(
            scene.name,
            "ratios", [round(value, 5) for value in ratios],
            "switches", [view["dynamic"]["switches"] for view in views],
            "best", [view["best_fixed_mode"] for view in views],
        )

    report["aggregate"] = {
        "view_count": len(all_ratios),
        "geomean_dynamic_vs_best_fixed_ratio": math.exp(statistics.mean(math.log(value) for value in all_ratios)),
        "mean_dynamic_vs_best_fixed_ratio": statistics.mean(all_ratios),
        "minimum_ratio": min(all_ratios),
        "maximum_ratio": max(all_ratios),
        "views_with_over_1pct_dynamic_gain": sum(value < 0.99 for value in all_ratios),
        "views_with_over_2pct_dynamic_gain": sum(value < 0.98 for value in all_ratios),
        "views_with_no_switch": sum(value == 0 for value in all_switches),
        "best_fixed_mode_histogram": {name: all_best_modes.count(name) for name in sorted(set(all_best_modes))},
    }
    output = ROOT / "experiments" / "real_workload_profiles_multiview.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("aggregate", report["aggregate"])
    print(output)


if __name__ == "__main__":
    main()
