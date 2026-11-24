from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.fixed import image_metrics, lpips_status


def read_image(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def main():
    parser = argparse.ArgumentParser(description="Local PSNR/SSIM/LPIPS image-pair evaluator")
    parser.add_argument("reference", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--pattern", default="*.png")
    parser.add_argument("--lpips", action="store_true", help="require and run a prepared local torch/lpips runtime")
    parser.add_argument("--lpips-net", default="alex")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--output", type=Path, default=ROOT / "experiments" / "image_quality_metrics.json")
    args = parser.parse_args()
    if args.lpips and not lpips_status()["available"]:
        raise SystemExit("LPIPS requested, but the local runtime lacks torch/lpips and weights")

    references = {path.relative_to(args.reference): path for path in args.reference.rglob(args.pattern)}
    candidates = {path.relative_to(args.candidate): path for path in args.candidate.rglob(args.pattern)}
    common = sorted(references.keys() & candidates.keys())
    if not common:
        raise SystemExit("no identically named image pairs found")
    missing_candidate = sorted(str(path) for path in references.keys() - candidates.keys())
    missing_reference = sorted(str(path) for path in candidates.keys() - references.keys())
    results = []
    for relative in common:
        metrics = image_metrics(read_image(references[relative]), read_image(candidates[relative]), compute_lpips=args.lpips, lpips_net=args.lpips_net, device=args.device)
        metrics.pop("lpips_status")
        results.append({"image": str(relative), **metrics})
    aggregate = {
        key: float(np.mean([row[key] for row in results]))
        for key in ("psnr", "ssim", "lpips") if all(row[key] is not None for row in results)
    }
    report = {"pair_count": len(results), "aggregate_mean": aggregate, "lpips_status": lpips_status(), "missing_candidate": missing_candidate, "missing_reference": missing_reference, "images": results}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    csv_path = args.output.with_suffix(".csv")
    with csv_path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=("image", "psnr", "ssim", "lpips"))
        writer.writeheader()
        writer.writerows(results)
    print(json.dumps({"json": str(args.output), "csv": str(csv_path), "pair_count": len(results), "aggregate_mean": aggregate}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
