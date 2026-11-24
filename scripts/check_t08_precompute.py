"""Compare offline integer precompute with unchanged production covariance RTL."""
import sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,WORK,read,save,sha,run_logged
from model.io.t08_precompute import world_covariance_q20,quantize,lossless_sh_degree,sh_tail_bounds_q12


def main():
    out=BASE/'precompute_units_20261101';out.mkdir(parents=True,exist_ok=True)
    work=WORK/'precompute_units_20261101';work.mkdir(parents=True,exist_ok=True)
    rng=np.random.default_rng(20261101)
    normal=rng.normal(size=(1536,4));normal/=np.linalg.norm(normal,axis=1,keepdims=True)
    q=np.vstack([quantize(normal,20,22),rng.integers(-(1<<21),1<<21,size=(512,4))])
    scale=rng.integers(0,1<<24,size=(2048,3),dtype=np.int64)
    q[:8]=np.array([[1<<20,0,0,0]]*4+[[0,1<<20,0,0],[0,0,1<<20,0],[0,0,0,1<<20],[0,0,0,0]])
    scale[:8]=np.array([[0,0,0],[1<<20,2<<20,3<<20],[1,511,512],[(1<<24)-1]*3,
                        [1<<20]*3,[1<<20]*3,[1<<20]*3,[1<<20]*3])
    cov,overflow=world_covariance_q20(q,scale)
    # Independent identities and sign/rounding properties, not only RTL parity.
    assert cov[0].tolist()==[0]*6 and not overflow[0]
    assert cov[1].tolist()==[1<<20,0,0,4<<20,0,9<<20]
    assert cov[2].tolist()==[0,0,0,0,0,0]
    assert np.all(cov[4:8]==[1<<20,0,0,1<<20,0,1<<20])
    sh=np.zeros((4,3,16),dtype=np.int64)
    for band in range(4):sh[band,0,band*band]=1
    assert lossless_sh_degree(sh).tolist()==[0,1,2,3]
    bounds=sh_tail_bounds_q12(sh)
    assert np.all(bounds[:,-1]==0) and np.all(bounds[:,:-1]>=bounds[:,1:])
    inputs=[];expected=[]
    for qs,ss,cs,ov in zip(q,scale,cov,overflow):
        value=0
        for field,width in zip([*qs,*ss],[22]*4+[24]*3):value=(value<<width)|(int(field)&((1<<width)-1))
        inputs.append(f'{value:040x}\n')
        value=0
        for field in cs:value=(value<<41)|(int(field)&((1<<41)-1))
        value=(value<<1)|int(ov);expected.append(f'{value:062x}\n')
    (out/'input.memh').write_text(''.join(inputs));(out/'expected.memh').write_text(''.join(expected))
    files=['rtl/common/rv_reg_slice.sv','rtl/projection/quaternion_scale_covariance_core.sv',
           'verification/rtl/tb_t08_covariance_precompute.sv']
    verilator=read(BASE/'build/native/binary.json')['command'][0]
    cmd=[verilator,'--binary','--build','-j','2','--timing','--assert','-Wno-fatal',
         '--top-module','tb_t08_covariance_precompute','--Mdir',str(work),'-o','simulation',*files]
    run_logged(cmd,out/'build.log')
    run_logged([str(work/'simulation'),'+INPUT='+str(out/'input.memh'),'+EXPECTED='+str(out/'expected.memh')],out/'run.log')
    assert 'PASS T08 covariance precompute vectors=2048' in (out/'run.log').read_text()
    save(out/'report.json',dict(status='PASS',vectors=2048,legal_normalized_vectors=1536,
         arbitrary_bitpattern_vectors=512,overflow_vectors=int(overflow.sum()),signed_off=False,
         source_sha256={f:sha(ROOT/f) for f in files+['model/io/t08_precompute.py','scripts/check_t08_precompute.py']},
         input_sha256=sha(out/'input.memh'),expected_sha256=sha(out/'expected.memh'),binary_sha256=sha(work/'simulation'),
         scope='Existing world covariance Q20.20 offline arithmetic parity, identities, tags and output backpressure; not integrated compressed rendering'))
    print('PASS T08 precompute: 2048 vectors',flush=True)


if __name__=='__main__':main()
