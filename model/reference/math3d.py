from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from numpy.typing import NDArray

from .model import Camera, Gaussian3D, RenderConfig


F32 = NDArray[np.float32]


@dataclass(frozen=True)
class ProjectedGaussian:
    source: Gaussian3D
    depth: float
    mean2d: F32
    conic: F32
    covariance2d: F32
    color: F32
    bbox: tuple[int, int, int, int]


def quaternion_to_rotation(quaternion: F32) -> F32:
    """Convert normalized (w, x, y, z) quaternion to a rotation matrix."""
    w, x, y, z = [np.float32(v) for v in quaternion]
    return np.asarray(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
            [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
            [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)],
        ],
        dtype=np.float32,
    )


def covariance3d(gaussian: Gaussian3D) -> F32:
    rotation = quaternion_to_rotation(gaussian.quaternion)
    scale2 = np.diag(np.square(gaussian.scale)).astype(np.float32)
    return (rotation @ scale2 @ rotation.T).astype(np.float32)


def sh_basis(direction: F32, count: int) -> F32:
    """Real SH basis in the coefficient order used by the original 3DGS code."""
    x, y, z = [np.float32(v) for v in direction]
    basis = [0.28209479177387814]
    if count >= 4:
        basis.extend((-0.4886025119029199 * y, 0.4886025119029199 * z, -0.4886025119029199 * x))
    if count >= 9:
        basis.extend(
            (
                1.0925484305920792 * x * y,
                -1.0925484305920792 * y * z,
                0.31539156525252005 * (2 * z * z - x * x - y * y),
                -1.0925484305920792 * x * z,
                0.5462742152960396 * (x * x - y * y),
            )
        )
    if count >= 16:
        basis.extend(
            (
                -0.5900435899266435 * y * (3 * x * x - y * y),
                2.890611442640554 * x * y * z,
                -0.4570457994644658 * y * (4 * z * z - x * x - y * y),
                0.3731763325901154 * z * (2 * z * z - 3 * x * x - 3 * y * y),
                -0.4570457994644658 * x * (4 * z * z - x * x - y * y),
                1.445305721320277 * z * (x * x - y * y),
                -0.5900435899266435 * x * (x * x - 3 * y * y),
            )
        )
    return np.asarray(basis[:count], dtype=np.float32)


def gaussian_color(gaussian: Gaussian3D, camera: Camera) -> F32:
    if gaussian.rgb is not None:
        return np.clip(gaussian.rgb, 0.0, 1.0).astype(np.float32)
    view_direction = gaussian.mean - camera.position_world
    norm = float(np.linalg.norm(view_direction))
    if norm <= 1e-12:
        view_direction = np.asarray((0.0, 0.0, 1.0), dtype=np.float32)
    else:
        view_direction = (view_direction / np.float32(norm)).astype(np.float32)
    basis = sh_basis(view_direction, gaussian.sh.shape[1])
    # The original 3DGS renderer adds 0.5 after SH evaluation.
    return np.clip(gaussian.sh @ basis + np.float32(0.5), 0.0, 1.0).astype(np.float32)


def project_gaussian(gaussian: Gaussian3D, camera: Camera, config: RenderConfig) -> ProjectedGaussian | None:
    homogeneous = np.append(gaussian.mean, np.float32(1.0)).astype(np.float32)
    camera_mean = (camera.world_to_camera @ homogeneous)[:3].astype(np.float32)
    x, y, z = [float(v) for v in camera_mean]
    if not config.near <= z <= config.far:
        return None

    mean2d = np.asarray((camera.fx * x / z + camera.cx, camera.fy * y / z + camera.cy), dtype=np.float32)
    # Match official 3DGS computeCov2D: limit off-screen ray slopes for
    # covariance only, otherwise near-camera off-screen splats can cover the
    # whole image. Keep mean2d above unchanged.
    jac_xz = float(np.clip(x/z, -1.3*camera.width/(2*camera.fx), 1.3*camera.width/(2*camera.fx)))
    jac_yz = float(np.clip(y/z, -1.3*camera.height/(2*camera.fy), 1.3*camera.height/(2*camera.fy)))
    jacobian = np.asarray(
        (
            (camera.fx / z, 0.0, -camera.fx * jac_xz / z),
            (0.0, camera.fy / z, -camera.fy * jac_yz / z),
        ),
        dtype=np.float32,
    )
    view_rotation = camera.world_to_camera[:3, :3]
    cov_camera = (view_rotation @ covariance3d(gaussian) @ view_rotation.T).astype(np.float32)
    covariance2d = (jacobian @ cov_camera @ jacobian.T).astype(np.float32)
    covariance2d += np.eye(2, dtype=np.float32) * np.float32(config.covariance_regularizer)
    determinant = float(np.linalg.det(covariance2d))
    if determinant <= 1e-12 or not np.isfinite(determinant):
        return None
    conic = np.linalg.inv(covariance2d).astype(np.float32)

    max_eigenvalue = max(float(v) for v in np.linalg.eigvalsh(covariance2d))
    if gaussian.opacity < config.alpha_threshold:
        return None
    opacity_radius = np.sqrt(max(0.0, 2.0 * np.log(gaussian.opacity / config.alpha_threshold)))
    radius_sigma = min(config.sigma_limit, float(opacity_radius))
    radius = int(np.ceil(radius_sigma * np.sqrt(max_eigenvalue)))
    radius = max(radius, 1)
    x0 = max(0, int(np.floor(mean2d[0])) - radius)
    y0 = max(0, int(np.floor(mean2d[1])) - radius)
    x1 = min(camera.width, int(np.floor(mean2d[0])) + radius + 1)
    y1 = min(camera.height, int(np.floor(mean2d[1])) + radius + 1)
    if x0 >= x1 or y0 >= y1:
        return None
    return ProjectedGaussian(
        source=gaussian,
        depth=z,
        mean2d=mean2d,
        conic=conic,
        covariance2d=covariance2d,
        color=gaussian_color(gaussian, camera),
        bbox=(x0, y0, x1, y1),
    )


def alpha_at(projected: ProjectedGaussian, x: int, y: int, config: RenderConfig) -> float:
    # Pixel centers are located at integer coordinates in the original rasterizer.
    delta = np.asarray((np.float32(x) - projected.mean2d[0], np.float32(y) - projected.mean2d[1]), dtype=np.float32)
    exponent = -0.5 * float(delta.T @ projected.conic @ delta)
    if exponent > 0.0:
        exponent = 0.0
    alpha = float(projected.source.opacity) * float(np.exp(exponent))
    return min(config.alpha_max, alpha)

