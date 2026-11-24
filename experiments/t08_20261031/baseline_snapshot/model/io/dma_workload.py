from __future__ import annotations

import heapq
import json
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np

from model.reference import Camera

from .scene import GaussianBatch, SceneFiles, iter_gaussian_batches, read_cameras, scaled_camera


COORD_W = 27
QUAT_W = 22
SCALE_W = 24
COEFF_W = 18
COEFFS = 16
ATTRIBUTE_BITS = 1118
ATTRIBUTE_BEATS = 9
CAMERA_DESCRIPTOR_TAG = 0x47534301


@dataclass(frozen=True)
class WorkloadManifest:
    format_version: int
    source: str
    scene: str
    camera_index: int
    original_gaussian_indices: list[int]
    gaussian_count: int
    width: int
    height: int
    mean_record_bytes: int
    attribute_record_bytes: int
    gaussian_base: int
    attribute_base: int
    output_base: int
    fixed_formats: dict[str, str]
    camera_fixed: dict[str, int | list[int]]
    depth_pivots_q16: list[int]
    selection: str


def _signed_code(value, fractional_bits: int, width: int) -> int:
    minimum = -(1 << (width - 1))
    maximum = (1 << (width - 1)) - 1
    code = int(np.rint(float(value) * (1 << fractional_bits)))
    return min(max(code, minimum), maximum)


def _unsigned_code(value, fractional_bits: int, width: int) -> int:
    code = int(np.rint(float(value) * (1 << fractional_bits)))
    return min(max(code, 0), (1 << width) - 1)


def _bits(value: int, width: int) -> int:
    return value & ((1 << width) - 1)


def pack_mean_record(gid: int, mean: np.ndarray) -> int:
    record = _bits(gid, 32)
    for offset, value in zip((32, 59, 86), mean):
        record |= _bits(_signed_code(value, 16, COORD_W), COORD_W) << offset
    return record


def pack_attribute_record(mean, quaternion, scale, opacity, sh) -> int:
    sh = np.asarray(sh, dtype=np.float64)
    if sh.shape != (3, COEFFS):
        raise ValueError(f"expected SH shape (3,16), got {sh.shape}")
    fields: list[tuple[int, int]] = []
    for value in sh.reshape(-1):
        fields.append((_signed_code(value, 12, COEFF_W), COEFF_W))
    fields.append((_unsigned_code(opacity, 12, 13), 13))
    for value in np.asarray(scale)[::-1]:
        fields.append((_unsigned_code(value, 20, SCALE_W), SCALE_W))
    for value in np.asarray(quaternion)[::-1]:
        fields.append((_signed_code(value, 20, QUAT_W), QUAT_W))
    for value in np.asarray(mean)[::-1]:
        fields.append((_signed_code(value, 16, COORD_W), COORD_W))
    record = 0
    offset = 0
    for value, width in fields:
        record |= _bits(value, width) << offset
        offset += width
    if offset != ATTRIBUTE_BITS:
        raise AssertionError(f"attribute width mismatch: {offset}")
    return record


def _candidate_mask(batch: GaussianBatch, camera: Camera) -> tuple[np.ndarray, np.ndarray]:
    mean_camera = batch.mean @ camera.world_to_camera[:3, :3].T + camera.world_to_camera[:3, 3]
    depth = mean_camera[:, 2]
    valid_depth = (depth >= 0.2) & (depth <= 1000.0)
    safe_depth = np.where(valid_depth, depth, 1.0)
    screen_x = camera.fx * mean_camera[:, 0] / safe_depth + camera.cx
    screen_y = camera.fy * mean_camera[:, 1] / safe_depth + camera.cy
    # The margin admits Gaussians whose centers are just off screen but whose
    # trained covariance may still overlap the image.
    margin = 8.0
    visible = valid_depth & (batch.opacity >= 1.0 / 255.0)
    visible &= (screen_x >= -margin) & (screen_x < camera.width + margin)
    visible &= (screen_y >= -margin) & (screen_y < camera.height + margin)
    representable = np.all(np.abs(batch.mean) < 1023.0, axis=1)
    representable &= np.all(batch.scale < 15.9, axis=1)
    return visible & representable, depth


def _sample_priority(global_index: int) -> int:
    """Return a deterministic SplitMix64 key for scene-wide sampling."""
    value = (int(global_index) + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
    value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
    value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
    return value ^ (value >> 31)


def select_real_gaussians(scene: SceneFiles, camera: Camera, count: int) -> tuple[list[int], GaussianBatch, np.ndarray]:
    if count <= 0:
        raise ValueError("count must be positive")
    # Keep the globally smallest deterministic random keys. This gives a
    # fixed-seed, batch-size-independent sample while storing O(count) records.
    selected: list[tuple[int, int, np.ndarray, np.ndarray, np.ndarray, float, np.ndarray, float]] = []
    for batch in iter_gaussian_batches(scene.final_ply, batch_size=262_144, include_sh=True):
        mask, depth = _candidate_mask(batch, camera)
        for local_value in np.flatnonzero(mask):
            local = int(local_value)
            global_index = batch.start + local
            priority = _sample_priority(global_index)
            if len(selected) == count and priority >= -selected[0][0]:
                continue
            entry = (-priority, global_index, batch.mean[local].copy(), batch.scale[local].copy(),
                     batch.quaternion[local].copy(), float(batch.opacity[local]), batch.sh[local].copy(),
                     float(depth[local]))
            if len(selected) < count:
                heapq.heappush(selected, entry)
            else:
                heapq.heapreplace(selected, entry)
    if len(selected) != count:
        raise ValueError(f"scene {scene.name} yielded only {len(selected)} representable visible Gaussians")
    selected.sort(key=lambda entry: entry[1])
    selected_indices = [entry[1] for entry in selected]
    selected_batch = GaussianBatch(
        0,
        count,
        np.asarray([entry[2] for entry in selected], dtype=np.float32),
        np.asarray([entry[3] for entry in selected], dtype=np.float32),
        np.asarray([entry[4] for entry in selected], dtype=np.float32),
        np.asarray([entry[5] for entry in selected], dtype=np.float32),
        np.asarray([entry[6] for entry in selected], dtype=np.float32),
    )
    return selected_indices, selected_batch, np.asarray([entry[7] for entry in selected], dtype=np.float32)


def camera_fixed(camera: Camera) -> dict[str, int | list[int]]:
    rotation = camera.world_to_camera[:3, :3]
    translation = camera.world_to_camera[:3, 3]
    position = camera.position_world
    return {
        "rotation_q20": [_signed_code(value, 20, 22) for value in rotation.reshape(-1)],
        "translation_q16": [_signed_code(value, 16, COORD_W) for value in translation],
        "position_q16": [_signed_code(value, 16, COORD_W) for value in position],
        "fx_fy_cx_cy_q16": [_signed_code(value, 16, 33) for value in (camera.fx, camera.fy, camera.cx, camera.cy)],
        "near_far_q16": [_signed_code(0.2, 16, COORD_W), _signed_code(1000.0, 16, COORD_W)],
        "regularizer_q8": _unsigned_code(0.3, 8, 32),
    }


def _write_hex(path: Path, values: list[int], digits: int) -> None:
    path.write_text("".join(f"{value:0{digits}x}\n" for value in values), encoding="ascii")


def _sv_list(values: list[int]) -> str:
    return ",".join(str(value) for value in values)


def write_workload(
    scene: SceneFiles,
    output_dir: Path,
    camera_index: int = -1,
    count: int = 4,
    max_dimension: int = 32,
) -> WorkloadManifest:
    cameras = read_cameras(scene.cameras_json)
    if camera_index < 0:
        camera_index = len(cameras) // 2
    if not 0 <= camera_index < len(cameras):
        raise IndexError("camera index out of range")
    camera = scaled_camera(cameras[camera_index], max_dimension)
    source_indices, batch, depth = select_real_gaussians(scene, camera, count)
    output_dir.mkdir(parents=True, exist_ok=True)

    mean_records = [pack_mean_record(gid, batch.mean[gid]) for gid in range(count)]
    attribute_beats: list[int] = []
    for gid in range(count):
        record = pack_attribute_record(
            batch.mean[gid], batch.quaternion[gid], batch.scale[gid], batch.opacity[gid], batch.sh[gid]
        )
        attribute_beats.extend((record >> (beat * 128)) & ((1 << 128) - 1) for beat in range(ATTRIBUTE_BEATS))
    _write_hex(output_dir / "mean.memh", mean_records, 32)
    _write_hex(output_dir / "attribute.memh", attribute_beats, 32)

    quantiles = np.quantile(depth, (0.25, 0.5, 0.75)) if count > 1 else np.repeat(depth[0], 3)
    pivots = [_signed_code(value, 16, COORD_W) for value in quantiles]
    fixed = camera_fixed(camera)
    camera_words = [
        *fixed["rotation_q20"],
        *fixed["translation_q16"],
        *fixed["position_q16"],
        *fixed["fx_fy_cx_cy_q16"],
        *fixed["near_far_q16"],
        fixed["regularizer_q8"],
        *pivots,
        camera.width,
        camera.height,
        (CAMERA_DESCRIPTOR_TAG << 32) | count,
    ]
    _write_hex(output_dir / "camera.memh", [_bits(int(value), 64) for value in camera_words], 16)
    manifest = WorkloadManifest(
        format_version=1,
        source="local D:/3DGS/data only; no network upload",
        scene=scene.name,
        camera_index=camera_index,
        original_gaussian_indices=source_indices,
        gaussian_count=count,
        width=camera.width,
        height=camera.height,
        mean_record_bytes=16,
        attribute_record_bytes=144,
        gaussian_base=0x1000,
        attribute_base=0x4000,
        output_base=0x100000,
        fixed_formats={
            "mean": "signed Q10.16 / 27-bit",
            "quaternion": "signed Q2.20 / 22-bit",
            "scale": "unsigned Q4.20 / 24-bit",
            "opacity_rgb": "Q1.12 / 13-bit",
            "sh": "signed Q5.12 / 18-bit channel-major",
        },
        camera_fixed=fixed,
        depth_pivots_q16=pivots,
        selection="deterministic scene-wide priority sample of visible fixed-point-representable trained Gaussians; frame-local GID remap",
    )
    (output_dir / "manifest.json").write_text(
        json.dumps(asdict(manifest), ensure_ascii=False, indent=2), encoding="utf-8"
    )
    rotation = fixed["rotation_q20"]
    translation = fixed["translation_q16"]
    position = fixed["position_q16"]
    intrinsics = fixed["fx_fy_cx_cy_q16"]
    near_far = fixed["near_far_q16"]
    include = f"""// Generated locally from {scene.name}; do not edit.
`define RTL_WORKLOAD_COUNT {count}
`define RTL_WORKLOAD_WIDTH {camera.width}
`define RTL_WORKLOAD_HEIGHT {camera.height}
`define RTL_WORKLOAD_GAUSSIAN_BASE 64'h0000000000001000
`define RTL_WORKLOAD_ATTRIBUTE_BASE 64'h0000000000004000
`define RTL_WORKLOAD_OUTPUT_BASE 64'h0000000000100000
`define RTL_WORKLOAD_ROTATION_Q20 '{{{_sv_list(rotation)}}}
`define RTL_WORKLOAD_TRANSLATION_Q16 '{{{_sv_list(translation)}}}
`define RTL_WORKLOAD_POSITION_Q16 '{{{_sv_list(position)}}}
`define RTL_WORKLOAD_INTRINSICS_Q16 '{{{_sv_list(intrinsics)}}}
`define RTL_WORKLOAD_NEAR_FAR_Q16 '{{{_sv_list(near_far)}}}
`define RTL_WORKLOAD_REGULARIZER_Q8 {fixed['regularizer_q8']}
`define RTL_WORKLOAD_PIVOTS_Q16 '{{{_sv_list(pivots)}}}
"""
    (output_dir / "workload_params.svh").write_text(include, encoding="ascii")
    return manifest
