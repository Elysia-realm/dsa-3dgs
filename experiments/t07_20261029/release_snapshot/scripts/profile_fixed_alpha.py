from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, replace
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.fixed import AlphaFixedConfig, alpha_fixed, alpha_fixed_cholesky_block_float, alpha_fixed_cholesky_shared_scale, alpha_fixed_shared_scale, alpha_float, cholesky_factors
from model.io import discover_scenes, read_cameras, scaled_camera
from scripts.profile_exact_raster_rois import collect_projected, roi_from_anchor, subset_projected


REPRESENTATIVES = {"garden": 184, "train": 150, "bonsai": 291}
ANCHORS = ((0.25, 0.25), (0.50, 0.50), (0.75, 0.75))


def collect_samples(projected, roi, rng, limit):
    if not projected:
        return None
    rx0, ry0, rx1, ry1 = roi
    lengths = (projected["x1"] - projected["x0"]) * (projected["y1"] - projected["y0"])
    total = int(np.sum(lengths, dtype=np.int64))
    if total == 0:
        return None
    count = min(limit, total)
    flattened = rng.choice(total, size=count, replace=False)
    prefix = np.cumsum(lengths, dtype=np.int64)
    item = np.searchsorted(prefix, flattened, side="right")
    offset = flattened - np.where(item == 0, 0, prefix[item - 1])
    widths = projected["x1"][item] - projected["x0"][item]
    x = projected["x0"][item] + offset % widths
    y = projected["y0"][item] + offset // widths
    extent = np.maximum(
        np.maximum(np.abs(projected["screen_x0"][item] - projected["mean_x"][item]), np.abs((projected["screen_x1"][item] - 1) - projected["mean_x"][item])),
        np.maximum(np.abs(projected["screen_y0"][item] - projected["mean_y"][item]), np.abs((projected["screen_y1"][item] - 1) - projected["mean_y"][item])),
    )
    l00, l10, l11 = cholesky_factors(
        projected["conic00"][item], projected["conic01"][item], projected["conic11"][item]
    )
    factor_extent = np.maximum.reduce((np.abs(l00), np.abs(l10), np.abs(l11)))
    return {
        "dx": x.astype(np.float64) - projected["mean_x"][item],
        "dy": y.astype(np.float64) - projected["mean_y"][item],
        "conic00": projected["conic00"][item].astype(np.float64),
        "conic01": projected["conic01"][item].astype(np.float64),
        "conic11": projected["conic11"][item].astype(np.float64),
        "opacity": projected["opacity"][item].astype(np.float64),
        "scale_shift": np.maximum(0, np.ceil(np.log2(np.maximum(1.0, extent) / 16.0))).astype(np.int64),
        "factor_shift": np.ceil(np.log2(np.maximum(factor_extent, 2.0 ** -30) / 4.0)).astype(np.int64),
    }


def evaluate(samples, config):
    arguments = [samples[name] for name in ("dx", "dy", "conic00", "conic01", "conic11", "opacity")]
    reference = alpha_float(*arguments, alpha_max=config.alpha_max)
    candidate = alpha_fixed(*arguments, config=config, apply_threshold=False)
    error = np.abs(reference - candidate)
    ref_pass = reference >= config.alpha_threshold
    threshold_code = int(round(config.alpha_threshold * (1 << config.alpha_fractional_bits)))
    effective_threshold = threshold_code / (1 << config.alpha_fractional_bits)
    fixed_pass = candidate >= effective_threshold
    return {
        "config": asdict(config),
        "mean_abs_error": float(np.mean(error)),
        "p50_abs_error": float(np.quantile(error, 0.50)),
        "p90_abs_error": float(np.quantile(error, 0.90)),
        "p99_abs_error": float(np.quantile(error, 0.99)),
        "max_abs_error": float(np.max(error)),
        "threshold_classification_mismatch_rate": float(np.mean(ref_pass != fixed_pass)),
        "false_prune_rate": float(np.mean(ref_pass & ~fixed_pass)),
        "false_blend_rate": float(np.mean(~ref_pass & fixed_pass)),
        "threshold_code": threshold_code,
        "effective_threshold": effective_threshold,
    }


def evaluate_shared_scale(samples, config):
    arguments = [samples[name] for name in ("dx", "dy", "conic00", "conic01", "conic11", "opacity")]
    reference = alpha_float(*arguments, alpha_max=config.alpha_max)
    candidate = alpha_fixed_shared_scale(*arguments, samples["scale_shift"], config=config, apply_threshold=False)
    error = np.abs(reference - candidate)
    ref_pass = reference >= config.alpha_threshold
    threshold_code = int(round(config.alpha_threshold * (1 << config.alpha_fractional_bits)))
    effective_threshold = threshold_code / (1 << config.alpha_fractional_bits)
    fixed_pass = candidate >= effective_threshold
    return {
        "config": asdict(config),
        "scale": "per-Gaussian power-of-two coordinate/conic shared shift",
        "mean_abs_error": float(np.mean(error)),
        "p50_abs_error": float(np.quantile(error, 0.50)),
        "p90_abs_error": float(np.quantile(error, 0.90)),
        "p99_abs_error": float(np.quantile(error, 0.99)),
        "max_abs_error": float(np.max(error)),
        "threshold_classification_mismatch_rate": float(np.mean(ref_pass != fixed_pass)),
        "false_prune_rate": float(np.mean(ref_pass & ~fixed_pass)),
        "false_blend_rate": float(np.mean(~ref_pass & fixed_pass)),
        "threshold_code": threshold_code,
        "effective_threshold": effective_threshold,
    }


def evaluate_cholesky(samples, config, factor_integer_bits, factor_fractional_bits):
    arguments = [samples[name] for name in ("dx", "dy", "conic00", "conic01", "conic11", "opacity")]
    reference = alpha_float(*arguments, alpha_max=config.alpha_max)
    candidate = alpha_fixed_cholesky_shared_scale(
        *arguments, samples["scale_shift"], config=config,
        factor_integer_bits=factor_integer_bits,
        factor_fractional_bits=factor_fractional_bits, apply_threshold=False,
    )
    error = np.abs(reference - candidate)
    ref_pass = reference >= config.alpha_threshold
    threshold_code = int(round(config.alpha_threshold * (1 << config.alpha_fractional_bits)))
    effective_threshold = threshold_code / (1 << config.alpha_fractional_bits)
    fixed_pass = candidate >= effective_threshold
    l00, l10, l11 = cholesky_factors(samples["conic00"], samples["conic01"], samples["conic11"])
    factor_scale = np.exp2(samples["scale_shift"])
    factor_limit = (1 << factor_integer_bits) - 1.0 / (1 << factor_fractional_bits)
    scaled_abs = np.maximum.reduce((np.abs(l00 * factor_scale), np.abs(l10 * factor_scale), np.abs(l11 * factor_scale)))
    return {
        "config": asdict(config),
        "factor_integer_bits": factor_integer_bits,
        "factor_fractional_bits": factor_fractional_bits,
        "scale": "per-Gaussian power-of-two coordinate/Cholesky shared shift",
        "mean_abs_error": float(np.mean(error)),
        "p50_abs_error": float(np.quantile(error, 0.50)),
        "p90_abs_error": float(np.quantile(error, 0.90)),
        "p99_abs_error": float(np.quantile(error, 0.99)),
        "max_abs_error": float(np.max(error)),
        "threshold_classification_mismatch_rate": float(np.mean(ref_pass != fixed_pass)),
        "false_prune_rate": float(np.mean(ref_pass & ~fixed_pass)),
        "false_blend_rate": float(np.mean(~ref_pass & fixed_pass)),
        "threshold_code": threshold_code,
        "effective_threshold": effective_threshold,
        "factor_saturation_rate": float(np.mean(scaled_abs > factor_limit)),
        "factor_scaled_p99": float(np.quantile(scaled_abs, 0.99)),
        "factor_scaled_max": float(np.max(scaled_abs)),
    }


def evaluate_block_float(samples, config, factor_fractional_bits, axis_fractional_bits):
    arguments = [samples[name] for name in ("dx", "dy", "conic00", "conic01", "conic11", "opacity")]
    reference = alpha_float(*arguments, alpha_max=config.alpha_max)
    candidate = alpha_fixed_cholesky_block_float(
        *arguments, samples["scale_shift"], samples["factor_shift"],
        config=config, factor_fractional_bits=factor_fractional_bits,
        axis_fractional_bits=axis_fractional_bits, apply_threshold=False,
    )
    error = np.abs(reference - candidate)
    ref_pass = reference >= config.alpha_threshold
    threshold_code = int(round(config.alpha_threshold * (1 << config.alpha_fractional_bits)))
    effective_threshold = threshold_code / (1 << config.alpha_fractional_bits)
    fixed_pass = candidate >= effective_threshold
    return {
        "config": asdict(config),
        "factor_integer_bits": 3,
        "factor_fractional_bits": factor_fractional_bits,
        "axis_integer_bits": 4,
        "axis_fractional_bits": axis_fractional_bits,
        "scale": "independent per-Gaussian coordinate/factor exponents",
        "mean_abs_error": float(np.mean(error)),
        "p50_abs_error": float(np.quantile(error, 0.50)),
        "p90_abs_error": float(np.quantile(error, 0.90)),
        "p99_abs_error": float(np.quantile(error, 0.99)),
        "max_abs_error": float(np.max(error)),
        "threshold_classification_mismatch_rate": float(np.mean(ref_pass != fixed_pass)),
        "false_prune_rate": float(np.mean(ref_pass & ~fixed_pass)),
        "false_blend_rate": float(np.mean(~ref_pass & fixed_pass)),
        "threshold_code": threshold_code,
        "effective_threshold": effective_threshold,
    }


def main():
    parser = argparse.ArgumentParser(description="Sweep fixed-point alpha formats on local real 3DGS ROI samples")
    parser.add_argument("--max-dimension", type=int, default=960)
    parser.add_argument("--roi-size", type=int, default=64)
    parser.add_argument("--samples-per-roi", type=int, default=100000)
    parser.add_argument("--seed", type=int, default=20260804)
    parser.add_argument("--output", type=Path, default=ROOT / "experiments" / "fixed_alpha_sweep.json")
    args = parser.parse_args()

    rng = np.random.default_rng(args.seed)
    scenes = {scene.name: scene for scene in discover_scenes(ROOT / "data")}
    parts = []
    source_summary = []
    for scene_name, camera_index in REPRESENTATIVES.items():
        scene = scenes[scene_name]
        camera = scaled_camera(read_cameras(scene.cameras_json)[camera_index], args.max_dimension)
        rois = [roi_from_anchor(camera, args.roi_size, anchor) for anchor in ANCHORS]
        union = (min(v[0] for v in rois), min(v[1] for v in rois), max(v[2] for v in rois), max(v[3] for v in rois))
        union_projected = collect_projected(scene, camera, union)
        for anchor, roi in zip(ANCHORS, rois):
            projected = subset_projected(union_projected, roi)
            sample = collect_samples(projected, roi, rng, args.samples_per_roi)
            if sample is None:
                continue
            parts.append(sample)
            source_summary.append({"scene": scene_name, "camera_index": camera_index, "anchor": list(anchor), "roi": list(roi), "sample_count": len(sample["dx"])})

    samples = {name: np.concatenate([part[name] for part in parts]) for name in parts[0]}
    base = AlphaFixedConfig()
    configs = [("baseline_q5_12", base)]
    configs += [(f"delta_int_{bits}", replace(base, delta_integer_bits=bits)) for bits in (7, 9, 11)]
    configs += [(f"lut_{entries}", replace(base, exp_lut_entries=entries)) for entries in (128, 512)]
    configs += [(f"alpha_frac_{bits}", replace(base, alpha_fractional_bits=bits)) for bits in (10, 14)]
    configs += [(f"conic_frac_{bits}", replace(base, conic_fractional_bits=bits)) for bits in (10, 14)]
    configs += [
        ("wide_q18_c18", replace(base, delta_integer_bits=18, conic_fractional_bits=18)),
        ("wide_q18_c20", replace(base, delta_integer_bits=18, conic_fractional_bits=20)),
        ("wide_q18_c24", replace(base, delta_integer_bits=18, conic_fractional_bits=24)),
    ]
    report = {
        "metadata": {
            "date": "2026-08-04",
            "method": "uniform without-replacement sampling of exact projected Gaussian/pixel pairs from nine real 64x64 ROIs",
            "seed": args.seed,
            "total_samples": len(samples["dx"]),
            "threshold": base.alpha_threshold,
            "sample_distributions": {
                "abs_dx_p99": float(np.quantile(np.abs(samples["dx"]), 0.99)),
                "abs_dx_max": float(np.max(np.abs(samples["dx"]))),
                "abs_dy_p99": float(np.quantile(np.abs(samples["dy"]), 0.99)),
                "abs_dy_max": float(np.max(np.abs(samples["dy"]))),
                "conic_abs_max": float(max(np.max(np.abs(samples[name])) for name in ("conic00", "conic01", "conic11"))),
            },
            "sources": source_summary,
        },
        "formats": {name: evaluate(samples, config) for name, config in configs},
    }
    report["formats"]["shared_scale_q5_c12"] = evaluate_shared_scale(samples, base)
    report["formats"]["shared_scale_q5_c16"] = evaluate_shared_scale(samples, replace(base, conic_fractional_bits=16))
    for factor_integer_bits in (3, 4, 5, 6, 8):
        for factor_fractional_bits in (8, 10, 12, 14):
            for lut_entries in (128, 256, 512):
                name = f"cholesky_i{factor_integer_bits}_f{factor_fractional_bits}_lut{lut_entries}"
                report["formats"][name] = evaluate_cholesky(
                    samples, replace(base, exp_lut_entries=lut_entries),
                    factor_integer_bits, factor_fractional_bits,
                )
    for factor_fractional_bits in (8, 10, 12, 14):
        for axis_fractional_bits in (10, 12, 14):
            for lut_entries in (128, 256, 512):
                name = f"block_float_f{factor_fractional_bits}_a{axis_fractional_bits}_lut{lut_entries}"
                report["formats"][name] = evaluate_block_float(
                    samples, replace(base, exp_lut_entries=lut_entries),
                    factor_fractional_bits, axis_fractional_bits,
                )
    best = min(report["formats"], key=lambda name: (report["formats"][name]["p99_abs_error"], report["formats"][name]["threshold_classification_mismatch_rate"]))
    report["best_by_p99_error"] = best
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"output": str(args.output), "samples": len(samples["dx"]), "best": best, "baseline": report["formats"]["baseline_q5_12"]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
