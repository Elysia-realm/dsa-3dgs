from __future__ import annotations

from dataclasses import dataclass

import numpy as np


def quantize_signed(value, integer_bits: int, fractional_bits: int):
    scale = 1 << fractional_bits
    minimum = -(1 << (integer_bits + fractional_bits))
    maximum = (1 << (integer_bits + fractional_bits)) - 1
    integer = np.rint(np.asarray(value, dtype=np.float64) * scale).astype(np.int64)
    integer = np.clip(integer, minimum, maximum)
    return integer.astype(np.float64) / scale


def quantize_unsigned(value, integer_bits: int, fractional_bits: int):
    scale = 1 << fractional_bits
    maximum = (1 << (integer_bits + fractional_bits)) - 1
    integer = np.rint(np.asarray(value, dtype=np.float64) * scale).astype(np.int64)
    integer = np.clip(integer, 0, maximum)
    return integer.astype(np.float64) / scale


@dataclass(frozen=True)
class AlphaFixedConfig:
    delta_integer_bits: int = 5
    delta_fractional_bits: int = 10
    conic_integer_bits: int = 8
    conic_fractional_bits: int = 12
    exponent_fractional_bits: int = 12
    opacity_fractional_bits: int = 12
    alpha_fractional_bits: int = 12
    exp_lut_entries: int = 256
    exp_domain_min: float = -16.0
    alpha_max: float = 0.99
    alpha_threshold: float = 1.0 / 255.0

    def __post_init__(self):
        widths = (
            self.delta_integer_bits, self.delta_fractional_bits,
            self.conic_integer_bits, self.conic_fractional_bits,
            self.exponent_fractional_bits, self.opacity_fractional_bits,
            self.alpha_fractional_bits, self.exp_lut_entries,
        )
        if min(widths) <= 0:
            raise ValueError("fixed-point widths and LUT entries must be positive")
        if self.exp_lut_entries < 2:
            raise ValueError("exp_lut_entries must be at least two")


def alpha_float(dx, dy, conic00, conic01, conic11, opacity, alpha_max=0.99):
    exponent = -0.5 * (
        conic00 * np.asarray(dx) ** 2
        + 2.0 * conic01 * np.asarray(dx) * np.asarray(dy)
        + conic11 * np.asarray(dy) ** 2
    )
    exponent = np.minimum(exponent, 0.0)
    return np.minimum(alpha_max, np.asarray(opacity) * np.exp(exponent))


def _exp_lut(exponent, config: AlphaFixedConfig):
    exponent = np.clip(exponent, config.exp_domain_min, 0.0)
    position = (exponent - config.exp_domain_min) / (-config.exp_domain_min)
    index = np.rint(position * (config.exp_lut_entries - 1)).astype(np.int64)
    grid = np.linspace(config.exp_domain_min, 0.0, config.exp_lut_entries)
    values = quantize_unsigned(np.exp(grid), 1, config.alpha_fractional_bits)
    return values[index]


def alpha_fixed(
    dx, dy, conic00, conic01, conic11, opacity,
    config=AlphaFixedConfig(), *, apply_threshold: bool = True,
):
    dx_q = quantize_signed(dx, config.delta_integer_bits, config.delta_fractional_bits)
    dy_q = quantize_signed(dy, config.delta_integer_bits, config.delta_fractional_bits)
    c00_q = quantize_signed(conic00, config.conic_integer_bits, config.conic_fractional_bits)
    c01_q = quantize_signed(conic01, config.conic_integer_bits, config.conic_fractional_bits)
    c11_q = quantize_signed(conic11, config.conic_integer_bits, config.conic_fractional_bits)
    quadratic = c00_q * dx_q * dx_q + 2.0 * c01_q * dx_q * dy_q + c11_q * dy_q * dy_q
    exponent = quantize_signed(-0.5 * quadratic, 5, config.exponent_fractional_bits)
    exponent = np.minimum(exponent, 0.0)
    exp_value = _exp_lut(exponent, config)
    opacity_q = quantize_unsigned(opacity, 1, config.opacity_fractional_bits)
    alpha = quantize_unsigned(opacity_q * exp_value, 1, config.alpha_fractional_bits)
    alpha = np.minimum(config.alpha_max, alpha)
    if apply_threshold:
        alpha = np.where(alpha >= config.alpha_threshold, alpha, 0.0)
    return alpha


def alpha_fixed_shared_scale(
    dx, dy, conic00, conic01, conic11, opacity, scale_shift,
    config=AlphaFixedConfig(), *, apply_threshold: bool = True,
):
    """Evaluate alpha after an exact power-of-two shared-scale transform."""
    scale_shift = np.asarray(scale_shift, dtype=np.int64)
    coordinate_scale = np.exp2(scale_shift)
    conic_scale = np.exp2(2 * scale_shift)
    return alpha_fixed(
        np.asarray(dx) / coordinate_scale,
        np.asarray(dy) / coordinate_scale,
        np.asarray(conic00) * conic_scale,
        np.asarray(conic01) * conic_scale,
        np.asarray(conic11) * conic_scale,
        opacity,
        config=config,
        apply_threshold=apply_threshold,
    )


def cholesky_factors(conic00, conic01, conic11):
    """Return L for C=L*L.T, clamping only round-off-negative residuals."""
    c00 = np.maximum(np.asarray(conic00, dtype=np.float64), 0.0)
    c01 = np.asarray(conic01, dtype=np.float64)
    c11 = np.maximum(np.asarray(conic11, dtype=np.float64), 0.0)
    l00 = np.sqrt(c00)
    safe_l00 = np.where(l00 > 0.0, l00, 1.0)
    l10 = np.where(l00 > 0.0, c01 / safe_l00, 0.0)
    l11 = np.sqrt(np.maximum(c11 - l10 * l10, 0.0))
    return l00, l10, l11


def alpha_fixed_cholesky_shared_scale(
    dx, dy, conic00, conic01, conic11, opacity, scale_shift,
    config=AlphaFixedConfig(), *, factor_integer_bits: int = 8,
    factor_fractional_bits: int = 14, apply_threshold: bool = True,
):
    """PSD-preserving alpha using quantized Cholesky factors and shared scale."""
    shift = np.asarray(scale_shift, dtype=np.int64)
    coordinate_scale = np.exp2(shift)
    factor_scale = coordinate_scale
    dx_q = quantize_signed(
        np.asarray(dx) / coordinate_scale,
        config.delta_integer_bits,
        config.delta_fractional_bits,
    )
    dy_q = quantize_signed(
        np.asarray(dy) / coordinate_scale,
        config.delta_integer_bits,
        config.delta_fractional_bits,
    )
    l00, l10, l11 = cholesky_factors(conic00, conic01, conic11)
    l00_q = quantize_unsigned(l00 * factor_scale, factor_integer_bits, factor_fractional_bits)
    l10_q = quantize_signed(l10 * factor_scale, factor_integer_bits, factor_fractional_bits)
    l11_q = quantize_unsigned(l11 * factor_scale, factor_integer_bits, factor_fractional_bits)
    axis0 = l00_q * dx_q + l10_q * dy_q
    axis1 = l11_q * dy_q
    exponent = quantize_signed(
        -0.5 * (axis0 * axis0 + axis1 * axis1),
        5,
        config.exponent_fractional_bits,
    )
    exponent = np.minimum(exponent, 0.0)
    exp_value = _exp_lut(exponent, config)
    opacity_q = quantize_unsigned(opacity, 1, config.opacity_fractional_bits)
    alpha = quantize_unsigned(opacity_q * exp_value, 1, config.alpha_fractional_bits)
    alpha = np.minimum(config.alpha_max, alpha)
    if apply_threshold:
        alpha = np.where(alpha >= config.alpha_threshold, alpha, 0.0)
    return alpha


def alpha_fixed_cholesky_block_float(
    dx, dy, conic00, conic01, conic11, opacity,
    coordinate_shift, factor_shift, config=AlphaFixedConfig(), *,
    factor_integer_bits: int = 3, factor_fractional_bits: int = 12,
    axis_integer_bits: int = 4, axis_fractional_bits: int = 12,
    apply_threshold: bool = True,
):
    """PSD-preserving block-float alpha with independent coordinate/factor exponents."""
    coordinate_shift = np.asarray(coordinate_shift, dtype=np.int64)
    factor_shift = np.asarray(factor_shift, dtype=np.int64)
    coordinate_scale = np.exp2(coordinate_shift)
    factor_scale = np.exp2(factor_shift)
    dx_q = quantize_signed(
        np.asarray(dx) / coordinate_scale,
        config.delta_integer_bits,
        config.delta_fractional_bits,
    )
    dy_q = quantize_signed(
        np.asarray(dy) / coordinate_scale,
        config.delta_integer_bits,
        config.delta_fractional_bits,
    )
    l00, l10, l11 = cholesky_factors(conic00, conic01, conic11)
    l00_q = quantize_unsigned(l00 / factor_scale, factor_integer_bits, factor_fractional_bits)
    l10_q = quantize_signed(l10 / factor_scale, factor_integer_bits, factor_fractional_bits)
    l11_q = quantize_unsigned(l11 / factor_scale, factor_integer_bits, factor_fractional_bits)
    result_scale = np.exp2(coordinate_shift + factor_shift)
    axis0 = quantize_signed(
        (l00_q * dx_q + l10_q * dy_q) * result_scale,
        axis_integer_bits,
        axis_fractional_bits,
    )
    axis1 = quantize_signed(
        (l11_q * dy_q) * result_scale,
        axis_integer_bits,
        axis_fractional_bits,
    )
    exponent = quantize_signed(
        -0.5 * (axis0 * axis0 + axis1 * axis1),
        5,
        config.exponent_fractional_bits,
    )
    exponent = np.minimum(exponent, 0.0)
    exp_value = _exp_lut(exponent, config)
    opacity_q = quantize_unsigned(opacity, 1, config.opacity_fractional_bits)
    alpha = quantize_unsigned(opacity_q * exp_value, 1, config.alpha_fractional_bits)
    alpha = np.minimum(config.alpha_max, alpha)
    if apply_threshold:
        alpha = np.where(alpha >= config.alpha_threshold, alpha, 0.0)
    return alpha


def alpha_block_float_codes(
    dx_code, dy_code, l00_code, l10_code, l11_code,
    coordinate_shift, factor_shift, opacity_code,
):
    """Integer oracle for alpha_block_float_core.sv transaction arithmetic."""
    dx_code = np.asarray(dx_code, dtype=np.int64)
    dy_code = np.asarray(dy_code, dtype=np.int64)
    l00_code = np.asarray(l00_code, dtype=np.int64)
    l10_code = np.asarray(l10_code, dtype=np.int64)
    l11_code = np.asarray(l11_code, dtype=np.int64)
    result_shift = np.asarray(coordinate_shift, dtype=np.int64) + np.asarray(factor_shift, dtype=np.int64)

    def round_shift_signed(value, right_shift):
        value = np.asarray(value, dtype=np.int64)
        right_shift = np.asarray(right_shift, dtype=np.int64)
        result = np.zeros(np.broadcast_shapes(value.shape, right_shift.shape), dtype=np.int64)
        value, right_shift = np.broadcast_arrays(value, right_shift)
        left = right_shift <= 0
        result[left] = value[left] << np.minimum(-right_shift[left], 30)
        active = (right_shift > 0) & (right_shift < 63)
        magnitude = np.abs(value[active])
        result[active] = np.sign(value[active]) * (
            (magnitude + (1 << (right_shift[active] - 1))) >> right_shift[active]
        )
        return result

    product0 = l00_code * dx_code + l10_code * dy_code
    product1 = l11_code * dy_code
    axis0 = np.clip(round_shift_signed(product0, 12 - result_shift), -16384, 16383)
    axis1 = np.clip(round_shift_signed(product1, 12 - result_shift), -16384, 16383)
    quadratic = axis0 * axis0 + axis1 * axis1
    magnitude_q12 = np.minimum(65535, (quadratic + 256) >> 9)
    lut_index = np.where(
        magnitude_q12 >= 65535,
        0,
        255 - ((magnitude_q12 * 255 + 32768) >> 16),
    ).astype(np.int64)
    lut = np.rint(np.exp(np.linspace(-16.0, 0.0, 256)) * 4096.0).astype(np.int64)
    exp_code = lut[lut_index]
    alpha_code = np.minimum(4055, (np.asarray(opacity_code, dtype=np.int64) * exp_code + 2048) >> 12)
    return alpha_code, alpha_code >= 16


def conservative_shape_block_reject_code(
    y0: int, y1: int, mean_y_q8: int, coordinate_shift: int,
    factor_shift: int, l11_code: int, opacity_code: int,
) -> bool:
    """Mirror the RTL one-axis proof for an already clipped block row range."""
    if y0 >= y1:
        return False

    def encode_delta(pixel: int) -> int:
        delta_q8 = (int(pixel) << 8) - int(mean_y_q8)
        if coordinate_shift >= 0:
            if coordinate_shift == 0:
                scaled = delta_q8 << 2
            elif coordinate_shift >= 63:
                scaled = 0
            else:
                magnitude = ((abs(delta_q8) << 2) + (1 << (coordinate_shift - 1))) >> coordinate_shift
                scaled = -magnitude if delta_q8 < 0 else magnitude
        elif coordinate_shift <= -30:
            scaled = -(2**63 - 1) if delta_q8 < 0 else 2**63 - 1
        else:
            scaled = delta_q8 << (2 - coordinate_shift)
        return min(32767, max(-32768, scaled))

    lower_q8, upper_q8 = y0 << 8, (y1 - 1) << 8
    if lower_q8 <= mean_y_q8 <= upper_q8:
        min_dy = 0
    else:
        min_dy = encode_delta(y0 if mean_y_q8 < lower_q8 else y1 - 1)
    product = min_dy * int(l11_code)
    shift = int(coordinate_shift) + int(factor_shift)
    if shift >= 12:
        axis = (-16384 if product < 0 else 16383) if shift - 12 >= 31 else product << (shift - 12)
    else:
        right = 12 - shift
        if right >= 63:
            axis = 0
        else:
            rounded = (abs(product) + (1 << (right - 1))) >> right
            axis = -rounded if product < 0 else rounded
    axis = min(16383, max(-16384, axis))
    if opacity_code <= 512:
        threshold = 2703
    elif opacity_code <= 1024:
        threshold = 2959
    elif opacity_code <= 2048:
        threshold = 3214
    elif opacity_code <= 4096:
        threshold = 3413
    else:
        threshold = 3637
    return opacity_code == 0 or abs(axis) >= threshold
