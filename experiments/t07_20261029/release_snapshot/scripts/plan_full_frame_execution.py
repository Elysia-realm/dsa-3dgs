from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import asdict, dataclass
from datetime import date
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.io import discover_scenes, iter_gaussian_batches, read_cameras, scaled_camera


COORD_MAX = ((1 << 26) - 1) / float(1 << 16)
COORD_MIN = -(1 << 26) / float(1 << 16)
SCALE_MAX = ((1 << 24) - 1) / float(1 << 20)
SH_MAX = ((1 << 17) - 1) / float(1 << 12)
SH_MIN = -(1 << 17) / float(1 << 12)


@dataclass(frozen=True)
class CapacityPlan:
    group_capacity: int
    conservative_gaussians_per_batch: int
    optimistic_gaussians_per_batch: int
    conservative_batch_count: int
    optimistic_batch_count: int
    sequence_bits_required_conservative: int
    sequence_bits_required_optimistic: int


def required_bits(maximum_value: int) -> int:
    """Bits required to encode values in [0, maximum_value]."""
    if maximum_value < 0:
        raise ValueError("maximum_value must be non-negative")
    return max(1, int(maximum_value).bit_length())


def capacity_plan(eligible_gaussians: int, group_capacity: int, groups: int = 4) -> CapacityPlan:
    if eligible_gaussians < 0:
        raise ValueError("eligible_gaussians must be non-negative")
    if group_capacity <= 0 or groups <= 0:
        raise ValueError("group_capacity and groups must be positive")
    conservative = group_capacity
    optimistic = group_capacity * groups
    return CapacityPlan(
        group_capacity=group_capacity,
        conservative_gaussians_per_batch=conservative,
        optimistic_gaussians_per_batch=optimistic,
        conservative_batch_count=math.ceil(eligible_gaussians / conservative),
        optimistic_batch_count=math.ceil(eligible_gaussians / optimistic),
        sequence_bits_required_conservative=required_bits(max(0, conservative - 1)),
        sequence_bits_required_optimistic=required_bits(max(0, optimistic - 1)),
    )


def _scene_report(scene, camera_index: int, max_dimension: int, scan_batch: int, capacities: list[int]) -> dict:
    cameras = read_cameras(scene.cameras_json)
    selected_camera = len(cameras) // 2 if camera_index < 0 else camera_index
    if not 0 <= selected_camera < len(cameras):
        raise IndexError(f"{scene.name}: camera index {selected_camera} out of range")
    camera = scaled_camera(cameras[selected_camera], max_dimension)

    total = depth_valid = fixed_representable = eligible = screen_center_candidate = 0
    sh_clipped_values = 0
    depth_min = math.inf
    depth_max = -math.inf
    rotation = camera.world_to_camera[:3, :3]
    translation = camera.world_to_camera[:3, 3]

    for batch in iter_gaussian_batches(scene.final_ply, batch_size=scan_batch, include_sh=True):
        total += batch.stop - batch.start
        camera_mean = batch.mean @ rotation.T + translation
        depth = camera_mean[:, 2]
        finite = np.isfinite(batch.mean).all(axis=1)
        finite &= np.isfinite(batch.scale).all(axis=1)
        finite &= np.isfinite(batch.opacity)
        valid_depth = finite & (depth >= 0.2) & (depth <= 1000.0)
        representable = finite
        representable &= np.all((batch.mean >= COORD_MIN) & (batch.mean <= COORD_MAX), axis=1)
        representable &= np.all((batch.scale >= 0.0) & (batch.scale <= SCALE_MAX), axis=1)
        accepted = valid_depth & representable
        depth_valid += int(np.count_nonzero(valid_depth))
        fixed_representable += int(np.count_nonzero(representable))
        eligible += int(np.count_nonzero(accepted))
        if np.any(accepted):
            accepted_depth = depth[accepted]
            depth_min = min(depth_min, float(accepted_depth.min()))
            depth_max = max(depth_max, float(accepted_depth.max()))
            safe_depth = accepted_depth
            accepted_camera = camera_mean[accepted]
            screen_x = camera.fx * accepted_camera[:, 0] / safe_depth + camera.cx
            screen_y = camera.fy * accepted_camera[:, 1] / safe_depth + camera.cy
            margin = 8.0
            center_candidate = (screen_x >= -margin) & (screen_x < camera.width + margin)
            center_candidate &= (screen_y >= -margin) & (screen_y < camera.height + margin)
            screen_center_candidate += int(np.count_nonzero(center_candidate))
        if batch.sh is not None:
            sh_clipped_values += int(np.count_nonzero((batch.sh < SH_MIN) | (batch.sh > SH_MAX)))

    return {
        "scene": scene.name,
        "camera_index": selected_camera,
        "camera_count": len(cameras),
        "resolution": [camera.width, camera.height],
        "source_gaussians": total,
        "depth_valid_gaussians": depth_valid,
        "fixed_representable_gaussians": fixed_representable,
        "execution_eligible_gaussians": eligible,
        "screen_center_candidate_gaussians_diagnostic_only": screen_center_candidate,
        "depth_range": None if not eligible else [depth_min, depth_max],
        "sh_values_requiring_saturation": sh_clipped_values,
        "gid_bits_required": required_bits(max(0, total - 1)),
        "mean_stream_bytes": eligible * 16,
        "dense_attribute_store_bytes": total * 144,
        "compacted_eligible_attribute_bytes": eligible * 144,
        "pixel_state_bytes": camera.width * camera.height * 16,
        "capacity_plans": [asdict(capacity_plan(eligible, value)) for value in capacities],
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Plan local full-frame depth-group batches without uploading scene data"
    )
    parser.add_argument("--scene", action="append", help="scene name; repeatable, default is all discovered scenes")
    parser.add_argument("--camera", type=int, default=-1, help="negative selects the middle camera")
    parser.add_argument("--max-dimension", type=int, default=64)
    parser.add_argument("--scan-batch", type=int, default=262_144)
    parser.add_argument("--group-capacity", action="append", type=int, default=[])
    parser.add_argument(
        "--output", type=Path, default=ROOT / "experiments" / "full_frame_execution_plan.json"
    )
    args = parser.parse_args()
    capacities = args.group_capacity or [8, 64, 256]
    if args.max_dimension <= 0 or args.scan_batch <= 0 or any(value <= 0 for value in capacities):
        parser.error("dimensions, scan batch and group capacities must be positive")
    scenes = discover_scenes(ROOT / "data")
    by_name = {scene.name: scene for scene in scenes}
    selected_names = args.scene or sorted(by_name)
    unknown = sorted(set(selected_names) - set(by_name))
    if unknown:
        parser.error(f"unknown scenes: {', '.join(unknown)}")

    reports = [
        _scene_report(by_name[name], args.camera, args.max_dimension, args.scan_batch, capacities)
        for name in selected_names
    ]
    output = {
        "report_version": 1,
        "date": date.today().isoformat(),
        "data_policy": "Local D:/3DGS filesystem only; no upload.",
        "main_dataflow": "depth groups -> ordered Gaussian issue -> Gaussian-internal 8x8 block traversal",
        "planning_contract": {
            "eligible": "near/far valid and representable by the frozen mean/scale fixed-point formats",
            "screen_center_count": "diagnostic only; never used to discard wide off-screen-centered Gaussians",
            "conservative_batch": "at most one group capacity; always prevents a group-buffer overflow",
            "optimistic_batch": "up to GROUPS*capacity only after a depth-pivot builder proves every group fits",
            "continuation_requirement": "successive batches must preserve epoch, image state and front-to-back order",
        },
        "groups": 4,
        "max_dimension": args.max_dimension,
        "scenes": reports,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print(args.output)
    for report in reports:
        plans = ", ".join(
            f"cap{item['group_capacity']}:{item['conservative_batch_count']} batches"
            for item in report["capacity_plans"]
        )
        print(f"{report['scene']}: eligible={report['execution_eligible_gaussians']} {plans}")


if __name__ == "__main__":
    main()
