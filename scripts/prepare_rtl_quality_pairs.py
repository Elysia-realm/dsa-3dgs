from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.decode_rtl_frame import decode_state


def save_png(path: Path, rgb: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgb, mode="RGB").save(path)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Decode local RTL frame states and pair them with explicitly supplied reference PNGs"
    )
    parser.add_argument("--entry", action="append", nargs=4, metavar=("NAME", "STATE", "MANIFEST", "REFERENCE"), required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    reference_root = args.output_root / "reference"
    candidate_root = args.output_root / "candidate"
    records = []
    for name, state_value, manifest_value, reference_value in args.entry:
        state, manifest_path, reference_path = map(Path, (state_value, manifest_value, reference_value))
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        rtl_rgb, _ = decode_state(state, manifest["width"], manifest["height"])
        reference = Image.open(reference_path).convert("RGB")
        if reference.size != (manifest["width"], manifest["height"]):
            raise ValueError(
                f"{name}: reference is {reference.size}, expected {(manifest['width'], manifest['height'])}; "
                "resize/crop policy must be explicit before evaluation"
            )
        candidate_output = candidate_root / f"{name}.png"
        reference_output = reference_root / f"{name}.png"
        save_png(candidate_output, rtl_rgb)
        reference_output.parent.mkdir(parents=True, exist_ok=True)
        reference.save(reference_output)
        records.append({
            "name": name, "state": str(state.resolve()), "manifest": str(manifest_path.resolve()),
            "reference_source": str(reference_path.resolve()), "candidate_png": str(candidate_output.resolve()),
            "reference_png": str(reference_output.resolve()), "width": manifest["width"], "height": manifest["height"],
        })
    report = {
        "pair_count": len(records), "reference_dir": str(reference_root.resolve()),
        "candidate_dir": str(candidate_root.resolve()), "pairs": records,
        "next_command": f"python scripts/evaluate_image_quality.py {reference_root} {candidate_root} --lpips",
        "data_policy": "Local filesystem only; no upload.",
    }
    (args.output_root / "pairs.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(args.output_root / "pairs.json")


if __name__ == "__main__":
    main()
