"""Batch implementation of candidate v1; checked bit-for-bit against scalar codec."""
import numpy as np
from .t08_attribute_codec import unpack_legacy,RAW_HEADER,MAGIC,VERSION
from .t08_precompute import world_covariance_q20,lossless_sh_degree

def encode_records(records):
    if not records:return []
    decoded=[unpack_legacy(r) for r in records]
    sh=np.stack([x[0] for x in decoded]);q=np.array([x[1] for x in decoded]);scale=np.array([x[2] for x in decoded])
    cov,overflow=world_covariance_q20(q,scale);degree=lossless_sh_degree(sh)
    wide=np.any((sh<-(1<<15))|(sh>=(1<<15)),axis=(1,2))
    result=[]
    for i,raw in enumerate(records):
        d=int(degree[i]);width=18 if wide[i] else 16;count=(d+1)**2;beats=(254+3*count*width+127)//128
        if overflow[i] or np.any(cov[i]<-(1<<23)) or np.any(cov[i]>=(1<<23)) or beats>=9:
            result.append(dict(record=(raw<<16)|RAW_HEADER,beats=9,degree=3,precomputed=False));continue
        packed=MAGIC|(VERSION<<8)|(d<<11)|(int(wide[i])<<13)|((raw>>1037)<<16)|(((raw>>864)&8191)<<97)
        for k,v in enumerate(cov[i]):packed|=(int(v)&((1<<24)-1))<<(110+k*24)
        offset=254
        for c in range(3):
            for k in range(count):
                packed|=(int(sh[i,c,k])&((1<<width)-1))<<offset;offset+=width
        result.append(dict(record=packed,beats=beats,degree=d,precomputed=True))
    return result
