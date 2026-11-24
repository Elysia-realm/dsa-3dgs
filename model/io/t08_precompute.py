"""Camera-independent T08 analysis kernels; not a released compressed format.

The current world-covariance RTL has historical q16 port names but 20
fractional bits. Keep its three rounding points and overflow/wrap semantics.
"""
import numpy as np


def quantize(values, fractional_bits, width, signed=True):
    values = np.asarray(values, dtype=np.float64)
    if not np.isfinite(values).all():
        raise ValueError('non-finite model parameter')
    lo, hi = (-(1 << (width-1)), (1 << (width-1))-1) if signed else (0, (1 << width)-1)
    return np.clip(np.rint(values * (1 << fractional_bits)), lo, hi).astype(np.int64)


def _round_shift(values, shift):
    # RTL rounds ties away from zero, unlike np.rint used by the input format.
    magnitude = (np.abs(values) + (1 << (shift-1))) >> shift
    return np.where(values < 0, -magnitude, magnitude)


def _narrow(values, width):
    sign = 1 << (width-1)
    overflow = np.any((values < -sign) | (values >= sign), axis=tuple(range(1, values.ndim)))
    return (values + sign) % (sign*2) - sign, overflow


def world_covariance_q20(quaternion_codes, scale_codes):
    q = np.asarray(quaternion_codes, dtype=np.int64)
    scale = np.asarray(scale_codes, dtype=np.int64)
    if q.ndim != 2 or q.shape[1] != 4 or scale.shape != (len(q),3):
        raise ValueError('expected quaternion Nx4 and scale Nx3 integer codes')
    if np.any(q < -(1<<21)) or np.any(q >= 1<<21) or np.any(scale < 0) or np.any(scale >= 1<<24):
        raise ValueError('outside the existing 22-bit quaternion/24-bit scale contract')
    w,x,y,z = q.T
    one = 1 << 40
    rot = np.stack([one-2*y*y-2*z*z, 2*x*y-2*w*z, 2*x*z+2*w*y,
                    2*x*y+2*w*z, one-2*x*x-2*z*z, 2*y*z-2*w*x,
                    2*x*z-2*w*y, 2*y*z+2*w*x, one-2*x*x-2*y*y],axis=1).reshape(-1,3,3)
    rot, ov_r = _narrow(_round_shift(rot,20),24)
    scaled, ov_s = _narrow(_round_shift(rot*scale[:,None,:],20),28)
    products = np.matmul(scaled, np.swapaxes(scaled,1,2))
    cov = products[:,[0,0,0,1,1,2],[0,1,2,1,2,2]]
    cov, ov_c = _narrow(_round_shift(cov,20),41)
    return cov, ov_r | ov_s | ov_c


def sh_tail_bounds_q12(coefficients):
    """Real-SH all-direction analytic color bound, not an RTL error proof.

    Addition theorem plus Cauchy-Schwarz bounds each omitted band. Threshold
    zero is handled by exact nonzero tests elsewhere; nonzero thresholds
    remain unselected analysis candidates until RTL/GT validation.
    """
    sh = np.asarray(coefficients, dtype=np.int64)
    if sh.ndim != 3 or sh.shape[1:] != (3,16):
        raise ValueError('expected Nx3x16 channel-major SH codes')
    tails = np.zeros((len(sh),4), dtype=np.float64)
    per_channel = np.zeros((len(sh),3),dtype=np.float64)
    for band in range(3,0,-1):
        block = sh[:,:,band*band:(band+1)*(band+1)].astype(np.float64)
        per_channel += np.linalg.norm(block,axis=2)*np.sqrt((2*band+1)/(4*np.pi))
        tails[:,band-1] = per_channel.max(axis=1)
    return tails


def lossless_sh_degree(coefficients):
    sh = np.asarray(coefficients)
    if sh.ndim != 3 or sh.shape[1:] != (3,16):
        raise ValueError('expected Nx3x16 channel-major SH codes')
    degree = np.zeros(len(sh),dtype=np.int64)
    for band in range(1,4):
        degree[np.any(sh[:,:,band*band:(band+1)*(band+1)] != 0,axis=(1,2))] = band
    return degree
