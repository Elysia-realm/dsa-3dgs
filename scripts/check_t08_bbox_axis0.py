"""Check interval RTL against all pixels of small boxes and threshold neighbors."""
import random
from pathlib import Path
import sys
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,WORK,read,save,sha,run_logged
from verification.test_shape_block_reject import rtl_delta
from model.fixed.alpha import alpha_block_float_codes


def verify_batch(rows,stream):
    vectors=np.array(rows,dtype=np.int64)
    x,y,x1,y1,mx,my,l00,l10,cs,fs,op=vectors.T
    # Enumerate all pixels, including signed half ties and saturated deltas.
    samples=np.arange(8)
    dx=np.array([[rtl_delta(int(px+i),int(m),int(s)) for i in samples] for px,m,s in zip(x,mx,cs)])
    dy=np.array([[rtl_delta(int(py+i),int(m),int(s)) for i in samples] for py,m,s in zip(y,my,cs)])
    prod=l00[:,None,None]*dx[:,None,:]+l10[:,None,None]*dy[:,:,None]
    shift=(12-cs-fs)[:,None,None]
    mag=np.abs(prod)
    rounded=np.where(shift<=0,mag<<np.clip(-shift,0,21),(mag+(1<<np.clip(shift-1,0,62)))>>np.clip(shift,0,62))
    active=(samples[None,None,:]<(x1-x)[:,None,None])&(samples[None,:,None]<(y1-y)[:,None,None])
    minimum=np.where(active,prod,2**50).min(axis=(1,2))
    maximum=np.where(active,prod,-2**50).max(axis=(1,2))
    # A zero crossing deliberately disables the interval bound even for
    # discrete pixel locations where no sample equals zero.
    threshold=np.select([op<=512,op<=1024,op<=2048,op<=4096],[2703,2959,3214,3413],default=3637)
    min_abs=np.where(active,rounded,2**60).min(axis=(1,2))
    nonempty=(x1>x)&(y1>y)
    reject=nonempty&((op==0)|(((minimum>0)|(maximum<0))&(min_abs>=threshold)))
    # Zero second axis is the worst case for false rejection. Check every
    # affected pixel against the full integer alpha/LUT oracle.
    _,passes=alpha_block_float_codes(dx[:,None,:],dy[:,:,None],l00[:,None,None],l10[:,None,None],0,
                                      cs[:,None,None],fs[:,None,None],op[:,None,None])
    assert not (active & passes & reject[:,None,None]).any()
    for fields,decision in zip(rows,reject):stream.write(' '.join(map(str,[*fields,int(decision)]))+'\n')
    return int(reject.sum()),int((active & reject[:,None,None]).sum())


def main():
    out=BASE/'bbox_axis0_units_20261122';out.mkdir(parents=True,exist_ok=True)
    work=WORK/out.name;work.mkdir(parents=True,exist_ok=True)
    rng=random.Random(20261122)
    count=rejected=pixels=0
    rows=[]
    for i in range(8192):
        x,y=rng.randrange(65528),rng.randrange(65528)
        cs=rng.choice([0,1,2,4,10,31,rng.randrange(32)])
        fs=rng.choice([-32,-22,-1,0,2,rng.randrange(-22,3)])
        mx=rng.choice([x*256+rng.randrange(-32768,32768),-(1<<26),(1<<26)-1])
        my=rng.choice([y*256+rng.randrange(-32768,32768),-(1<<26),(1<<26)-1])
        rows.append([x,y,x+rng.randrange(9),y+rng.randrange(9),mx,my,rng.randrange(32768),
                     rng.choice([-32768,32767,0,rng.randrange(-32768,32768)]),cs,fs,
                     rng.choice([0,1,15,16,512,513,1024,1025,2048,2049,4096,4097,8191])])
    for op,t in [(1,2703),(512,2703),(513,2959),(1025,3214),(2049,3413),(4097,3637)]:
        for sign in (-1,1):
            for offset in range(-5,6):
                # dx=4, factor shift zero; L00=1024 scales dx by 1/4.
                rows.append([100,100,101,101,25600-sign*(t+offset),25600,1024,0,0,0,op])
    path=out/'vectors.txt'
    with path.open('w') as stream:
        for i in range(0,len(rows),128):
            group=rows[i:i+128];r,p=verify_batch(group,stream);rejected+=r;pixels+=p;count+=len(group)
    files=['rtl/projection/gaussian_bbox_axis0_reject.sv','verification/rtl/tb_t08_bbox_axis0.sv']
    run_logged(['/usr/bin/iverilog','-g2012','-s','tb_t08_bbox_axis0','-o',str(work/'test.vvp'),*files],out/'build.log')
    run_logged(['/usr/bin/vvp',str(work/'test.vvp'),'+VECTORS='+str(path)],out/'run.log')
    assert f'AXIS0 counts {count} {rejected}' in (out/'run.log').read_text()
    save(out/'report.json',dict(status='PASS_MODULE_ONLY',vectors=count,rejected=rejected,
         rejected_pixels_checked=pixels,source_sha256={f:sha(ROOT/f) for f in files},vectors_sha256=sha(path),signed_off=False))
    print(count,rejected,pixels)

if __name__=='__main__':main()
