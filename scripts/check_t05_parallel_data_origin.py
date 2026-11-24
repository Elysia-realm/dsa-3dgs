"""Check saved DMA records against data/ under the project's fixed format."""
from pathlib import Path
import sys,json,hashlib
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.build_full_frame_rtl_batch import load_selected_gaussians
from model.io.dma_workload import pack_mean_record,pack_attribute_record
BASE=ROOT/'experiments/t05_parallel_20261011'
def digest(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()
def main():
    rows=[]
    for scene in ['bonsai','counter','room','kitchen','garden']:
        source=ROOT/'experiments/t04_20261005/real_rgb'/scene
        old=json.loads((source/'manifest.json').read_text());ply=Path(old['source_ply'])
        assert digest(ply)==old['source_ply_sha256']
        batch=load_selected_gaussians(ply,np.array(old['original_gaussian_indices'][:512],dtype=np.uint32))
        folder=BASE/'release'/scene/'g16';seen=set()
        for d in sorted(folder.glob('rtl_batch_*')):
            gids=[int(x,16) for x in (d/'global_gid.memh').read_text().split()]
            means=[int(x,16) for x in (d/'mean.memh').read_text().split()]
            attrs=[int(x,16) for x in (d/'attribute_sparse.memh').read_text().split()]
            for slot,gid in enumerate(gids):
                assert gid not in seen;seen.add(gid)
                assert means[slot]==pack_mean_record(gid,batch['mean'][gid])
                expected=pack_attribute_record(batch['mean'][gid],batch['quaternion'][gid],batch['scale'][gid],batch['opacity'][gid],batch['sh'][gid])
                assert expected==sum(attrs[slot*9+i]<<(128*i) for i in range(9))
        assert len(seen)==512
        rows.append({'scene':scene,'status':'PASS','source_ply':str(ply),'source_ply_sha256':old['source_ply_sha256'],'checked_gaussians':len(seen),
            'scope':'repacked with current project fixed-format encoder; not software-3DGS/GT quality signoff'})
        print('PASS data origin',scene,flush=True)
    (BASE/'data_origin.json').write_text(json.dumps({'status':'PASS','results':rows},indent=2))
if __name__=='__main__':main()
