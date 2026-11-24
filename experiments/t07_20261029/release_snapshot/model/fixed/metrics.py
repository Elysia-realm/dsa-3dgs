from __future__ import annotations

import importlib.util
from math import log10

import numpy as np


def _validate(reference, candidate):
    reference = np.asarray(reference, dtype=np.float64)
    candidate = np.asarray(candidate, dtype=np.float64)
    if reference.shape != candidate.shape:
        raise ValueError("images must have identical shapes")
    if reference.ndim not in (2, 3):
        raise ValueError("images must be HxW or HxWxC")
    return np.clip(reference, 0.0, 1.0), np.clip(candidate, 0.0, 1.0)


def psnr(reference, candidate, data_range=1.0):
    reference, candidate = _validate(reference, candidate)
    mse = float(np.mean((reference - candidate) ** 2))
    return float("inf") if mse == 0.0 else 10.0 * log10(data_range * data_range / mse)


def _box_filter(image, window=11):
    window = min(window, image.shape[0], image.shape[1])
    if window % 2 == 0:
        window -= 1
    if window <= 1:
        return image.astype(np.float64, copy=False)
    pad = window // 2
    padded = np.pad(image, ((pad, pad), (pad, pad)), mode="reflect")
    integral = np.pad(padded, ((1, 0), (1, 0)), mode="constant").cumsum(0).cumsum(1)
    return (
        integral[window:, window:] - integral[:-window, window:]
        - integral[window:, :-window] + integral[:-window, :-window]
    ) / (window * window)


def ssim(reference, candidate, data_range=1.0, window=11):
    reference, candidate = _validate(reference, candidate)
    if reference.ndim == 2:
        reference = reference[..., None]
        candidate = candidate[..., None]
    values = []
    c1 = (0.01 * data_range) ** 2
    c2 = (0.03 * data_range) ** 2
    for channel in range(reference.shape[2]):
        x, y = reference[..., channel], candidate[..., channel]
        ux, uy = _box_filter(x, window), _box_filter(y, window)
        vx = _box_filter(x * x, window) - ux * ux
        vy = _box_filter(y * y, window) - uy * uy
        covariance = _box_filter(x * y, window) - ux * uy
        score = ((2 * ux * uy + c1) * (2 * covariance + c2)) / (
            (ux * ux + uy * uy + c1) * (vx + vy + c2)
        )
        values.append(float(np.mean(score)))
    return float(np.mean(values))


def lpips_status():
    available = importlib.util.find_spec("torch") is not None and importlib.util.find_spec("lpips") is not None
    return {
        "available": available,
        "reason": None if available else "local bundled runtime currently lacks torch and lpips",
    }


def lpips_distance(reference, candidate, net="alex", device="cpu"):
    """Compute LPIPS using an already prepared local torch/lpips runtime."""
    status = lpips_status()
    if not status["available"]:
        raise RuntimeError(status["reason"])
    import lpips as lpips_package
    import torch

    reference, candidate = _validate(reference, candidate)
    if reference.ndim == 2:
        reference = np.repeat(reference[..., None], 3, axis=2)
        candidate = np.repeat(candidate[..., None], 3, axis=2)
    if reference.shape[2] == 1:
        reference = np.repeat(reference, 3, axis=2)
        candidate = np.repeat(candidate, 3, axis=2)
    if reference.shape[2] != 3:
        raise ValueError("LPIPS expects one or three image channels")
    x = torch.from_numpy(reference.transpose(2, 0, 1)).float().unsqueeze(0)
    y = torch.from_numpy(candidate.transpose(2, 0, 1)).float().unsqueeze(0)
    x = x.to(device) * 2.0 - 1.0
    y = y.to(device) * 2.0 - 1.0
    metric = lpips_package.LPIPS(net=net).to(device)
    metric.eval()
    with torch.no_grad():
        return float(metric(x, y).item())


def image_metrics(reference, candidate, *, compute_lpips=False, lpips_net="alex", device="cpu"):
    result = {
        "psnr": psnr(reference, candidate),
        "ssim": ssim(reference, candidate),
        "lpips": None,
        "lpips_status": lpips_status(),
    }
    if compute_lpips:
        result["lpips"] = lpips_distance(reference, candidate, net=lpips_net, device=device)
    return result
