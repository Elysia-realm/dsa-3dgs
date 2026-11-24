"""Candidate v1, fixed 144-byte slots with variable useful DMA length.

Lossless relative to existing fixed input and its world-covariance stage.
Not the selected production profile until integrated acceptance completes.
"""
import numpy as np
from .t08_precompute import world_covariance_q20

MAGIC = 0xC8
VERSION = 1
RAW_HEADER = MAGIC | (VERSION << 8) | (1 << 10) | (3 << 11) | (1 << 13)


def signed(value, width):
    value &= (1 << width)-1
    return value-(1 << width) if value & (1 << (width-1)) else value


def unpack_legacy(record):
    if record < 0 or record >= 1 << 1118:
        raise ValueError('legacy attribute vector must have exactly 1118 meaningful bits')
    sh = np.array([signed(record >> (18*i),18) for i in range(48)],dtype=np.int64).reshape(3,16)
    scale = [(record >> (877+24*(2-i))) & ((1<<24)-1) for i in range(3)]
    q = [signed(record >> (949+22*(3-i)),22) for i in range(4)]
    return sh, q, scale


def encode_record(record):
    sh,q,scale = unpack_legacy(record)
    cov,overflow = world_covariance_q20([q],[scale])
    cov = cov[0]
    degree = 0
    for band in range(1,4):
        if np.any(sh[:,band*band:(band+1)*(band+1)]):degree=band
    wide = bool(np.any(sh < -(1<<15)) or np.any(sh >= 1<<15))
    width = 18 if wide else 16
    count = (degree+1)**2
    beats = (254+3*count*width+127)//128
    if overflow[0] or np.any(cov < -(1<<23)) or np.any(cov >= 1<<23) or beats >= 9:
        return dict(record=(record << 16)|RAW_HEADER,beats=9,degree=3,precomputed=False)
    header = MAGIC | (VERSION<<8) | (degree<<11) | (int(wide)<<13)
    packed = header | ((record >> 1037) << 16) | (((record >> 864)&8191) << 97)
    for i,value in enumerate(cov):packed |= (int(value)&((1<<24)-1)) << (110+i*24)
    offset = 254
    for channel in range(3):
        for k in range(count):
            packed |= (int(sh[channel,k])&((1<<width)-1)) << offset
            offset += width
    assert offset <= beats*128 and beats < 9
    return dict(record=packed,beats=beats,degree=degree,precomputed=True)


def decode_record(packet, beats):
    """Host inspection helper; RTL tests use original vectors as their oracle."""
    if packet < 0 or packet >= 1 << 1152:
        raise ValueError('packet exceeds nine beats')
    header=packet&65535
    raw=(header>>10)&1;degree=(header>>11)&3;wide=(header>>13)&1
    if header&255!=MAGIC or (header>>8)&3!=VERSION or header>>14:
        raise ValueError('invalid magic, version or reserved header')
    width=18 if wide else 16;count=(degree+1)**2
    expected=9 if raw else (254+3*count*width+127)//128
    if beats!=expected or (raw and header!=RAW_HEADER):
        raise ValueError('noncanonical raw header or wrong packet length')
    if raw:return dict(legacy=(packet>>16)&((1<<1118)-1),covariance=None,degree=3)
    legacy=((packet>>16)&((1<<81)-1))<<1037
    legacy|=((packet>>97)&8191)<<864
    cov=[signed(packet>>(110+i*24),24) for i in range(6)]
    offset=254
    for channel in range(3):
        for k in range(count):
            code=signed(packet>>offset,width)
            legacy|=(code&((1<<18)-1))<<(18*(channel*16+k))
            offset+=width
    return dict(legacy=legacy,covariance=cov,degree=degree)
