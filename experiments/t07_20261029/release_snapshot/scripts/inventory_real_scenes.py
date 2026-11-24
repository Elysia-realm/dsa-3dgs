from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.io import discover_scenes, open_ply_vertices, read_cameras


def quantiles(value):
    return {str(q): float(v) for q, v in zip((0.0, 0.01, 0.5, 0.99, 1.0), np.quantile(value, (0.0, 0.01, 0.5, 0.99, 1.0)))}


def sigmoid(value):
    value = np.asarray(value, dtype=np.float64)
    return np.where(value >= 0, 1.0 / (1.0 + np.exp(-value)), np.exp(value) / (1.0 + np.exp(value)))


def main():
    scenes = discover_scenes(ROOT / "data")
    report = {
        "metadata": {
            "date": "2026-08-04",
            "source": "local D:/3DGS/data only",
            "final_iteration": 30000,
            "sample_limit_per_scene": 200000,
            "transform": "opacity=sigmoid(raw), scale=exp(raw), quaternion=normalized during full import",
        },
        "scenes": {},
    }
    total_final = 0
    for scene in scenes:
        final_header, vertices = open_ply_vertices(scene.final_ply)
        early_count = open_ply_vertices(scene.early_ply)[0].vertex_count if scene.early_ply else None
        cameras = read_cameras(scene.cameras_json)
        count = final_header.vertex_count
        indices = np.linspace(0, count - 1, min(count, 200000), dtype=np.int64)
        sample = vertices[indices]
        mean = np.column_stack((sample["x"], sample["y"], sample["z"])).astype(np.float64)
        scale = np.exp(np.column_stack((sample["scale_0"], sample["scale_1"], sample["scale_2"])).astype(np.float64))
        opacity = sigmoid(sample["opacity"])
        resolutions = np.asarray([(camera.width, camera.height) for camera in cameras], dtype=np.int64)
        focals = np.asarray([(camera.fx, camera.fy) for camera in cameras], dtype=np.float64)
        report["scenes"][scene.name] = {
            "final_gaussians": count,
            "iteration_7000_gaussians": early_count,
            "growth_ratio_30000_over_7000": count / early_count if early_count else None,
            "final_ply_bytes": scene.final_ply.stat().st_size,
            "properties": list(final_header.dtype.names or ()),
            "sh_coefficients_per_channel": 16,
            "camera_count": len(cameras),
            "resolution_min": resolutions.min(axis=0).tolist(),
            "resolution_max": resolutions.max(axis=0).tolist(),
            "focal_quantiles": {
                "fx": quantiles(focals[:, 0]),
                "fy": quantiles(focals[:, 1]),
            },
            "sampled_attribute_stats": {
                "mean_min": mean.min(axis=0).tolist(),
                "mean_max": mean.max(axis=0).tolist(),
                "opacity": quantiles(opacity),
                "scale_min_axis": scale.min(axis=0).tolist(),
                "scale_median_axis": np.median(scale, axis=0).tolist(),
                "scale_max_axis": scale.max(axis=0).tolist(),
            },
        }
        total_final += count
        print(scene.name, count, len(cameras), resolutions.min(axis=0), resolutions.max(axis=0))
    report["metadata"]["scene_count"] = len(scenes)
    report["metadata"]["total_final_gaussians"] = total_final
    output = ROOT / "experiments" / "real_scene_inventory.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("total_final_gaussians", total_final)
    print(output)


if __name__ == "__main__":
    main()
