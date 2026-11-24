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

from model.io import discover_scenes, open_ply_vertices
from model.io.dma_workload import ATTRIBUTE_BEATS, CAMERA_DESCRIPTOR_TAG, pack_attribute_record
from scripts.build_full_frame_batch_index import INDEX_DTYPE


def _write_hex(path: Path, values, digits: int) -> None:
    with path.open("w", encoding="ascii", newline="\n") as stream:
        for value in values:
            stream.write(f"{int(value):0{digits}x}\n")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _bits(value: int, width: int) -> int:
    return int(value) & ((1 << width) - 1)


def load_index_records(index_path: Path, offset: int, count: int) -> np.ndarray:
    if offset < 0 or count <= 0:
        raise ValueError("offset must be nonnegative and count must be positive")
    records = np.memmap(index_path, dtype=INDEX_DTYPE, mode="r")
    if offset + count > records.size:
        raise ValueError("batch range exceeds depth/GID index")
    return np.asarray(records[offset:offset + count]).copy()


def load_selected_gaussians(scene_ply: Path, gids: np.ndarray) -> dict[str, np.ndarray]:
    gids = np.asarray(gids, dtype=np.uint32)
    if gids.size == 0 or np.unique(gids).size != gids.size:
        raise ValueError("selected global GIDs must be nonempty and unique")
    header, vertices = open_ply_vertices(scene_ply)
    if int(gids.max()) >= header.vertex_count:
        raise ValueError(f"global GID exceeds PLY vertex count {header.vertex_count}")
    names = set(header.dtype.names or ())
    dc_names = [f"f_dc_{index}" for index in range(3)]
    rest_names = [f"f_rest_{index}" for index in range(45)]
    required = {
        "x", "y", "z", "opacity", "scale_0", "scale_1", "scale_2",
        "rot_0", "rot_1", "rot_2", "rot_3", *dc_names, *rest_names,
    }
    missing = required - names
    if missing:
        raise ValueError(f"full degree-3 attributes are required; missing {sorted(missing)}")

    # Sparse advanced indexing reads only the selected global records and
    # preserves depth-stream order.  This avoids rescanning every Gaussian for
    # each of the roughly one thousand full-frame continuation batches.
    records = vertices[gids.astype(np.int64)]

    def stack(field_names: list[str]) -> np.ndarray:
        return np.column_stack([records[name] for name in field_names]).astype(np.float32, copy=False)

    mean = stack(["x", "y", "z"])
    scale = np.exp(stack(["scale_0", "scale_1", "scale_2"])).astype(np.float32)
    quaternion = stack(["rot_0", "rot_1", "rot_2", "rot_3"])
    norm = np.linalg.norm(quaternion, axis=1, keepdims=True)
    quaternion = (quaternion / np.maximum(norm, np.float32(1.0e-12))).astype(np.float32)
    raw_opacity = np.asarray(records["opacity"], dtype=np.float32)
    opacity = np.empty_like(raw_opacity)
    positive = raw_opacity >= 0
    opacity[positive] = 1.0 / (1.0 + np.exp(-raw_opacity[positive]))
    exp_value = np.exp(raw_opacity[~positive])
    opacity[~positive] = exp_value / (1.0 + exp_value)
    dc = stack(dc_names)[:, :, None]
    rest = stack(rest_names).reshape(-1, 15, 3).transpose(0, 2, 1)
    sh = np.concatenate((dc, rest), axis=2).astype(np.float32, copy=False)
    return {"mean": mean, "scale": scale, "quaternion": quaternion, "opacity": opacity, "sh": sh}


def build_batch(index_dir: Path, output_dir: Path, batch_index: int, scene_ply: Path) -> dict:
    manifest_path = index_dir / "manifest.json"
    source = json.loads(manifest_path.read_text(encoding="utf-8"))
    batches = source["batches"]
    if not 0 <= batch_index < len(batches):
        raise IndexError("batch index out of range")
    batch = batches[batch_index]
    count = int(batch["count"])
    offset = int(batch["offset_records"])
    records = load_index_records(index_dir / source["index_file"], offset, count)
    gids = records["gid"]
    attributes = load_selected_gaussians(scene_ply, gids)

    mean_words = np.memmap(index_dir / source["mean_stream_file"], dtype="<u8", mode="r").reshape(-1, 2)
    selected_mean_words = np.asarray(mean_words[offset:offset + count])
    mean_values = [int(lo) | (int(hi) << 64) for lo, hi in selected_mean_words]

    attribute_beats: list[int] = []
    for index in range(count):
        packed = pack_attribute_record(
            attributes["mean"][index], attributes["quaternion"][index],
            attributes["scale"][index], attributes["opacity"][index], attributes["sh"][index],
        )
        attribute_beats.extend(
            (packed >> (beat * 128)) & ((1 << 128) - 1) for beat in range(ATTRIBUTE_BEATS)
        )

    fixed = source["camera_fixed"]
    camera_words = [
        *fixed["rotation_q20"], *fixed["translation_q16"], *fixed["position_q16"],
        *fixed["fx_fy_cx_cy_q16"], *fixed["near_far_q16"], fixed["regularizer_q8"],
        *batch["pivots_q16"], *source["resolution"], (CAMERA_DESCRIPTOR_TAG << 32) | count,
    ]
    if len(camera_words) != 28:
        raise AssertionError("camera memory contract changed")

    output_dir.mkdir(parents=True, exist_ok=True)
    _write_hex(output_dir / "mean.memh", mean_values, 32)
    _write_hex(output_dir / "global_gid.memh", gids, 8)
    _write_hex(output_dir / "attribute_sparse.memh", attribute_beats, 32)
    _write_hex(output_dir / "camera.memh", (_bits(value, 64) for value in camera_words), 16)

    output = {
        "format_version": 1,
        "date": date.today().isoformat(),
        "data_policy": "Local D:/3DGS filesystem only; no upload.",
        "source_manifest": str(manifest_path),
        "scene": source["scene"],
        "camera_index": source["camera_index"],
        "batch_index": batch_index,
        "offset_records": offset,
        "gaussian_count": count,
        "resolution": source["resolution"],
        "global_gid_min": int(gids.min()),
        "global_gid_max": int(gids.max()),
        "global_gid_unique": bool(np.unique(gids).size == count),
        "pivots_q16": batch["pivots_q16"],
        "group_counts": batch["group_counts"],
        "control": batch["control"],
        "attribute_address_contract": "ATTRIBUTE_BASE + global_GID * 144",
        "sparse_lookup_contract": "global_gid.memh slot i maps to attribute_sparse.memh beats i*9..i*9+8",
        "files": {},
    }
    for name in ("mean.memh", "global_gid.memh", "attribute_sparse.memh", "camera.memh"):
        path = output_dir / name
        output["files"][name] = {"bytes": path.stat().st_size, "sha256": _sha256(path)}
    (output_dir / "manifest.json").write_text(
        json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a sparse global-GID RTL batch from a full-frame index")
    parser.add_argument("--index-dir", type=Path, required=True)
    parser.add_argument("--batch-index", type=int, default=0)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scene-ply", type=Path, help="optional explicit local PLY path")
    args = parser.parse_args()
    source = json.loads((args.index_dir / "manifest.json").read_text(encoding="utf-8"))
    if args.scene_ply:
        scene_ply = args.scene_ply
        if not scene_ply.is_file():
            parser.error(f"scene PLY is not available: {scene_ply}")
    else:
        scenes = {scene.name: scene for scene in discover_scenes(ROOT / "data")}
        if source["scene"] not in scenes:
            parser.error(f"scene {source['scene']!r} is not available under D:/3DGS/data")
        scene_ply = scenes[source["scene"]].final_ply
    result = build_batch(args.index_dir, args.output, args.batch_index, scene_ply)
    print(args.output / "manifest.json")
    print(
        f"batch={result['batch_index']} count={result['gaussian_count']} "
        f"global_gid=[{result['global_gid_min']},{result['global_gid_max']}] groups={result['group_counts']}"
    )


if __name__ == "__main__":
    main()
