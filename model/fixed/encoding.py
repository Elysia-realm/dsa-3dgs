from __future__ import annotations

import numpy as np

from .alpha import cholesky_factors


def _round_clip(value, fractional_bits, minimum, maximum):
    code = np.rint(np.asarray(value, dtype=np.float64) * (1 << fractional_bits)).astype(np.int64)
    return np.clip(code, minimum, maximum)


def encode_block_float_gaussian(
    mean_x, mean_y, screen_x0, screen_y0, screen_x1, screen_y1,
    conic00, conic01, conic11, opacity,
):
    """Encode one or more projected Gaussians for alpha_block_float_core."""
    mean_x, mean_y = np.broadcast_arrays(np.asarray(mean_x), np.asarray(mean_y))
    extent = np.maximum(
        np.maximum(np.abs(np.asarray(screen_x0) - mean_x), np.abs((np.asarray(screen_x1) - 1) - mean_x)),
        np.maximum(np.abs(np.asarray(screen_y0) - mean_y), np.abs((np.asarray(screen_y1) - 1) - mean_y)),
    )
    coordinate_shift = np.maximum(0, np.ceil(np.log2(np.maximum(1.0, extent) / 16.0))).astype(np.int64)
    l00, l10, l11 = cholesky_factors(conic00, conic01, conic11)
    factor_extent = np.maximum.reduce((np.abs(l00), np.abs(l10), np.abs(l11)))
    factor_shift = np.ceil(np.log2(np.maximum(factor_extent, 2.0 ** -30) / 4.0)).astype(np.int64)
    factor_scale = np.exp2(factor_shift)
    return {
        "coordinate_shift": np.clip(coordinate_shift, -32, 31).astype(np.int64),
        "factor_shift": np.clip(factor_shift, -32, 31).astype(np.int64),
        "l00_q12": _round_clip(l00 / factor_scale, 12, 0, (1 << 15) - 1),
        "l10_q12": _round_clip(l10 / factor_scale, 12, -(1 << 15), (1 << 15) - 1),
        "l11_q12": _round_clip(l11 / factor_scale, 12, 0, (1 << 15) - 1),
        "opacity_q12": _round_clip(opacity, 12, 0, 4096),
    }


def encode_pixel_delta(pixel_x, pixel_y, mean_x, mean_y, coordinate_shift):
    coordinate_scale = np.exp2(np.asarray(coordinate_shift, dtype=np.int64))
    return (
        _round_clip((np.asarray(pixel_x) - np.asarray(mean_x)) / coordinate_scale, 10, -(1 << 15), (1 << 15) - 1),
        _round_clip((np.asarray(pixel_y) - np.asarray(mean_y)) / coordinate_scale, 10, -(1 << 15), (1 << 15) - 1),
    )
