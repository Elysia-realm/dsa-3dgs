"""Count precision-risk records, not image errors, on a frozen native view per scene."""
from pathlib import Path
import sys
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,SCENES,read,save,sha
from scripts.build_full_frame_batch_index import rtl_depth_q16
from model.io.scene import iter_gaussian_batches
from model.io.t08_precompute import quantize,world_covariance_q20

def shift(v,n):
    return np.sign(v)*((np.abs(v)+(1<<(n-1)))>>n)

def make_products(q,sc):
    w,x,y,z=q.T;unit=1<<40
    rot=np.stack([unit-2*(y*y+z*z),2*(x*y-w*z),2*(x*z+w*y),
                  2*(x*y+w*z),unit-2*(x*x+z*z),2*(y*z-w*x),
                  2*(x*z-w*y),2*(y*z+w*x),unit-2*(x*x+y*y)],axis=1).reshape(-1,3,3)
    m=shift(shift(rot,20)*sc[:,None,:],20)
    return m@m.transpose(0,2,1)

def at_precision(products,R,J,fraction):
    world=shift(products,40-fraction)
    assert np.abs(world).max()<=300  # selected scales bound products in R*world*Rt
    view=shift((R@world)@R.T,40)
    mat=(J@view@J.transpose(0,2,1))*2.**(8-fraction)
    code=np.sign(mat)*np.floor(abs(mat)+.5)
    a,b,c=code[:,0,0]+77,code[:,0,1],code[:,1,1]+77
    det=a*c-b*b
    invalid=(a<=0)|(c<=0)|(det<=0)|(256*np.maximum.reduce([a,c,abs(b)])>=8*det)
    return invalid,world

def main():
    rows=[];out=BASE/'small_covariance_20261122'
    for scene in SCENES:
        native=read(BASE/'inputs/native'/scene/'manifest.json')
        ply=Path(native['ply']);camfile=Path(native['inputs']['CAMERA'])
        assert sha(ply)==native['ply_sha256'] and sha(camfile)==native['input_sha256']['CAMERA']
        words=[v-(1<<64) if v>>63 else v for v in (int(x,16) for x in camfile.read_text().split())]
        R=np.array(words[:9],dtype=np.int64).reshape(3,3)
        fx,fy,cx,cy=np.array(words[15:19])/65536;w,h=native['width'],native['height']
        counts=dict(records=0,selected=0,risk_q20=0,risk_q24=0,recovered=0,new_risks=0)
        examples=[];known=None
        for batch in iter_gaussian_batches(ply,batch_size=65536):
            sc=quantize(batch.scale,20,24,False)
            counts['records']+=len(sc)
            small=sc.max(axis=1)<=4096
            if not small.any():continue
            ids=np.flatnonzero(small);mean=batch.mean[ids]
            axes=[rtl_depth_q16(mean,axis,t) for axis,t in zip(R,words[9:12])]
            xyz=np.column_stack([a for a,_ in axes]);valid=~np.any(np.column_stack([b for _,b in axes]),axis=1)
            x,y,z=xyz.T.astype(float)/65536;zsafe=np.where(z>0,z,1)
            sx=fx*x/zsafe+cx;sy=fy*y/zsafe+cy
            valid&=(xyz[:,2]>=words[19])&(xyz[:,2]<=words[20])&(sx>=0)&(sx<w)&(sy>=0)&(sy<h)
            valid&=quantize(batch.opacity[ids],12,13,False)>=16
            ids=ids[valid]
            if not len(ids):continue
            x,y,z=x[valid],y[valid],z[valid]
            J=np.zeros((len(ids),2,3));J[:,0,0]=fx/z;J[:,1,1]=fy/z
            J[:,0,2]=-(fx/z)*np.clip(x/z,-.65*w/fx,.65*w/fx)
            J[:,1,2]=-(fy/z)*np.clip(y/z,-.65*h/fy,.65*h/fy)
            q=quantize(batch.quaternion[ids],20,22);products=make_products(q,sc[ids])
            low,world=at_precision(products,R,J,20);high,_=at_precision(products,R,J,24)
            expected,overflow=world_covariance_q20(q,sc[ids])
            assert not overflow.any() and np.array_equal(world[:,[0,0,0,1,1,2],[0,1,2,1,2,2]],expected)
            counts['selected']+=len(ids);counts['risk_q20']+=int(low.sum());counts['risk_q24']+=int(high.sum())
            counts['recovered']+=int((low&~high).sum());counts['new_risks']+=int((~low&high).sum())
            if len(examples)<8:examples.extend((batch.start+ids[low])[:8-len(examples)].tolist())
            if scene=='bonsai':
                ix=np.flatnonzero(batch.start+ids==770601)
                if len(ix):known=[bool(low[ix[0]]),bool(high[ix[0]])]
        assert counts['records']==native['gaussians']
        if scene=='bonsai':assert known and known[0]
        row=dict(scene=scene,camera=SCENES[scene],counts=counts,examples_q20=examples,known_case=known,
                 ply_sha256=native['ply_sha256'],camera_sha256=native['input_sha256']['CAMERA'])
        rows.append(row);save(out/scene/'result.json',row);print(scene,counts,known,flush=True)
    save(out/'report.json',dict(status='DIAGNOSTIC_COMPLETE',results=rows,signed_off=False,
        scope='All records scanned; selected max Q20 scale code <=4096, valid depth, projected center on screen, opacity code >=16. Integer world/view rounding; floating Jacobian, Q8 screen rounding. Counts estimate nonpositive or out-of-range conic risk; no measured pixel error or FPS implied.'))

if __name__=='__main__':main()
