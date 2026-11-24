"""Size Q24 in the existing fixed-slot budget; anchor the model to measured v1 AXI."""
import sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from model.io.scene import iter_gaussian_batches
from model.io.t08_precompute import lossless_sh_degree,quantize,world_covariance_q20
from scripts.build_full_frame_batch_index import rtl_depth_q16
from scripts.scan_t08_small_covariances import make_products,shift
from scripts.t08_common import BASE,SCENES,read,save,sha


def main():
    out=BASE/'q24_slot_budget_20261122';rows=[]
    for scene in SCENES:
        native=read(BASE/'inputs/native'/scene/'manifest.json')
        ply=Path(native['ply']);cam=Path(native['inputs']['CAMERA'])
        assert sha(ply)==native['ply_sha256'] and sha(cam)==native['input_sha256']['CAMERA']
        words=[v-(1<<64) if v>>63 else v for v in (int(x,16) for x in cam.read_text().split())]
        count=visible=bytes20=bytes24=extra_escapes=0
        for batch in iter_gaussian_batches(ply,batch_size=32768,include_sh=True):
            count+=len(batch.mean)
            z,ov=rtl_depth_q16(batch.mean,np.array(words[6:9]),words[11]);assert not ov.any()
            live=(z>=words[19])&(z<=words[20]);visible+=int(live.sum())
            if not live.any():continue
            q=quantize(batch.quaternion[live],20,22);sc=quantize(batch.scale[live],20,24,False)
            sh=quantize(batch.sh[live],12,18)
            degree=lossless_sh_degree(sh);width=np.where(np.all((sh>=-32768)&(sh<32768),axis=(1,2)),16,18)
            short_beats=(254+3*(degree+1)**2*width+127)//128
            products=make_products(q,sc)[:,[0,0,0,1,1,2],[0,1,2,1,2,2]]
            q20,overflow=world_covariance_q20(q,sc)
            assert not overflow.any() and np.array_equal(q20,shift(products,20))
            q24=shift(products,16)
            fits=lambda v:np.all((v>=-(1<<23))&(v<1<<23),axis=1)&(short_beats<9)
            old,new=fits(q20),fits(q24)
            assert not (new&~old).any()
            bytes20+=int(np.where(old,short_beats,9).sum())*16
            bytes24+=int(np.where(new,short_beats,9).sum())*16
            extra_escapes+=int((old&~new).sum())
        original=read(BASE/'early_advance_20261120/real/full/1'/scene/'f1/result.json')
        assert count==native['gaussians'] and visible==original['counters']['REAL_T08']['requests']
        assert bytes20==16*original['counters']['REAL_DMA_COUNTS']['attribute_beats']
        row=dict(scene=scene,records=count,requests=visible,v1_actual_bytes=bytes20,q24_projected_bytes=bytes24,
                 raw_bytes=144*visible,extra_escapes=extra_escapes,source_ply_sha256=native['ply_sha256'],
                 q24_saved_vs_raw_percent=100*(1-bytes24/(144*visible)))
        rows.append(row);save(out/scene/'result.json',row);print(row,flush=True)
    save(out/'report.json',dict(status='SIZING_ONLY',results=rows,signed_off=False,
         scope='Same header/slot widths, Q24 compact when all six words fit signed24, otherwise raw escape. Dedicated precision version required before hardware use. Q20 prediction checked against actual bus bytes.'))

if __name__=='__main__':main()
