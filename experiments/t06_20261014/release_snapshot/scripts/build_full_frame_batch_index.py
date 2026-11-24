from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import date
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.io import camera_fixed, discover_scenes, iter_gaussian_batches, read_cameras, scaled_camera
from model.io.scene import open_ply_vertices


COORD_W = 27
COORD_MIN = -(1 << (COORD_W - 1))
COORD_MAX = (1 << (COORD_W - 1)) - 1
NEAR_Q16 = int(round(0.2 * (1 << 16)))
FAR_Q16 = int(round(1000.0 * (1 << 16)))
INDEX_DTYPE = np.dtype([("gid", "<u4"), ("depth_q16", "<i4")])


def quantize_signed(values: np.ndarray, fractional_bits: int, width: int) -> np.ndarray:
    scaled = np.rint(np.asarray(values, dtype=np.float64) * (1 << fractional_bits)).astype(np.int64)
    return np.clip(scaled, -(1 << (width - 1)), (1 << (width - 1)) - 1)


def round_shift_away_from_zero(values: np.ndarray, shift: int) -> np.ndarray:
    values = np.asarray(values, dtype=np.int64)
    magnitude = np.abs(values)
    rounded = (magnitude + (1 << (shift - 1))) >> shift
    return np.where(values < 0, -rounded, rounded).astype(np.int64)


def rtl_depth_q16(mean: np.ndarray, rotation_row_q20: np.ndarray, translation_q16: int) -> tuple[np.ndarray, np.ndarray]:
    mean_q16 = quantize_signed(mean, 16, COORD_W)
    acc = mean_q16 @ np.asarray(rotation_row_q20, dtype=np.int64)
    acc += np.int64(translation_q16) << 20
    shifted = round_shift_away_from_zero(acc, 20)
    overflow = (shifted < COORD_MIN) | (shifted > COORD_MAX)
    return np.clip(shifted, COORD_MIN, COORD_MAX).astype(np.int32), overflow


def pack_mean_records(gid: np.ndarray, mean: np.ndarray) -> np.ndarray:
    """Pack the exact 128-bit AXI mean record as two little-endian uint64 words."""
    gid = np.asarray(gid, dtype=np.uint32)
    mean_q16 = quantize_signed(mean, 16, COORD_W)
    mask = np.uint64((1 << COORD_W) - 1)
    x = mean_q16[:, 0].astype(np.uint64) & mask
    y = mean_q16[:, 1].astype(np.uint64) & mask
    z = mean_q16[:, 2].astype(np.uint64) & mask
    words = np.zeros((gid.size, 2), dtype="<u8")
    words[:, 0] = gid.astype(np.uint64) | (x << np.uint64(32)) | ((y & np.uint64(0x1F)) << np.uint64(59))
    words[:, 1] = (y >> np.uint64(5)) | (z << np.uint64(22))
    return words


def validate_batches(records: np.ndarray, batches: list[dict], capacity: int) -> dict:
    expected_offset = 0
    for batch_index, batch in enumerate(batches):
        if batch["offset_records"] != expected_offset or batch["count"] <= 0:
            raise ValueError(f"batch {batch_index}: non-contiguous or empty range")
        start = batch["offset_records"]
        stop = start + batch["count"]
        if stop > records.size:
            raise ValueError(f"batch {batch_index}: range exceeds index")
        depths = records["depth_q16"][start:stop]
        pivots = np.asarray(batch["pivots_q16"], dtype=np.int64)
        assignment = np.searchsorted(pivots, depths.astype(np.int64), side="right")
        observed = [int(np.count_nonzero(assignment == group)) for group in range(4)]
        planned = batch["group_counts"] + [0] * (4 - len(batch["group_counts"]))
        if observed != planned:
            raise ValueError(f"batch {batch_index}: pivot counts {observed} != planned {planned}")
        if max(observed) > capacity:
            raise ValueError(f"batch {batch_index}: group capacity exceeded")
        expected_offset = stop
    if expected_offset != records.size:
        raise ValueError("batch ranges do not cover the complete index")
    depth_ordered = bool(np.all(records["depth_q16"][1:] >= records["depth_q16"][:-1]))
    ties = records["depth_q16"][1:] == records["depth_q16"][:-1]
    gid_ties_ordered = bool(np.all(records["gid"][1:][ties] >= records["gid"][:-1][ties]))
    if not depth_ordered or not gid_ties_ordered:
        raise ValueError("global (depth_q16,GID) order is invalid")
    return {
        "complete_coverage": True,
        "global_depth_nondecreasing": depth_ordered,
        "equal_depth_gid_nondecreasing": gid_ties_ordered,
        "all_pivot_group_counts_match": True,
        "all_groups_within_capacity": True,
    }


def pack_batches(depths: np.ndarray, capacity: int, groups: int = 4) -> list[dict]:
    """Pack globally sorted records without splitting a depth run inside a batch group."""
    if capacity <= 0 or groups <= 0:
        raise ValueError("capacity and groups must be positive")
    depths = np.asarray(depths, dtype=np.int32)
    if depths.size == 0:
        return []
    run_start = np.r_[0, np.flatnonzero(depths[1:] != depths[:-1]) + 1]
    run_stop = np.r_[run_start[1:], depths.size]
    batches: list[dict] = []
    batch_groups: list[tuple[int, int]] = []
    group_begin = int(run_start[0])
    group_end = group_begin

    def close_batch() -> None:
        nonlocal batch_groups
        if not batch_groups:
            return
        begin, end = batch_groups[0][0], batch_groups[-1][1]
        boundary_depths = [int(depths[item[0]]) for item in batch_groups[1:]]
        after = min(COORD_MAX, int(depths[end - 1]) + 1)
        pivots = (boundary_depths + [after, after, after])[:3]
        batches.append({
            "offset_records": begin,
            "count": end - begin,
            "group_counts": [stop - start for start, stop in batch_groups],
            "depth_min_q16": int(depths[begin]),
            "depth_max_q16": int(depths[end - 1]),
            "pivots_q16": pivots,
        })
        batch_groups = []

    for start, stop in zip(run_start.tolist(), run_stop.tolist()):
        remaining_start = int(start)
        while remaining_start < int(stop):
            remaining = int(stop) - remaining_start
            # A quantized-depth run larger than one group cannot be separated
            # by a depth-only pivot. Put each capacity-sized piece in its own
            # batch so no equal-depth record crosses an intra-batch boundary.
            if remaining > capacity:
                if group_end > group_begin:
                    batch_groups.append((group_begin, group_end))
                close_batch()
                piece_end = remaining_start + capacity
                batch_groups = [(remaining_start, piece_end)]
                close_batch()
                remaining_start = piece_end
                group_begin = remaining_start
                group_end = remaining_start
                continue
            if group_end == group_begin:
                group_begin, group_end = remaining_start, int(stop)
            elif int(stop) - group_begin <= capacity:
                group_end = int(stop)
            else:
                batch_groups.append((group_begin, group_end))
                if len(batch_groups) == groups:
                    close_batch()
                group_begin, group_end = remaining_start, int(stop)
            remaining_start = int(stop)

    if group_end > group_begin:
        batch_groups.append((group_begin, group_end))
    close_batch()
    return batches


def main() -> None:
    parser = argparse.ArgumentParser(description="Build local capacity-safe full-frame depth/GID batch index")
    parser.add_argument("--scene", required=True)
    parser.add_argument("--camera", type=int, default=-1)
    parser.add_argument("--max-dimension", type=int, default=64)
    parser.add_argument("--group-capacity", type=int, default=256)
    parser.add_argument("--scan-batch", type=int, default=262_144)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    scenes = {scene.name: scene for scene in discover_scenes(ROOT / "data")}
    if args.scene not in scenes:
        parser.error(f"unknown scene {args.scene!r}")
    scene = scenes[args.scene]
    cameras = read_cameras(scene.cameras_json)
    camera_index = len(cameras) // 2 if args.camera < 0 else args.camera
    camera = scaled_camera(cameras[camera_index], args.max_dimension)
    fixed = camera_fixed(camera)
    row = np.asarray(fixed["rotation_q20"], dtype=np.int64).reshape(3, 3)[2]
    tz = int(fixed["translation_q16"][2])

    gids: list[np.ndarray] = []
    depths: list[np.ndarray] = []
    overflow_count = 0
    for batch in iter_gaussian_batches(scene.final_ply, batch_size=args.scan_batch, include_sh=False):
        depth, overflow = rtl_depth_q16(batch.mean, row, tz)
        valid = ~overflow & (depth >= NEAR_Q16) & (depth <= FAR_Q16)
        overflow_count += int(np.count_nonzero(overflow))
        gids.append(np.arange(batch.start, batch.stop, dtype=np.uint32)[valid])
        depths.append(depth[valid])
    gid = np.concatenate(gids)
    depth = np.concatenate(depths)
    order = np.lexsort((gid, depth))
    records = np.empty(order.size, dtype=INDEX_DTYPE)
    records["gid"] = gid[order]
    records["depth_q16"] = depth[order]
    batches = pack_batches(records["depth_q16"], args.group_capacity)
    for index, batch in enumerate(batches):
        batch["batch_index"] = index
        batch["control"] = {
            "continue": index != 0,
            "more_batches": index + 1 != len(batches),
        }
        batch["mean_offset_bytes"] = batch["offset_records"] * 16
        batch["gaussian_count"] = batch["count"]
    validation = validate_batches(records, batches, args.group_capacity)

    args.output_root.mkdir(parents=True, exist_ok=True)
    index_path = args.output_root / "depth_gid_index.bin"
    index_path.write_bytes(records.tobytes())
    index_sha = hashlib.sha256(index_path.read_bytes()).hexdigest()
    _, vertices = open_ply_vertices(scene.final_ply)
    selected = vertices[records["gid"]]
    selected_mean = np.column_stack((selected["x"], selected["y"], selected["z"])).astype(np.float32)
    replay_depth, replay_overflow = rtl_depth_q16(selected_mean, row, tz)
    if np.any(replay_overflow) or not np.array_equal(replay_depth, records["depth_q16"]):
        raise ValueError("mean stream does not replay to the indexed RTL depth")
    validation["mean_stream_replays_indexed_depth"] = True
    mean_path = args.output_root / "mean_stream.bin"
    mean_path.write_bytes(pack_mean_records(records["gid"], selected_mean).tobytes())
    mean_sha = hashlib.sha256(mean_path.read_bytes()).hexdigest()
    manifest = {
        "format_version": 1,
        "date": date.today().isoformat(),
        "data_policy": "Local D:/3DGS filesystem only; no upload.",
        "scene": scene.name,
        "camera_index": camera_index,
        "resolution": [camera.width, camera.height],
        "source_gaussians": int(len(vertices)),
        "eligible_gaussians": int(records.size),
        "numeric_overflow_gaussians": overflow_count,
        "sort_key": "(RTL Q16 camera depth, unsigned global GID)",
        "record_format": "little-endian {uint32 gid, int32 depth_q16}",
        "record_bytes": INDEX_DTYPE.itemsize,
        "index_file": index_path.name,
        "index_sha256": index_sha,
        "mean_stream_file": mean_path.name,
        "mean_record_format": "128-bit little-endian RTL mean record",
        "mean_stream_bytes": mean_path.stat().st_size,
        "mean_stream_sha256": mean_sha,
        "group_capacity": args.group_capacity,
        "groups": 4,
        "batch_count": len(batches),
        "max_batch_gaussians": max((batch["count"] for batch in batches), default=0),
        "max_group_gaussians": max((max(batch["group_counts"]) for batch in batches), default=0),
        "camera_fixed": fixed,
        "validation": validation,
        "batches": batches,
    }
    manifest_path = args.output_root / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(manifest_path)
    print(f"eligible={records.size} batches={len(batches)} max_batch={manifest['max_batch_gaussians']} index_sha256={index_sha} mean_sha256={mean_sha}")


if __name__ == "__main__":
    main()
