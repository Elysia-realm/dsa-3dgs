from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.io import discover_scenes, write_workload


def main() -> None:
    parser = argparse.ArgumentParser(description="Build local 3DGS RTL DMA workload images")
    parser.add_argument("--scene", default="bonsai")
    parser.add_argument("--camera", type=int, default=-1, help="negative selects middle camera")
    parser.add_argument("--count", type=int, default=4)
    parser.add_argument("--max-dimension", type=int, default=32)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    scenes = {scene.name: scene for scene in discover_scenes(ROOT / "data")}
    if args.scene not in scenes:
        raise SystemExit(f"unknown scene {args.scene!r}; choices: {', '.join(scenes)}")
    output = args.output or ROOT / "experiments" / "rtl_workloads" / (
        f"{args.scene}_cam{'mid' if args.camera < 0 else args.camera}_n{args.count}_d{args.max_dimension}"
    )
    manifest = write_workload(scenes[args.scene], output, args.camera, args.count, args.max_dimension)
    print(output)
    print(f"scene={manifest.scene} camera={manifest.camera_index} gaussians={manifest.gaussian_count}")
    print(f"resolution={manifest.width}x{manifest.height}")


if __name__ == "__main__":
    main()
