"""Compare actual RTL shape predicates with independent bounded pixel checks."""
import random,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t07_common import BASE,WORK,VERILATOR,sha,save,run_logged
from model.fixed.alpha import conservative_shape_block_reject_code,alpha_block_float_codes
from verification.test_shape_block_reject import rtl_delta

def main():
    out=BASE/'shape';out.mkdir(exist_ok=True);w=WORK/'shape';w.mkdir(parents=True,exist_ok=True)
    rng=random.Random(370029);rows=[];rejected=0;pixels=0
    opacity_bounds=[0,1,15,16,511,512,513,1023,1024,1025,2047,2048,2049,4095,4096,4097,8191]
    for i in range(20000):
        bx=rng.randrange(32);by=rng.randrange(512);x0=bx*8+rng.randrange(9);x1=bx*8+8
        y0=by*8+rng.randrange(9);y1=by*8+8;width=bx*8+rng.randrange(1,17);height=by*8+rng.randrange(1,17)
        mean=rng.choice([y0*256,y1*256,(y0+y1)*128,rng.randrange(-(1<<26),(1<<26))])
        cs=rng.randrange(32);fs=rng.choice([-32,-22,-1,0,1,2,rng.randrange(-22,3)])
        l11=rng.choice([0,1,4096,32767,rng.randrange(32768)]);opacity=rng.choice(opacity_bounds)
        lo=max(by*8,y0);hi=min(by*8+8,y1,height);nonempty=max(bx*8,x0)<min(bx*8+8,x1,width) and lo<hi
        expected=bool(nonempty and conservative_shape_block_reject_code(lo,hi,mean,cs,fs,l11,opacity))
        if expected:
            rejected+=1
            for y in range(lo,hi):
                dy=rtl_delta(y,mean,cs)
                _,passed=alpha_block_float_codes(0,dy,0,0,l11,cs,fs,opacity)
                assert not bool(passed),(i,y);pixels+=1
        values=[bx,by,x0,x1,y0,y1,width,height,mean,cs,fs,l11,opacity,int(expected)]
        widths=[12,12,16,16,16,16,16,16,27,6,6,15,13,1];v=0
        for x,b in zip(values,widths):v=(v<<b)|(x&((1<<b)-1))
        rows.append(f'{v:047x}')
    path=out/'vectors.memh';path.write_text('\n'.join(rows)+'\n')
    files=['rtl/raster/gaussian_shape_block_reject.sv','verification/rtl/tb_t07_shape_vectors.sv']
    run_logged([VERILATOR,'--binary','--build','-j','2','--timing','-Wno-fatal','--top-module','tb_t07_shape_vectors',
                '--Mdir',str(w),'-o','simulation',*files],out/'build.log')
    run_logged([str(w/'simulation'),'+INPUT='+str(path)],out/'run.log')
    save(out/'report.json',dict(status='PASS',vectors=len(rows),rejected=rejected,independent_pixels_checked=pixels,
      source_sha256={f:sha(ROOT/f) for f in files+['model/fixed/alpha.py','verification/test_shape_block_reject.py','scripts/check_t07_shape.py']},
      vectors_sha256=sha(path),scope='Production encoder FACTOR_W=24 implies factor shift -32 or -22..2; coordinate shift 0..31. Includes empty/clipped blocks and opacity-bin boundaries; independent axis0=0 provides conservative lower bound.'))
    print('PASS T07 shape',rejected,pixels,flush=True)
if __name__=='__main__':main()
