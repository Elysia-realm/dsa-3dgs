from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.io.dma_workload import CAMERA_DESCRIPTOR_TAG


def read_camera_descriptor(path: Path) -> list[int]:
    words = [int(line.strip(), 16) for line in path.read_text(encoding="ascii").splitlines() if line.strip()]
    if len(words) != 28:
        raise ValueError(f"camera descriptor must contain 28 64-bit words, got {len(words)}")
    if any(word < 0 or word >= 1 << 64 for word in words):
        raise ValueError("camera descriptor word exceeds 64 bits")
    if words[27] >> 32 != CAMERA_DESCRIPTOR_TAG:
        raise ValueError("camera descriptor tag/version mismatch")
    if not 0 < words[25] <= 0xFFFF or not 0 < words[26] <= 0xFFFF:
        raise ValueError("camera descriptor image size is invalid")
    return words


def register_writes(
    words: list[int], gaussian_base: int, camera_base: int,
    attribute_base: int, output_base: int, continuation: bool, more_batches: bool,
) -> list[dict[str, int | str]]:
    count = words[27] & 0xFFFFFFFF
    width, height = words[25] & 0xFFFF, words[26] & 0xFFFF
    values = (
        ("GAUSSIAN_BASE_LO", 0x010, gaussian_base & 0xFFFFFFFF),
        ("GAUSSIAN_BASE_HI", 0x014, gaussian_base >> 32),
        ("CAMERA_BASE_LO", 0x018, camera_base & 0xFFFFFFFF),
        ("CAMERA_BASE_HI", 0x01C, camera_base >> 32),
        ("OUTPUT_BASE_LO", 0x020, output_base & 0xFFFFFFFF),
        ("OUTPUT_BASE_HI", 0x024, output_base >> 32),
        ("IMAGE_SIZE", 0x028, (height << 16) | width),
        ("GAUSSIAN_COUNT", 0x038, count),
        ("ATTRIBUTE_BASE_LO", 0x03C, attribute_base & 0xFFFFFFFF),
        ("ATTRIBUTE_BASE_HI", 0x040, attribute_base >> 32),
    )
    control = 1 | (8 if continuation else 0) | (16 if more_batches else 0)
    writes = [{"name": name, "offset": offset, "value": value & 0xFFFFFFFF} for name, offset, value in values]
    writes.append({"name": "CONTROL.START", "offset": 0, "value": control})
    return writes


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a T03 camera descriptor image and APB command example")
    parser.add_argument("camera_memh", type=Path)
    parser.add_argument("--gaussian-base", type=lambda value: int(value, 0), default=0x1000)
    parser.add_argument("--camera-base", type=lambda value: int(value, 0), default=0x2000)
    parser.add_argument("--attribute-base", type=lambda value: int(value, 0), default=0x4000)
    parser.add_argument("--output-base", type=lambda value: int(value, 0), default=0x100000)
    parser.add_argument("--continuation", action="store_true")
    parser.add_argument("--more-batches", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    words = read_camera_descriptor(args.camera_memh)
    args.output.mkdir(parents=True, exist_ok=True)
    descriptor_bin = args.output / "camera_descriptor_v1.bin"
    descriptor_bin.write_bytes(b"".join(word.to_bytes(8, "little") for word in words))
    command = {
        "schema_version": 1,
        "camera_descriptor_tag": f"0x{CAMERA_DESCRIPTOR_TAG:08x}",
        "camera_descriptor_bytes": descriptor_bin.stat().st_size,
        "camera_descriptor_binary": descriptor_bin.name,
        "apb_writes": register_writes(
            words, args.gaussian_base, args.camera_base, args.attribute_base,
            args.output_base, args.continuation, args.more_batches,
        ),
    }
    (args.output / "command.json").write_text(json.dumps(command, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
