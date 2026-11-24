from __future__ import annotations

import json
import sys
from dataclasses import asdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.cycle import B0Config, ScoreboardConfig, simulate_b0
from model.reference import Camera, Gaussian3D, RenderConfig


def gaussian(gid, mean, scale, opacity):
    return Gaussian3D(
        gid=gid,
        mean=np.asarray(mean, dtype=np.float32),
        scale=np.asarray(scale, dtype=np.float32),
        quaternion=np.asarray((1.0, 0.0, 0.0, 0.0), dtype=np.float32),
        opacity=float(opacity),
        rgb=np.asarray((0.4, 0.6, 0.2), dtype=np.float32),
    )


def sparse_scene():
    items = []
    gid = 0
    # Put each tiny Gaussian well inside a distinct 8x8 block. This isolates
    # pipeline/queue cost from per-block ordering dependencies.
    for row in range(4):
        for col in range(5):
            z = 2.5 + 0.03 * gid
            px = 4 + 16 * col
            py = 4 + 24 * row
            x = (px - 47.5) * z / 72.0
            y = (py - 47.5) * z / 72.0
            items.append(gaussian(gid, (x, y, z), (0.01, 0.01, 0.01), 0.45))
            gid += 1
    return items


def dense_overlap_scene():
    return [
        gaussian(gid, (0.03 * ((gid % 3) - 1), 0.03 * (((gid // 3) % 3) - 1), 2.0 + 0.018 * gid), (0.32, 0.32, 0.12), 0.32)
        for gid in range(72)
    ]


def occlusion_scene():
    return [gaussian(gid, (0.0, 0.0, 1.5 + 0.012 * gid), (0.58, 0.58, 0.18), 1.0) for gid in range(96)]


def single_block_hotspot_scene():
    return [gaussian(gid, (0.0, 0.0, 2.0 + 0.015 * gid), (0.06, 0.06, 0.04), 0.25) for gid in range(64)]


def summarize(report):
    return {
        "total_cycles": report.total_cycles,
        "input_gaussians": report.input_gaussians,
        "projected_gaussians": report.projected_gaussians,
        "candidate_blocks": report.raster_trace.candidate_blocks,
        "issued_blocks": report.raster_trace.issued_blocks,
        "skipped_terminated_blocks": report.raster_trace.skipped_terminated_blocks,
        "skip_ratio": report.raster_trace.skipped_terminated_blocks / max(1, report.raster_trace.candidate_blocks),
        "scoreboard_stall_cycles": report.raster.scoreboard_stall_cycles,
        "scoreboard_overhead_cycles": report.scoreboard_overhead_cycles,
        "result_queue_stall_cycles": report.raster.result_queue_stall_cycles,
        "alpha_utilization": report.raster.alpha_utilization,
        "blend_utilization": report.raster.blend_utilization,
        "dram_read_bytes": report.traffic.dram_read_bytes,
        "dram_write_bytes": report.traffic.dram_write_bytes,
        "sram_traffic_bytes": report.traffic.sram_read_bytes + report.traffic.sram_write_bytes,
        "active_pixel_tests": report.raster_trace.active_pixel_tests,
        "blend_updates": report.raster_trace.blend_updates,
        "terminated_pixels": report.raster_trace.terminated_pixels,
    }


def main():
    camera = Camera(96, 96, 72.0, 72.0, 47.5, 47.5)
    architecture_base = dict(
        frequency_hz=500e6,
        scoreboard=ScoreboardConfig(alpha_arrays=4, blend_arrays=2, alpha_latency=4, blend_latency=8, result_queue_depth=16),
    )
    workloads = {
        "sparse": (sparse_scene(), RenderConfig(block_size=8, group_size=16)),
        "dense_overlap": (dense_overlap_scene(), RenderConfig(block_size=8, group_size=16, transmittance_threshold=1.0e-20)),
        "heavy_occlusion": (occlusion_scene(), RenderConfig(block_size=8, group_size=16)),
    }
    results = {"metadata": {
        "date": "2026-08-03",
        "status": "uncalibrated analytical model; use for relative comparison only",
        "camera": "96x96 synthetic",
        "frequency_assumption_hz": 500_000_000,
    }, "workloads": {}, "early_termination_comparison": {}, "queue_depth_sensitivity": {}}

    for name, (scene, render) in workloads.items():
        results["workloads"][name] = summarize(simulate_b0(scene, camera, render, B0Config(**architecture_base)))

    hotspot_camera = Camera(8, 8, 24.0, 24.0, 3.5, 3.5)
    hotspot_architecture = B0Config(
        frequency_hz=500e6,
        scoreboard=ScoreboardConfig(alpha_arrays=4, blend_arrays=4, alpha_latency=2, blend_latency=8, result_queue_depth=16),
    )
    results["workloads"]["single_block_hotspot"] = summarize(
        simulate_b0(
            single_block_hotspot_scene(),
            hotspot_camera,
            RenderConfig(block_size=8, group_size=16, transmittance_threshold=1.0e-20),
            hotspot_architecture,
        )
    )

    occlusion, enabled_render = workloads["heavy_occlusion"]
    disabled_render = RenderConfig(
        block_size=enabled_render.block_size,
        group_size=enabled_render.group_size,
        transmittance_threshold=1.0e-30,
    )
    enabled_summary = results["workloads"]["heavy_occlusion"]
    disabled_summary = summarize(simulate_b0(occlusion, camera, disabled_render, B0Config(**architecture_base)))
    results["early_termination_comparison"] = {
        "enabled": enabled_summary,
        "disabled": disabled_summary,
        "cycle_reduction_ratio": 1.0 - enabled_summary["total_cycles"] / disabled_summary["total_cycles"],
        "issued_block_reduction_ratio": 1.0 - enabled_summary["issued_blocks"] / disabled_summary["issued_blocks"],
        "sram_traffic_reduction_ratio": 1.0 - enabled_summary["sram_traffic_bytes"] / disabled_summary["sram_traffic_bytes"],
    }

    scene, render = workloads["dense_overlap"]
    for depth in (4, 8, 16, 32, 64):
        architecture = B0Config(
            frequency_hz=500e6,
            scoreboard=ScoreboardConfig(alpha_arrays=4, blend_arrays=2, alpha_latency=4, blend_latency=8, result_queue_depth=depth),
        )
        results["queue_depth_sensitivity"][str(depth)] = summarize(simulate_b0(scene, camera, render, architecture))

    output = ROOT / "experiments" / "b0_workload_sweep.json"
    output.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    for name, values in results["workloads"].items():
        print(name, values)
    print("queue_depth_sensitivity", {key: value["total_cycles"] for key, value in results["queue_depth_sensitivity"].items()})
    print("early_termination_savings", {
        key: results["early_termination_comparison"][key]
        for key in ("cycle_reduction_ratio", "issued_block_reduction_ratio", "sram_traffic_reduction_ratio")
    })
    print(output)


if __name__ == "__main__":
    main()
