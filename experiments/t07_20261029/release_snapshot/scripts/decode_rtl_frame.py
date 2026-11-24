from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


def decode_state(path: Path, width: int, height: int) -> tuple[np.ndarray, np.ndarray]:
    words = [int(line, 16) for line in path.read_text(encoding="ascii").splitlines() if line.strip()]
    expected = width * height
    if len(words) != expected:
        raise ValueError(f"expected {expected} pixels, got {len(words)}")
    rgb = np.empty((height, width, 3), dtype=np.uint8)
    transmittance = np.empty((height, width), dtype=np.uint16)
    for pixel, word in enumerate(words):
        q12 = (word & 0x1FFF, (word >> 13) & 0x1FFF, (word >> 26) & 0x1FFF)
        y, x = divmod(pixel, width)
        rgb[y, x] = np.clip(np.rint(np.asarray(q12) * (255.0 / 4096.0)), 0, 255).astype(np.uint8)
        transmittance[y, x] = (word >> 39) & 0xFFFF
    return rgb, transmittance


def main() -> None:
    parser = argparse.ArgumentParser(description="Decode local RTL 128-bit pixel state into an RGB PNG")
    parser.add_argument("state", type=Path)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--metadata", type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    rgb, transmittance = decode_state(args.state, manifest["width"], manifest["height"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgb, mode="RGB").save(args.output)
    if args.metadata:
        nonzero = np.any(rgb != 0, axis=2)
        report = {
            "state": str(args.state),
            "width": manifest["width"],
            "height": manifest["height"],
            "nonzero_pixels": int(nonzero.sum()),
            "rgb_min": rgb.reshape(-1, 3).min(axis=0).tolist(),
            "rgb_max": rgb.reshape(-1, 3).max(axis=0).tolist(),
            "transmittance_min": int(transmittance.min()),
            "transmittance_max": int(transmittance.max()),
        }
        args.metadata.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(args.output)


if __name__ == "__main__":
    main()
