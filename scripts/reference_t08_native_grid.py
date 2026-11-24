"""Independent native pixel samples, anchored to the frozen low-resolution float renderer."""
from pathlib import Path
import sys
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_qsu_native_full import OUT,SCENES
from scripts.run_t08_dual_full import FLOAT
from scripts.t08_common import BASE,read,save,sha
from scripts.diagnose_t06_low_resolution import colors,quant,signed
from scripts.build_full_frame_rtl_batch import load_selected_gaussians


def render_grid(ply,camfile,ids):
    words=np.array([signed(int(s,16)) for s in camfile.read_text().split()],dtype=np.float64)
    width,height=map(int,words[25:27])
    pixels=[(round(x*(width-1)/8),round(y*(height-1)/8)) for y in range(9) for x in range(9)]
    R=words[:9].reshape(3,3)/2**20
    t=words[9:12]/65536
    pos=words[12:15]/65536
    fx,fy,cx,cy=words[15:19]/65536
    rgb=np.zeros((len(pixels),3))
    T=np.ones(len(pixels))
    contributions=np.zeros(len(pixels),dtype=np.int64)
    for start in range(0,len(ids),2048):
        a=load_selected_gaussians(ply,ids[start:start+2048])
        mean=quant(a['mean'],16,-(1<<26),(1<<26)-1)
        scale=quant(a['scale'],20,0,(1<<24)-1)
        qw,qx,qy,qz=quant(a['quaternion'],20,-(1<<21),(1<<21)-1).T
        rot=np.stack([1-2*(qy*qy+qz*qz),2*(qx*qy-qw*qz),2*(qx*qz+qw*qy),
                      2*(qx*qy+qw*qz),1-2*(qx*qx+qz*qz),2*(qy*qz-qw*qx),
                      2*(qx*qz-qw*qy),2*(qy*qz+qw*qx),1-2*(qx*qx+qy*qy)],axis=1).reshape(-1,3,3)
        x,y,z=(mean@R.T+t).T
        J=np.zeros((len(z),2,3))
        J[:,0,0]=fx/z
        J[:,1,1]=fy/z
        J[:,0,2]=-(fx/z)*np.clip(x/z,-1.3*width/(2*fx),1.3*width/(2*fx))
        J[:,1,2]=-(fy/z)*np.clip(y/z,-1.3*height/(2*fy),1.3*height/(2*fy))
        A=np.einsum('nij,jk,nkl->nil',J,R,rot)*scale[:,None,:]
        cov=np.einsum('nik,njk->nij',A,A)
        c00=cov[:,0,0]+77/256
        c11=cov[:,1,1]+77/256
        c01=cov[:,0,1]
        det=c00*c11-c01*c01
        assert np.all(det>0)
        eigen=.5*(c00+c11+np.sqrt((c00-c11)**2+4*c01**2))
        opacity=quant(a['opacity'],12,0,8191)
        radius=np.ceil(np.minimum(3,np.sqrt(np.maximum(0,2*np.log(np.maximum(opacity,1e-30)*255))))*np.sqrt(eigen))
        center_x,center_y=fx*x/z+cx,fy*y/z+cy
        ix,iy=np.floor(center_x),np.floor(center_y)
        col=colors(mean,quant(a['sh'],12,-(1<<17),(1<<17)-1),pos)
        for k,(px,py) in enumerate(pixels):
            if T[k]<1e-4:
                continue
            at=(opacity>=1/255)&(np.abs(px-ix)<=radius)&(np.abs(py-iy)<=radius)
            if not at.any():
                continue
            dx,dy=px-center_x[at],py-center_y[at]
            power=-.5*(c11[at]*dx*dx-2*c01[at]*dx*dy+c00[at]*dy*dy)/det[at]
            alpha=np.minimum(.99,opacity[at]*np.exp(np.minimum(power,0)))
            alpha[alpha<1/255]=0
            prefix=np.cumprod(1-alpha)
            before=T[k]*np.r_[1,prefix[:-1]]
            weight=before*alpha
            weight[before<1e-4]=0
            rgb[k]+=weight@col[at]
            T[k]*=prefix[-1]
            contributions[k]+=np.count_nonzero(weight)
    result=np.clip(np.floor(rgb*255+.5),0,255).astype(np.uint8)
    return [dict(x=x,y=y,rgb=result[k].tolist(),contributions=int(contributions[k])) for k,(x,y) in enumerate(pixels)]


if __name__=='__main__':
    dest=OUT/'reference'
    rows=[]
    for scene in SCENES:
        meta=read(BASE/'inputs/native'/scene/'manifest.json')
        old=next(r for r in read(FLOAT/'audit.json')['results'] if r['scene']==scene)
        folder=Path(meta['inputs']['MEAN']).parent
        ply=Path(meta['ply'])
        order=folder/'expected_sorted.txt'
        low=folder/'camera.memh'
        native=Path(meta['inputs']['CAMERA'])
        fp=FLOAT/scene/'float_floor_0.30078125_jac_clamp.png'
        assert sha(ply)==meta['ply_sha256'] and sha(order)==old['input_sha256']['expected_sorted.txt']
        assert sha(low)==old['input_sha256']['camera.memh'] and sha(native)==meta['input_sha256']['CAMERA'] and sha(fp)==old['float_sha256']
        ids=np.loadtxt(order,usecols=1,dtype=np.uint32,ndmin=1)
        assert len(ids)==read(BASE/'dual_precision_full128_20261122/real'/scene/'f2/result.json')['counters']['REAL_T08']['requests']
        anchor=render_grid(ply,low,ids)
        frozen=np.asarray(Image.open(fp))
        assert all(v['rgb']==frozen[v['y'],v['x']].tolist() for v in anchor),scene
        values=render_grid(ply,native,ids)
        result=dict(scene=scene,camera=meta['camera_index'],gaussians=meta['gaussians'],visible=len(ids),
                    width=meta['width'],height=meta['height'],samples=values,low_anchor=anchor,
                    inputs={str(p):sha(p) for p in (ply,order,low,native,fp)},sources={str(p):sha(p) for p in [
                    Path(__file__),ROOT/'scripts/diagnose_t06_low_resolution.py',ROOT/'scripts/build_full_frame_rtl_batch.py']})
        save(dest/scene/'samples.json',result)
        rows.append(result)
    save(dest/'report.json',dict(results=rows,signed_off=False,
         scope='Predeclared 9x9 grid including edges. Independent float equations, quantized PLY and complete depth-visible order. No camera GT or whole-image metrics.'))
