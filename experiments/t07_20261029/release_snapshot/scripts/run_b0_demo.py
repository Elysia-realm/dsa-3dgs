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


def scene(count=160):
    rng = np.random.default_rng(20260803)
    result = []
    for gid in range(count):
        angle = rng.uniform(0.0, 2.0 * np.pi)
        radius = rng.uniform(0.0, 0.75)
        mean = (radius * np.cos(angle), radius * np.sin(angle) * 0.7, rng.uniform(1.8, 7.0))
        scale = rng.uniform(0.05, 0.24, size=3)
        opacity = float(rng.uniform(0.08, 0.95))
        color = rng.uniform(0.0, 1.0, size=3)
        result.append(
            Gaussian3D(
                gid=gid,
                mean=np.asarray(mean, dtype=np.float32),
                scale=np.asarray(scale, dtype=np.float32),
                quaternion=np.asarray((1, 0, 0, 0), dtype=np.float32),
                opacity=opacity,
                rgb=np.asarray(color, dtype=np.float32),
            )
        )
    return result


def main():
    camera = Camera(128, 128, 96.0, 96.0, 63.5, 63.5)
    render = RenderConfig(block_size=8, group_size=32)
    architecture = B0Config(
        frequency_hz=500e6,
        scoreboard=ScoreboardConfig(
            alpha_arrays=4, blend_arrays=4, alpha_latency=14, blend_latency=4, result_queue_depth=32
        ),
    )
    report = simulate_b0(scene(), camera, render, architecture)
    output = ROOT / "experiments" / "b0_synthetic_demo.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(asdict(report), ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"total_cycles={report.total_cycles}")
    print(f"fps_assumption={report.fps:.2f}")
    print(f"groups={report.group_sizes_before_projection}")
    print(f"block_tasks={report.block_tasks}")
    print(f"candidate_blocks={report.raster_trace.candidate_blocks}")
    print(f"skipped_terminated_blocks={report.raster_trace.skipped_terminated_blocks}")
    print(f"terminated_pixels={report.raster_trace.terminated_pixels}")
    print(f"scoreboard_stall_cycles={report.raster.scoreboard_stall_cycles}")
    print(f"scoreboard_overhead_cycles={report.scoreboard_overhead_cycles}")
    print(f"dram_read_bytes={report.traffic.dram_read_bytes}")
    print(f"sram_traffic_bytes={report.traffic.sram_read_bytes + report.traffic.sram_write_bytes}")
    print(output)


if __name__ == "__main__":
    main()
