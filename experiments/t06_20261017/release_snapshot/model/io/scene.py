from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

import numpy as np

from model.reference import Camera


PLY_SCALARS = {
    "char": "i1",
    "uchar": "u1",
    "int8": "i1",
    "uint8": "u1",
    "short": "<i2",
    "ushort": "<u2",
    "int16": "<i2",
    "uint16": "<u2",
    "int": "<i4",
    "uint": "<u4",
    "int32": "<i4",
    "uint32": "<u4",
    "float": "<f4",
    "float32": "<f4",
    "double": "<f8",
    "float64": "<f8",
}


@dataclass(frozen=True)
class PlyHeader:
    path: Path
    format: str
    vertex_count: int
    properties: tuple[tuple[str, str], ...]
    data_offset: int
    dtype: np.dtype


@dataclass(frozen=True)
class SceneFiles:
    name: str
    root: Path
    final_ply: Path
    early_ply: Path | None
    cameras_json: Path
    cfg_args: Path | None


@dataclass(frozen=True)
class GaussianBatch:
    start: int
    stop: int
    mean: np.ndarray
    scale: np.ndarray
    quaternion: np.ndarray
    opacity: np.ndarray
    sh: np.ndarray | None = None


def discover_scenes(root: str | Path, final_iteration: int = 30000, early_iteration: int = 7000) -> list[SceneFiles]:
    root = Path(root)
    result = []
    for scene in sorted(path for path in root.iterdir() if path.is_dir()):
        final_ply = scene / "point_cloud" / f"iteration_{final_iteration}" / "point_cloud.ply"
        cameras = scene / "cameras.json"
        if not final_ply.is_file() or not cameras.is_file():
            continue
        early = scene / "point_cloud" / f"iteration_{early_iteration}" / "point_cloud.ply"
        cfg = scene / "cfg_args"
        result.append(
            SceneFiles(
                name=scene.name,
                root=scene,
                final_ply=final_ply,
                early_ply=early if early.is_file() else None,
                cameras_json=cameras,
                cfg_args=cfg if cfg.is_file() else None,
            )
        )
    return result


def parse_ply_header(path: str | Path) -> PlyHeader:
    path = Path(path)
    with path.open("rb") as stream:
        if stream.readline().rstrip() != b"ply":
            raise ValueError(f"not a PLY file: {path}")
        fmt = ""
        vertex_count: int | None = None
        properties: list[tuple[str, str]] = []
        current_element = None
        for _ in range(4096):
            raw = stream.readline()
            if not raw:
                raise ValueError(f"unterminated PLY header: {path}")
            line = raw.decode("ascii").strip()
            parts = line.split()
            if not parts or parts[0] in ("comment", "obj_info"):
                continue
            if parts[0] == "format":
                fmt = parts[1]
            elif parts[0] == "element":
                current_element = parts[1]
                if current_element == "vertex":
                    vertex_count = int(parts[2])
            elif parts[0] == "property" and current_element == "vertex":
                if parts[1] == "list":
                    raise ValueError("list-valued vertex properties are unsupported")
                properties.append((parts[2], parts[1]))
            elif parts[0] == "end_header":
                offset = stream.tell()
                break
        else:
            raise ValueError(f"PLY header exceeds safety limit: {path}")
    if fmt != "binary_little_endian":
        raise ValueError(f"only binary_little_endian PLY is supported, got {fmt!r}")
    if vertex_count is None:
        raise ValueError("PLY has no vertex element")
    fields = []
    for name, scalar_type in properties:
        if scalar_type not in PLY_SCALARS:
            raise ValueError(f"unsupported PLY scalar type: {scalar_type}")
        fields.append((name, PLY_SCALARS[scalar_type]))
    dtype = np.dtype(fields, align=False)
    expected_bytes = offset + vertex_count * dtype.itemsize
    actual_bytes = path.stat().st_size
    if actual_bytes < expected_bytes:
        raise ValueError(f"truncated PLY: expected at least {expected_bytes} bytes, got {actual_bytes}")
    return PlyHeader(path, fmt, vertex_count, tuple(properties), offset, dtype)


def open_ply_vertices(path: str | Path) -> tuple[PlyHeader, np.memmap]:
    header = parse_ply_header(path)
    vertices = np.memmap(
        header.path,
        dtype=header.dtype,
        mode="r",
        offset=header.data_offset,
        shape=(header.vertex_count,),
    )
    return header, vertices


def _stack(records: np.ndarray, names: list[str]) -> np.ndarray:
    return np.column_stack([records[name] for name in names]).astype(np.float32, copy=False)


def _sigmoid(value: np.ndarray) -> np.ndarray:
    value = np.asarray(value, dtype=np.float32)
    result = np.empty_like(value)
    positive = value >= 0
    result[positive] = 1.0 / (1.0 + np.exp(-value[positive]))
    exp_value = np.exp(value[~positive])
    result[~positive] = exp_value / (1.0 + exp_value)
    return result


def iter_gaussian_batches(
    path: str | Path,
    batch_size: int = 262_144,
    include_sh: bool = False,
) -> Iterator[GaussianBatch]:
    if batch_size <= 0:
        raise ValueError("batch_size must be positive")
    header, vertices = open_ply_vertices(path)
    names = set(header.dtype.names or ())
    required = {"x", "y", "z", "opacity", "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3"}
    missing = required - names
    if missing:
        raise ValueError(f"missing Gaussian PLY properties: {sorted(missing)}")
    rest_names = sorted(
        (name for name in names if name.startswith("f_rest_")),
        key=lambda name: int(name.rsplit("_", 1)[1]),
    )
    dc_names = [f"f_dc_{index}" for index in range(3)]
    if include_sh and (not set(dc_names) <= names or len(rest_names) not in (0, 9, 24, 45)):
        raise ValueError("unsupported or incomplete SH property set")

    for start in range(0, header.vertex_count, batch_size):
        stop = min(header.vertex_count, start + batch_size)
        records = vertices[start:stop]
        mean = _stack(records, ["x", "y", "z"])
        scale = np.exp(_stack(records, ["scale_0", "scale_1", "scale_2"])).astype(np.float32)
        quaternion = _stack(records, ["rot_0", "rot_1", "rot_2", "rot_3"])
        norm = np.linalg.norm(quaternion, axis=1, keepdims=True)
        quaternion = quaternion / np.maximum(norm, np.float32(1.0e-12))
        opacity = _sigmoid(records["opacity"])
        sh = None
        if include_sh:
            dc = _stack(records, dc_names)[:, :, None]
            if rest_names:
                # Official PLY layout is channel-major: all non-DC R bases,
                # then G, then B. Runtime tensors may transpose afterwards;
                # that does not make the on-disk fields RGB-interleaved.
                rest = _stack(records, rest_names).reshape(-1, 3, len(rest_names) // 3)
                sh = np.concatenate((dc, rest), axis=2).astype(np.float32, copy=False)
            else:
                sh = dc
        yield GaussianBatch(start, stop, mean, scale, quaternion.astype(np.float32), opacity, sh)


def camera_from_json(record: dict) -> Camera:
    required = {"width", "height", "fx", "fy", "position", "rotation"}
    missing = required - record.keys()
    if missing:
        raise ValueError(f"camera record missing fields: {sorted(missing)}")
    position = np.asarray(record["position"], dtype=np.float32)
    camera_to_world_rotation = np.asarray(record["rotation"], dtype=np.float32)
    if position.shape != (3,) or camera_to_world_rotation.shape != (3, 3):
        raise ValueError("invalid camera position/rotation shape")
    world_to_camera_rotation = camera_to_world_rotation.T
    world_to_camera = np.eye(4, dtype=np.float32)
    world_to_camera[:3, :3] = world_to_camera_rotation
    world_to_camera[:3, 3] = -world_to_camera_rotation @ position
    return Camera(
        width=int(record["width"]),
        height=int(record["height"]),
        fx=float(record["fx"]),
        fy=float(record["fy"]),
        cx=(int(record["width"]) - 1) / 2.0,
        cy=(int(record["height"]) - 1) / 2.0,
        world_to_camera=world_to_camera,
    )


def read_cameras(path: str | Path) -> list[Camera]:
    records = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(records, list):
        raise ValueError("cameras.json must contain a list")
    return [camera_from_json(record) for record in records]


def scaled_camera(camera: Camera, max_dimension: int = 1920) -> Camera:
    if max_dimension <= 0:
        raise ValueError("max_dimension must be positive")
    scale = max_dimension / max(camera.width, camera.height)
    width = max(1, int(round(camera.width * scale)))
    height = max(1, int(round(camera.height * scale)))
    return Camera(
        width=width,
        height=height,
        fx=camera.fx * scale,
        fy=camera.fy * scale,
        cx=(width - 1) / 2.0,
        cy=(height - 1) / 2.0,
        world_to_camera=camera.world_to_camera,
    )
