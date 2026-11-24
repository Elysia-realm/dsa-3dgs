"""Complete-model SH/covariance sizing. Estimates are not DMA/quality evidence."""
import sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE, SCENES, read, save, sha
from model.io.scene import discover_scenes, iter_gaussian_batches
from model.io.t08_precompute import quantize,world_covariance_q20,sh_tail_bounds_q12,lossless_sh_degree


def main():
    out=BASE/'parameter_analysis_20261101'
    scenes={s.name:s for s in discover_scenes(ROOT/'data')}
    rows=[]
    for name in SCENES:
        source=scenes[name].final_ply
        expected=read(BASE/'inputs/native'/name/'manifest.json')
        assert sha(source)==expected['ply_sha256']
        count=0;cov_overflow=0;cov24=0;sh16=0;sh_min=0;sh_max=0;cov_min=0;cov_max=0
        degrees=np.zeros(4,dtype=np.int64);beats_hist=np.zeros(10,dtype=np.int64)
        sensitivity={str(eps):np.zeros(4,dtype=np.int64) for eps in [1,4]}
        for batch in iter_gaussian_batches(source,batch_size=65536,include_sh=True):
            q=quantize(batch.quaternion,20,22);scale=quantize(batch.scale,20,24,False)
            cov,overflow=world_covariance_q20(q,scale)
            sh=quantize(batch.sh,12,18)
            degree=lossless_sh_degree(sh)
            fit_cov=np.all((cov>=-(1<<23))&(cov<(1<<23)),axis=1)&~overflow
            fit_sh=np.all((sh>=-(1<<15))&(sh<(1<<15)),axis=(1,2))
            # Candidate sizing only: 16 header bits, 81 mean, 13 opacity,
            # 6x24 covariance, retained SH bands; 144-byte raw escape otherwise.
            bits=16+81+13+144+3*(degree+1)**2*np.where(fit_sh,16,18)
            beats=np.where(fit_cov,np.minimum((bits+127)//128,9),9)
            beats_hist+=np.bincount(beats,minlength=10)
            degrees+=np.bincount(degree,minlength=4)
            bounds=sh_tail_bounds_q12(sh)
            for eps,hist in sensitivity.items():
                proposed=np.argmax(bounds<=float(eps),axis=1)
                hist+=np.bincount(proposed,minlength=4)
            count+=len(q);cov_overflow+=int(overflow.sum());cov24+=int(fit_cov.sum());sh16+=int(fit_sh.sum())
            sh_min=min(sh_min,int(sh.min()));sh_max=max(sh_max,int(sh.max()))
            cov_min=min(cov_min,int(cov.min()));cov_max=max(cov_max,int(cov.max()))
        assert count==expected['gaussians']
        bytes_estimate=sum(i*16*int(n) for i,n in enumerate(beats_hist))
        row=dict(scene=name,gaussians=count,full_model=True,ply_sha256=expected['ply_sha256'],
                 covariance_fractional_bits=20,covariance_integer_min=cov_min,covariance_integer_max=cov_max,
                 world_covariance_overflow_records=cov_overflow,covariance_signed24_fit_records=cov24,
                 sh_integer_min=sh_min,sh_integer_max=sh_max,sh_signed16_fit_records=sh16,
                 lossless_degree_histogram=degrees.tolist(),analytic_tail_bound_sensitivity={k:v.tolist() for k,v in sensitivity.items()},
                 nonzero_error_budget_selected=False,candidate_beats_histogram=beats_hist.tolist(),
                 uncompressed_attribute_bytes=count*144,candidate_useful_payload_bytes=bytes_estimate,
                 estimated_attribute_payload_reduction_percent=100*(1-bytes_estimate/(count*144)),
                 scope='Sizing only: no compressed DMA, decoder or image pass; raw escape for covariance overflow/out-of-range; no lossy SH choice',
                 signed_off=False)
        save(out/name/'report.json',row);rows.append(row)
        print(name,'records',count,'estimated payload saving',round(row['estimated_attribute_payload_reduction_percent'],3),'degree',degrees.tolist(),flush=True)
    save(out/'report.json',dict(status='ANALYSIS_COMPLETE_NOT_INTEGRATED',results=rows,signed_off=False,
        source_sha256={f:sha(ROOT/f) for f in ['model/io/t08_precompute.py','model/io/scene.py','scripts/analyze_t08_parameters.py',
          'rtl/projection/quaternion_scale_covariance_core.sv','rtl/projection/raw_gaussian_projection_lane.sv']}))


if __name__=='__main__':main()
