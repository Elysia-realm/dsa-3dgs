from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.io import discover_scenes, iter_gaussian_batches, read_cameras
from model.reference.math3d import sh_basis


def quantiles(values):
    q = (0.0, 0.0001, 0.01, 0.5, 0.99, 0.9999, 1.0)
    return {str(key): float(value) for key, value in zip(q, np.quantile(values, q))}


def main():
    report = {"metadata": {"source": "local D:/3DGS/data only", "sample_per_scene": 100000}, "scenes": {}}
    all_abs_coeff = []
    all_abs_basis = []
    all_color = []
    for scene in discover_scenes(ROOT / "data"):
        cameras = read_cameras(scene.cameras_json)
        camera = cameras[len(cameras) // 2]
        coeff_parts = []
        basis_parts = []
        color_parts = []
        remaining = 100000
        for batch in iter_gaussian_batches(scene.final_ply, batch_size=min(remaining, 100000), include_sh=True):
            take = min(remaining, len(batch.mean))
            mean = batch.mean[:take]
            sh = batch.sh[:take]
            direction = mean - camera.position_world[None, :]
            norm = np.linalg.norm(direction, axis=1, keepdims=True)
            direction = direction / np.maximum(norm, np.float32(1e-12))
            basis = np.stack([sh_basis(item, sh.shape[2]) for item in direction])
            color = np.einsum("nci,ni->nc", sh, basis) + np.float32(0.5)
            coeff_parts.append(np.abs(sh).reshape(-1))
            basis_parts.append(np.abs(basis).reshape(-1))
            color_parts.append(color.reshape(-1))
            remaining -= take
            if remaining == 0:
                break
        coeff = np.concatenate(coeff_parts)
        basis = np.concatenate(basis_parts)
        color = np.concatenate(color_parts)
        report["scenes"][scene.name] = {
            "abs_coefficient": quantiles(coeff),
            "abs_basis": quantiles(basis),
            "preclip_color": quantiles(color),
        }
        all_abs_coeff.append(coeff)
        all_abs_basis.append(basis)
        all_color.append(color)
        print(scene.name, float(coeff.max()), float(basis.max()), float(color.min()), float(color.max()))
    report["aggregate"] = {
        "abs_coefficient": quantiles(np.concatenate(all_abs_coeff)),
        "abs_basis": quantiles(np.concatenate(all_abs_basis)),
        "preclip_color": quantiles(np.concatenate(all_color)),
    }
    output = ROOT / "experiments" / "sh_fixed_format_profile.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
