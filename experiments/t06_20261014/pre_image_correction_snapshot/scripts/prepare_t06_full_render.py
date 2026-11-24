"""Encode complete PLY order, no host ordering/pivots/subsets. Vectorized wire packing."""
import argparse,json,sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from model.io.scene import iter_gaussian_batches,open_ply_vertices
from scripts.build_full_frame_batch_index import pack_mean_records,quantize_signed,rtl_depth_q16
from scripts.run_t06_qsu_units import sha
OUT=ROOT/'experiments/t06_20261014/full_render'
def attribute_words(batch):
    n=len(batch.mean);words=np.zeros((n,18),dtype=np.uint64);offset=0
    def add(values,bits,frac,signed=True):
        nonlocal offset
        q=np.rint(np.asarray(values,dtype=np.float64)*(1<<frac)).astype(np.int64)
        q=np.clip(q,-(1<<(bits-1)) if signed else 0,(1<<(bits-1))-1 if signed else (1<<bits)-1)
        code=q.astype(np.uint64)&np.uint64((1<<bits)-1);col,bit=divmod(offset,64)
        words[:,col]|=code<<np.uint64(bit)
        if bit+bits>64:words[:,col+1]|=code>>np.uint64(64-bit)
        offset+=bits
    for i in range(48):add(batch.sh.reshape(n,48)[:,i],18,12)
    add(batch.opacity,13,12,False)
    for i in [2,1,0]:add(batch.scale[:,i],24,20,False)
    for i in [3,2,1,0]:add(batch.quaternion[:,i],22,20)
    for i in [2,1,0]:add(batch.mean[:,i],27,16)
    assert offset==1118
    return words
def prepare(name):
    dest=OUT/name;dest.mkdir(parents=True,exist_ok=True)
    ply=ROOT/'data'/name/'point_cloud/iteration_30000/point_cloud.ply';header,_=open_ply_vertices(ply);n=header.vertex_count
    old=ROOT/'experiments/t04_20261005/real_rgb'/name
    oldm=json.loads((old/'manifest.json').read_text());fixed=oldm['camera_fixed']
    cam=[int(x,16) for x in (ROOT/'experiments/t05_parallel_20261011/release'/name/'g16/rtl_batch_0000/camera.memh').read_text().split()]
    width,height=16,round(cam[26]*16/cam[25]);oldw,oldh=cam[25:27]
    for i,scale in [(15,width/oldw),(16,height/oldh),(17,width/oldw),(18,height/oldh)]:
        value=cam[i]-(1<<64) if cam[i]>>63 else cam[i];cam[i]=round(value*scale)&((1<<64)-1)
    cam[22:25]=[0]*3;cam[25:27]=[width,height];cam[27]=(0x47534301<<32)|n
    (dest/'camera.memh').write_text(''.join(f'{v:016x}\n' for v in cam))
    depths=[];visible=[]
    with (dest/'mean.memh').open('w') as mf,(dest/'attribute.memh').open('w') as af:
        for batch in iter_gaussian_batches(ply,batch_size=16384,include_sh=True):
            gids=np.arange(batch.start,batch.stop,dtype=np.uint32)
            mw=pack_mean_records(gids,batch.mean);aw=attribute_words(batch)
            # Cross-check the vector encoder against the existing scalar format.
            from model.io.dma_workload import pack_attribute_record
            for j in [0,len(gids)-1]:
                scalar=pack_attribute_record(batch.mean[j],batch.quaternion[j],batch.scale[j],batch.opacity[j],batch.sh[j])
                assert scalar==sum(int(v)<<(64*k) for k,v in enumerate(aw[j]))
            for lo,hi in mw:mf.write(f'{int(hi):016x}{int(lo):016x}\n')
            for row in aw:
                for k in range(0,18,2):af.write(f'{int(row[k+1]):016x}{int(row[k]):016x}\n')
            d,overflow=rtl_depth_q16(batch.mean,np.array(fixed['rotation_q20'][6:9]),fixed['translation_q16'][2])
            assert not np.any(overflow),'prepass numeric overflow requires explicit closure'
            depths.append(d);visible.append((d>=fixed['near_far_q16'][0])&(d<=fixed['near_far_q16'][1]))
            print(name,batch.stop,n,flush=True)
    depth=np.concatenate(depths);mask=np.concatenate(visible);ids=np.flatnonzero(mask);order=ids[np.argsort(depth[ids],kind='stable')]
    # Expected sorted stream remains a verification-only artifact.
    with (dest/'expected_sorted.txt').open('w') as f:
        for i in order:f.write(f'{int(depth[i])} {int(i)} {int(i)}\n')
    m={'scene':name,'camera_index':oldm['camera_index'],'gaussians':n,'visible':int(mask.sum()),'full_scene':True,
       'width':width,'height':height,'software_preprocessing':'PLY decode and fixed-point format only; original order; pivots zero/ignored; one command',
       'source_ply_sha256':sha(ply),'input_sha256':{p.name:sha(p) for p in dest.glob('*.memh')},
       'oracle_sha256':sha(dest/'expected_sorted.txt'),'status':'INPUT_PREPARED_NOT_TESTED'}
    (dest/'manifest.json').write_text(json.dumps(m,indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--scenes',nargs='+',default=['bonsai','counter','room','kitchen','garden']);a=p.parse_args()
    for name in a.scenes:prepare(name)
