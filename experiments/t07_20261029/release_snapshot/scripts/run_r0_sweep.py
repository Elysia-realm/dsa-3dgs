from __future__ import annotations

import json
import sys
from dataclasses import asdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.cycle import B0Config, R0Config, ScoreboardConfig, simulate_b0, simulate_r0
from model.reference import Camera, RenderConfig
from scripts.run_b0_workload_sweep import (
    dense_overlap_scene,
    occlusion_scene,
    single_block_hotspot_scene,
    sparse_scene,
)


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
            "status": "uncalibrated scheduling study; not an area-fair hardware claim",
            "r0_barrier": "full group drain before a mode change",
            "elastic_budget": "8 abstract equal-cost lanes; per-operation area and timing await RTL calibration",
        },
        "workloads": {},
        "switch_cost_ablation": {},
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
        fixed = {}
        for mode in R0Config().modes:
            report = simulate_r0(scene, scene_camera, render, R0Config(policy="fixed", fixed_mode=mode.name))
            fixed[mode.name] = {
                "total_cycles": report.total_cycles,
                "selected_modes": report.selected_modes,
                "reconfigurations": report.reconfigurations,
            }
        dynamic = simulate_r0(scene, scene_camera, render, R0Config(policy="dynamic"))
        best_static_name, best_static = min(fixed.items(), key=lambda item: item[1]["total_cycles"])
        output["workloads"][name] = {
            "b0_total_cycles": b0.total_cycles,
            "r0_fixed": fixed,
            "r0_best_static_mode": best_static_name,
            "r0_best_static_cycles": best_static["total_cycles"],
            "r0_dynamic_cycles": dynamic.total_cycles,
            "r0_dynamic_modes": dynamic.selected_modes,
            "r0_reconfigurations": dynamic.reconfigurations,
            "r0_reconfiguration_cycles": dynamic.reconfiguration_cycles,
            "dynamic_vs_best_static_ratio": dynamic.total_cycles / best_static["total_cycles"],
            "dynamic_vs_b0_ratio": dynamic.total_cycles / b0.total_cycles,
            "task_graph_equal": dynamic.block_tasks == b0.block_tasks and dynamic.sorted_ids == b0.sorted_ids,
        }

    scene, scene_camera, render = cases["heavy_occlusion"]
    for cost in (0, 4, 8, 12, 24, 48):
        report = simulate_r0(
            scene, scene_camera, render, R0Config(policy="dynamic", reconfiguration_cycles=cost)
        )
        output["switch_cost_ablation"][str(cost)] = {
            "total_cycles": report.total_cycles,
            "modes": report.selected_modes,
            "reconfigurations": report.reconfigurations,
            "charged_cycles": report.reconfiguration_cycles,
        }

    path = ROOT / "experiments" / "r0_synthetic_sweep.json"
    path.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    for name, result in output["workloads"].items():
        print(name, {key: result[key] for key in (
            "b0_total_cycles", "r0_best_static_mode", "r0_best_static_cycles", "r0_dynamic_cycles",
            "r0_dynamic_modes", "r0_reconfigurations", "dynamic_vs_best_static_ratio", "dynamic_vs_b0_ratio",
        )})
    print("switch_cost_ablation", output["switch_cost_ablation"])
    print(path)


if __name__ == "__main__":
    main()
