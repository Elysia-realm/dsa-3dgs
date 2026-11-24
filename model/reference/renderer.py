from __future__ import annotations

from collections.abc import Iterable

import numpy as np

from .math3d import ProjectedGaussian, alpha_at, project_gaussian
from .model import Camera, Gaussian3D, RenderConfig, RenderResult, RenderStats


def _prepare(
    gaussians: Iterable[Gaussian3D], camera: Camera, config: RenderConfig, stats: RenderStats
) -> tuple[list[ProjectedGaussian], list[list[ProjectedGaussian]]]:
    source = list(gaussians)
    stats.input_gaussians = len(source)
    projected: list[ProjectedGaussian] = []
    for gaussian in source:
        item = project_gaussian(gaussian, camera, config)
        if item is None:
            stats.screen_culled_gaussians += 1
            continue
        projected.append(item)
    stats.visible_gaussians = len(projected)
    stats.projected_gaussians = len(projected)

    # This exact model establishes the required ordering invariant. A later cycle
    # model will replace the implementation with hardware-style coarse binning.
    projected.sort(key=lambda value: (value.depth, value.source.gid))
    groups = [projected[i : i + config.group_size] for i in range(0, len(projected), config.group_size)]
    stats.depth_groups = len(groups)
    return projected, groups


def _empty_state(camera: Camera, config: RenderConfig):
    rgb = np.zeros((camera.height, camera.width, 3), dtype=np.float32)
    transmittance = np.ones((camera.height, camera.width), dtype=np.float32)
    terminated = np.zeros((camera.height, camera.width), dtype=np.bool_)
    return rgb, transmittance, terminated


def _finalize(rgb, transmittance, terminated, sorted_ids, contributing_ids, stats, config):
    rgb += transmittance[..., None] * config.background[None, None, :]
    return RenderResult(
        rgb=np.clip(rgb, 0.0, 1.0).astype(np.float32),
        transmittance=transmittance,
        terminated=terminated,
        sorted_ids=sorted_ids,
        contributing_ids=contributing_ids,
        stats=stats,
    )


def render_pixelwise(
    gaussians: Iterable[Gaussian3D], camera: Camera, config: RenderConfig = RenderConfig()
) -> RenderResult:
    """Slow independent-pixel reference used to check Gaussian-wise execution."""
    stats = RenderStats()
    projected, _ = _prepare(gaussians, camera, config, stats)
    rgb, transmittance, terminated = _empty_state(camera, config)
    contributing: set[int] = set()
    for y in range(camera.height):
        for x in range(camera.width):
            for gaussian in projected:
                x0, y0, x1, y1 = gaussian.bbox
                if not (x0 <= x < x1 and y0 <= y < y1):
                    continue
                stats.pixel_tests += 1
                stats.alpha_evaluations += 1
                alpha = alpha_at(gaussian, x, y, config)
                if alpha < config.alpha_threshold:
                    stats.alpha_pruned += 1
                    continue
                contributing.add(gaussian.source.gid)
                weight = float(transmittance[y, x]) * alpha
                rgb[y, x] += np.float32(weight) * gaussian.color
                transmittance[y, x] *= np.float32(1.0 - alpha)
                stats.blend_updates += 1
                if transmittance[y, x] < config.transmittance_threshold:
                    terminated[y, x] = True
                    stats.terminated_pixels += 1
                    break
    return _finalize(
        rgb,
        transmittance,
        terminated,
        [g.source.gid for g in projected],
        sorted(contributing),
        stats,
        config,
    )


def render_gaussianwise(
    gaussians: Iterable[Gaussian3D], camera: Camera, config: RenderConfig = RenderConfig()
) -> RenderResult:
    """Gaussian-wise renderer with block traversal and per-pixel termination."""
    stats = RenderStats()
    projected, groups = _prepare(gaussians, camera, config, stats)
    rgb, transmittance, terminated = _empty_state(camera, config)
    contributing: set[int] = set()
    block = config.block_size

    for group in groups:
        if bool(np.all(terminated)):
            break
        for gaussian in group:
            x0, y0, x1, y1 = gaussian.bbox
            bx0, by0 = x0 // block, y0 // block
            bx1, by1 = (x1 - 1) // block, (y1 - 1) // block
            for by in range(by0, by1 + 1):
                py0, py1 = max(y0, by * block), min(y1, (by + 1) * block)
                for bx in range(bx0, bx1 + 1):
                    stats.gaussian_block_tests += 1
                    px0, px1 = max(x0, bx * block), min(x1, (bx + 1) * block)
                    if bool(np.all(terminated[py0:py1, px0:px1])):
                        stats.skipped_terminated_pixels += (py1 - py0) * (px1 - px0)
                        continue
                    stats.active_block_visits += 1
                    for y in range(py0, py1):
                        for x in range(px0, px1):
                            stats.pixel_tests += 1
                            if terminated[y, x]:
                                stats.skipped_terminated_pixels += 1
                                continue
                            stats.alpha_evaluations += 1
                            alpha = alpha_at(gaussian, x, y, config)
                            if alpha < config.alpha_threshold:
                                stats.alpha_pruned += 1
                                continue
                            contributing.add(gaussian.source.gid)
                            weight = float(transmittance[y, x]) * alpha
                            rgb[y, x] += np.float32(weight) * gaussian.color
                            transmittance[y, x] *= np.float32(1.0 - alpha)
                            stats.blend_updates += 1
                            if transmittance[y, x] < config.transmittance_threshold:
                                terminated[y, x] = True
                                stats.terminated_pixels += 1

    return _finalize(
        rgb,
        transmittance,
        terminated,
        [g.source.gid for g in projected],
        sorted(contributing),
        stats,
        config,
    )

