from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class BlendResult:
    rgb_q12: tuple[int, int, int]
    transmittance_q16: int
    newly_terminated: bool


def blend_codes(
    rgb_q12: tuple[int, int, int], transmittance_q16: int,
    color_q12: tuple[int, int, int], alpha_q12: int,
    termination_code_q16: int = 7,
) -> BlendResult:
    """Integer oracle for front-to-back blend using Q1.12 RGB/alpha and Q0.16 T."""
    alpha_q12 = min(max(int(alpha_q12), 0), 4055)
    transmittance_q16 = min(max(int(transmittance_q16), 0), 65535)
    old_terminated = transmittance_q16 <= termination_code_q16
    weight_q16 = (transmittance_q16 * alpha_q12 + 2048) >> 12
    output = []
    for old, color in zip(rgb_q12, color_q12):
        contribution_q12 = (weight_q16 * min(max(int(color), 0), 4096) + 32768) >> 16
        output.append(min(4096, max(0, int(old) + contribution_q12)))
    new_t = (transmittance_q16 * (4096 - alpha_q12) + 2048) >> 12
    new_t = min(65535, max(0, new_t))
    new_terminated = not old_terminated and new_t <= termination_code_q16
    return BlendResult(tuple(output), new_t, new_terminated)
