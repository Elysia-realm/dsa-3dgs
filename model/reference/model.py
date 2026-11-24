from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
from numpy.typing import NDArray


F32 = NDArray[np.float32]


def _f32(value) -> F32:
    return np.asarray(value, dtype=np.float32)


@dataclass(frozen=True)
class Camera:
    """Pinhole camera using a world-to-camera transform."""

    width: int
    height: int
    fx: float
    fy: float
    cx: float
    cy: float
    world_to_camera: F32 = field(default_factory=lambda: np.eye(4, dtype=np.float32))

    def __post_init__(self):
        if self.width <= 0 or self.height <= 0:
            raise ValueError("camera width and height must be positive")
        if self.fx <= 0 or self.fy <= 0:
            raise ValueError("camera focal lengths must be positive")
        matrix = _f32(self.world_to_camera)
        if matrix.shape != (4, 4):
            raise ValueError("world_to_camera must have shape (4, 4)")
        object.__setattr__(self, "world_to_camera", matrix)

    @property
    def position_world(self) -> F32:
        rotation = self.world_to_camera[:3, :3]
        translation = self.world_to_camera[:3, 3]
        return (-rotation.T @ translation).astype(np.float32)


@dataclass(frozen=True)
class Gaussian3D:
    """A trained 3D Gaussian with either RGB or real SH coefficients."""

    gid: int
    mean: F32
    scale: F32
    quaternion: F32
    opacity: float
    rgb: F32 | None = None
    sh: F32 | None = None

    def __post_init__(self):
        mean = _f32(self.mean)
        scale = _f32(self.scale)
        quaternion = _f32(self.quaternion)
        if mean.shape != (3,) or scale.shape != (3,) or quaternion.shape != (4,):
            raise ValueError("mean/scale/quaternion must have shapes (3,)/(3,)/(4,)")
        if np.any(scale <= 0):
            raise ValueError("scale values must be positive")
        if not 0.0 <= float(self.opacity) <= 1.0:
            raise ValueError("opacity must be in [0, 1]")
        norm = float(np.linalg.norm(quaternion))
        if norm <= 1e-12:
            raise ValueError("quaternion must be non-zero")
        quaternion = quaternion / np.float32(norm)
        rgb = None if self.rgb is None else _f32(self.rgb)
        sh = None if self.sh is None else _f32(self.sh)
        if rgb is not None and rgb.shape != (3,):
            raise ValueError("rgb must have shape (3,)")
        if sh is not None and (sh.ndim != 2 or sh.shape[0] != 3 or sh.shape[1] not in (1, 4, 9, 16)):
            raise ValueError("sh must have shape (3, 1|4|9|16)")
        if rgb is None and sh is None:
            raise ValueError("either rgb or sh coefficients must be provided")
        object.__setattr__(self, "mean", mean)
        object.__setattr__(self, "scale", scale)
        object.__setattr__(self, "quaternion", quaternion.astype(np.float32))
        object.__setattr__(self, "rgb", rgb)
        object.__setattr__(self, "sh", sh)


@dataclass(frozen=True)
class RenderConfig:
    alpha_threshold: float = 1.0 / 255.0
    transmittance_threshold: float = 1.0e-4
    alpha_max: float = 0.99
    near: float = 0.2
    far: float = 1.0e5
    covariance_regularizer: float = 0.3
    sigma_limit: float = 3.0
    block_size: int = 8
    group_size: int = 256
    background: F32 = field(default_factory=lambda: np.zeros(3, dtype=np.float32))

    def __post_init__(self):
        if not 0.0 < self.alpha_threshold < 1.0:
            raise ValueError("alpha_threshold must be in (0, 1)")
        if not 0.0 < self.transmittance_threshold < 1.0:
            raise ValueError("transmittance_threshold must be in (0, 1)")
        if not 0.0 < self.alpha_max <= 1.0:
            raise ValueError("alpha_max must be in (0, 1]")
        if self.near <= 0 or self.far <= self.near:
            raise ValueError("invalid near/far range")
        if self.block_size <= 0 or self.group_size <= 0:
            raise ValueError("block_size and group_size must be positive")
        background = _f32(self.background)
        if background.shape != (3,):
            raise ValueError("background must have shape (3,)")
        object.__setattr__(self, "background", background)


@dataclass
class RenderStats:
    input_gaussians: int = 0
    visible_gaussians: int = 0
    depth_groups: int = 0
    projected_gaussians: int = 0
    screen_culled_gaussians: int = 0
    gaussian_block_tests: int = 0
    active_block_visits: int = 0
    pixel_tests: int = 0
    alpha_evaluations: int = 0
    alpha_pruned: int = 0
    blend_updates: int = 0
    terminated_pixels: int = 0
    skipped_terminated_pixels: int = 0


@dataclass
class RenderResult:
    rgb: F32
    transmittance: F32
    terminated: NDArray[np.bool_]
    sorted_ids: list[int]
    contributing_ids: list[int]
    stats: RenderStats

