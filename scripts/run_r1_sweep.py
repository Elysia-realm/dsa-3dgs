from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.cycle import B0Config, R0Config, R1Config, ScoreboardConfig, simulate_b0, simulate_r0, simulate_r1
from model.reference import Camera, Gaussian3D, RenderConfig
from scripts.run_b0_workload_sweep import (
    dense_overlap_scene,
    occlusion_scene,
    single_block_hotspot_scene,
    sparse_scene,
)


def gaussian(gid, mean, scale, opacity):
    return Gaussian3D(
        gid=gid,
        mean=np.asarray(mean, dtype=np.float32),
        scale=np.asarray(scale, dtype=np.float32),
        quaternion=np.asarray((1.0, 0.0, 0.0, 0.0), dtype=np.float32),
        opacity=float(opacity),
        rgb=np.asarray((0.4, 0.5, 0.6), dtype=np.float32),
    )


def heterogeneous_phase_scene():
    """Directed scheduler test, intentionally not a representative 3DGS scene."""
    result = []
    for gid in range(128):
        result.append(gaussian(gid, (20.0, 0.0, 1.5 + gid * 0.005), (0.1, 0.1, 0.1), 0.4))
    for index in range(32):
        gid = 128 + index
        result.append(gaussian(gid, (0.0, 0.0, 3.0 + index * 0.012), (0.35, 0.35, 0.15), 0.25))
    return result


def main():
    camera = Camera(96, 96, 72.0, 72.0, 47.5, 47.5)
    cases = {
        "sparse": (sparse_scene(), camera, RenderConfig(block_size=8, group_size=16)),
        "dense_overlap": (
            dense_overlap_scene(), camera, RenderConfig(block_size=8, group_size=16, transmittance_threshold=1.0e-20)
        ),
        "heavy_occlusion": (occlusion_scene(), camera, RenderConfig(block_size=8, group_size=16)),
        "single_block_hotspot": (
            single_block_hotspot_scene(),
            Camera(8, 8, 24.0, 24.0, 3.5, 3.5),
            RenderConfig(block_size=8, group_size=16, transmittance_threshold=1.0e-20),
        ),
    }
    output = {
        "metadata": {
            "date": "2026-08-03",
            "status": "uncalibrated R1 scheduling study; area credits are provisional",
            "resource_costs": {"projection": 2, "sort": 1, "paired_raster": 2},
            "area_budget_credits": 12,
            "warning": "results do not establish area-fair hardware speedup before RTL synthesis",
        },
        "workloads": {},
        "heterogeneous_scheduler_test": {},
    }

    for name, (scene, scene_camera, render) in cases.items():
        b0 = simulate_b0(
            scene,
            scene_camera,
            render,
            B0Config(
                frequency_hz=500e6,
                scoreboard=ScoreboardConfig(
                    alpha_arrays=4, blend_arrays=2, alpha_latency=14, blend_latency=4, result_queue_depth=24
                ),
            ),
        )
        r0 = simulate_r0(scene, scene_camera, render, R0Config(policy="dynamic"))
        fixed = {}
        for mode in R1Config().modes:
            report = simulate_r1(scene, scene_camera, render, R1Config(policy="fixed", fixed_mode=mode.name))
            fixed[mode.name] = report.total_cycles
        r1 = simulate_r1(scene, scene_camera, render, R1Config(policy="dynamic"))
        best_name, best_cycles = min(fixed.items(), key=lambda item: item[1])
        output["workloads"][name] = {
            "b0_cycles": b0.total_cycles,
            "r0_cycles": r0.total_cycles,
            "r1_fixed_cycles": fixed,
            "r1_best_static_mode": best_name,
            "r1_best_static_cycles": best_cycles,
            "r1_dynamic_cycles": r1.total_cycles,
            "r1_modes": r1.selected_modes,
            "r1_reconfigurations": r1.reconfigurations,
            "r1_vs_b0_ratio": r1.total_cycles / b0.total_cycles,
            "r1_vs_r0_ratio": r1.total_cycles / r0.total_cycles,
            "dynamic_vs_best_static_ratio": r1.total_cycles / best_cycles,
            "task_graph_equal": r1.block_tasks == b0.block_tasks and r1.sorted_ids == b0.sorted_ids,
        }

    scene = heterogeneous_phase_scene()
    render = RenderConfig(block_size=8, group_size=16, transmittance_threshold=1.0e-20)
    fixed = {
        mode.name: simulate_r1(scene, camera, render, R1Config(policy="fixed", fixed_mode=mode.name)).total_cycles
        for mode in R1Config().modes
    }
    output["heterogeneous_scheduler_test"]["fixed"] = fixed
    for cost in (0, 4, 12, 24, 48):
        report = simulate_r1(scene, camera, render, R1Config(policy="dynamic", reconfiguration_cycles=cost))
        output["heterogeneous_scheduler_test"][str(cost)] = {
            "total_cycles": report.total_cycles,
            "modes": report.selected_modes,
            "reconfigurations": report.reconfigurations,
            "charged_cycles": report.reconfiguration_cycles,
            "epochs": [
                {
                    "group_start": epoch.group_index,
                    "group_end": epoch.group_end_index,
                    "mode": epoch.mode,
                    "input_gaussians": epoch.input_gaussians,
                    "projected_gaussians": epoch.projected_gaussians,
                    "block_tasks": epoch.block_tasks,
                }
                for epoch in report.epochs
            ],
        }

    path = ROOT / "experiments" / "r1_synthetic_sweep.json"
    path.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    for name, result in output["workloads"].items():
        print(name, result)
    print("heterogeneous_scheduler_test", output["heterogeneous_scheduler_test"])
    print(path)


if __name__ == "__main__":
    main()
