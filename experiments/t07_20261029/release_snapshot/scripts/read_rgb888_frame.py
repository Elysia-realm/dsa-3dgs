from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


def aligned_row_stride(width: int) -> int:
    if width <= 0:
        raise ValueError("width must be positive")
    return (width * 3 + 15) & ~15


def decode_rgb888(data: bytes, width: int, height: int, stride: int | None = None) -> np.ndarray:
    if height <= 0:
        raise ValueError("height must be positive")
    row_stride = aligned_row_stride(width) if stride is None else stride
    if row_stride < width * 3 or row_stride % 16:
        raise ValueError("stride must be 16-byte aligned and cover one RGB888 row")
    expected = row_stride * height
    if len(data) != expected:
        raise ValueError(f"expected {expected} bytes, got {len(data)}")
    frame = np.empty((height, width, 3), dtype=np.uint8)
    for y in range(height):
        start = y * row_stride
        frame[y] = np.frombuffer(data[start:start + width * 3], dtype=np.uint8).reshape(width, 3)
    return frame


def main() -> None:
    parser = argparse.ArgumentParser(description="Wrap a T04 RTL RGB888 DMA frame as PNG")
    parser.add_argument("input", type=Path, help="raw bytes read from OUTPUT_BASE")
    parser.add_argument("output", type=Path, help="PNG written without recomputing rendering")
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--stride", type=int, help="defaults to align16(width*3)")
    parser.add_argument("--metadata", type=Path)
    args = parser.parse_args()
    stride = aligned_row_stride(args.width) if args.stride is None else args.stride
    frame = decode_rgb888(args.input.read_bytes(), args.width, args.height, stride)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(frame, mode="RGB").save(args.output)
    if args.metadata:
        report = {
            "format": "rgb888-row-aligned16-v1",
            "input": str(args.input),
            "width": args.width,
            "height": args.height,
            "row_stride_bytes": stride,
            "payload_bytes": stride * args.height,
            "rgb_min": frame.reshape(-1, 3).min(axis=0).tolist(),
            "rgb_max": frame.reshape(-1, 3).max(axis=0).tolist(),
        }
        args.metadata.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(args.output)


if __name__ == "__main__":
    main()
