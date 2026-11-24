"""Float geometry/alpha diagnostic from real PLY; NOT RTL image/signoff evidence.

Uses the frozen project's SH field interpretation, quantized source parameters
and camera. Varies only the pixel-space covariance floor. No generated image is
substituted for the saved RTL RGB DMA output.
"""
import argparse,json,sys,time
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.build_full_frame_rtl_batch import load_selected_gaussians
BASE=ROOT/'experiments/t06_20261014/full_render';OUT=ROOT/'experiments/t06_20261017/image_diagnosis'
def quant(x,frac,lo,hi):return np.clip(np.rint(np.asarray(x,dtype=np.float64)*(1<<frac)),lo,hi)/(1<<frac)
def signed(v):return v-(1<<64) if v>=1<<63 else v
def colors(mean,sh,camera_pos):
    d=mean-camera_pos;d/=np.maximum(np.linalg.norm(d,axis=1,keepdims=True),1e-12);x,y,z=d.T
    b=np.column_stack([np.full(len(x),.28209479177387814),-.4886025119029199*y,.4886025119029199*z,-.4886025119029199*x,
      1.0925484305920792*x*y,-1.0925484305920792*y*z,.31539156525252005*(2*z*z-x*x-y*y),-1.0925484305920792*x*z,.5462742152960396*(x*x-y*y),
      -.5900435899266435*y*(3*x*x-y*y),2.890611442640554*x*y*z,-.4570457994644658*y*(4*z*z-x*x-y*y),
      .3731763325901154*z*(2*z*z-3*x*x-3*y*y),-.4570457994644658*x*(4*z*z-x*x-y*y),1.445305721320277*z*(x*x-y*y),-.5900435899266435*x*(x*x-3*y*y)])
    return np.clip(np.einsum('nci,ni->nc',sh,b)+.5,0,1)
def run(name,regularizer,clamp=False):
    folder=BASE/name;manifest=json.loads((folder/'manifest.json').read_text(encoding='utf-8'))
    camera=np.array([signed(int(x,16)) for x in (folder/'camera.memh').read_text().split()],dtype=np.float64)
    w,h=manifest['width'],manifest['height'];R=camera[:9].reshape(3,3)/(1<<20);t=camera[9:12]/65536;pos=camera[12:15]/65536
    fx,fy,cx,cy=camera[15:19]/65536
    ids=np.loadtxt(folder/'expected_sorted.txt',usecols=1,dtype=np.uint32,ndmin=1)
    yy,xx=np.mgrid[:h,:w];pixels=np.column_stack([xx.ravel(),yy.ravel()]);T=np.ones(w*h);rgb=np.zeros((w*h,3))
    tile_ids=(pixels[:,0]//8)+(pixels[:,1]//8)*((w+7)//8)
    tiles=[np.flatnonzero(tile_ids==t) for t in np.unique(tile_ids)]
    consumed=0;contributing=0;peak=0;beg=time.monotonic();dominant=[]
    for start in range(0,len(ids),2048):
        if np.all(T<1e-4):break
        selected=ids[start:start+2048]
        source_ids=np.asarray(manifest['original_gaussian_indices'],dtype=np.uint32)[selected] if 'original_gaussian_indices' in manifest else selected
        a=load_selected_gaussians(ROOT/'data'/name/'point_cloud/iteration_30000/point_cloud.ply',source_ids)
        mean=quant(a['mean'],16,-(1<<26),(1<<26)-1);scale=quant(a['scale'],20,0,(1<<24)-1)
        q=quant(a['quaternion'],20,-(1<<21),(1<<21)-1);qw,qx,qy,qz=q.T
        rot=np.stack([1-2*(qy*qy+qz*qz),2*(qx*qy-qw*qz),2*(qx*qz+qw*qy),
          2*(qx*qy+qw*qz),1-2*(qx*qx+qz*qz),2*(qy*qz-qw*qx),
          2*(qx*qz-qw*qy),2*(qy*qz+qw*qx),1-2*(qx*qx+qy*qy)],axis=1).reshape(-1,3,3)
        cam=mean@R.T+t;x,y,z=cam.T;n=len(z)
        J=np.zeros((n,2,3));J[:,0,0]=fx/z;J[:,0,2]=-fx*x/(z*z);J[:,1,1]=fy/z;J[:,1,2]=-fy*y/(z*z)
        if clamp:
            J[:,0,2]=-(fx/z)*np.clip(x/z,-1.3*w/(2*fx),1.3*w/(2*fx))
            J[:,1,2]=-(fy/z)*np.clip(y/z,-1.3*h/(2*fy),1.3*h/(2*fy))
        A=np.einsum('nij,jk,nkl->nil',J,R,rot)*scale[:,None,:]
        cov=np.einsum('nik,njk->nij',A,A);cov[:,0,0]+=regularizer;cov[:,1,1]+=regularizer
        det=cov[:,0,0]*cov[:,1,1]-cov[:,0,1]**2
        inv=np.zeros_like(cov);inv[:,0,0]=cov[:,1,1]/det;inv[:,1,1]=cov[:,0,0]/det;inv[:,0,1]=inv[:,1,0]=-cov[:,0,1]/det
        center=np.column_stack([fx*x/z+cx,fy*y/z+cy])
        opacity=quant(a['opacity'],12,0,8191)
        eigmax=.5*(cov[:,0,0]+cov[:,1,1]+np.sqrt((cov[:,0,0]-cov[:,1,1])**2+4*cov[:,0,1]**2))
        radius=np.ceil(np.minimum(3,np.sqrt(np.maximum(0,2*np.log(np.maximum(opacity,1e-30)/(1/255)))))*np.sqrt(eigmax))
        # Software-reference optimization ONLY. Pixels are independent; within
        # each tile the selected Gaussian indices retain the same global order.
        # The hardware remains Gaussian-wise and does not adopt tile binning.
        mass=np.zeros(n);center_floor=np.floor(center)
        col=colors(mean,quant(a['sh'],12,-(1<<17),(1<<17)-1),pos)
        for tile in tiles:
            active=tile[T[tile]>=1e-4]
            if len(active)==0:continue
            p=pixels[active];lo=p.min(0);hi=p.max(0)
            selected_rows=np.flatnonzero((opacity>=1/255)&np.all(center_floor+radius[:,None]>=lo,axis=1)&np.all(center_floor-radius[:,None]<=hi,axis=1))
            if len(selected_rows)==0:continue
            cr=center[selected_rows];ci=inv[selected_rows];op=opacity[selected_rows]
            delta=p[None,:,:]-cr[:,None,:]
            exponent=-.5*(ci[:,0,0,None]*delta[:,:,0]**2+2*ci[:,0,1,None]*delta[:,:,0]*delta[:,:,1]+ci[:,1,1,None]*delta[:,:,1]**2)
            support=np.all(np.abs(p[None,:,:]-center_floor[selected_rows,None,:])<=radius[selected_rows,None,None],axis=2)
            alpha=np.minimum(.99,op[:,None]*np.exp(np.minimum(exponent,0)));alpha[(alpha<1/255)|~support]=0
            prefix=np.cumprod(1-alpha,axis=0);before=np.vstack([np.ones((1,len(active))),prefix[:-1]])*T[active]
            weights=before*alpha;weights[before<1e-4]=0
            mass[selected_rows]+=weights.sum(axis=1)
            rgb[active]+=weights.T@col[selected_rows];T[active]*=prefix[-1]
        for i in np.argsort(mass)[-10:]:
            if mass[i]>0:dominant.append({'gid':int(selected[i]),'weight_sum':float(mass[i]),'camera_z':float(z[i]),
                'projected_center':center[i].tolist(),'max_sigma_pixels':float(np.sqrt(eigmax[i])),
                'outside_fov':bool(abs(x[i]/z[i])>w/(2*fx) or abs(y[i]/z[i])>h/(2*fy))})
        dominant=sorted(dominant,key=lambda q:q['weight_sum'],reverse=True)[:10]
        contributing+=int(np.count_nonzero(mass>0));consumed+=n
    raw=np.clip(np.floor(rgb.reshape(h,w,3)*255+.5),0,255).astype(np.uint8)
    target_path=folder/'production_v2/frame.png'
    target=np.array(Image.open(target_path)) if target_path.exists() else None
    diff=raw.astype(float)-target if target is not None else None
    dest=OUT/name;dest.mkdir(parents=True,exist_ok=True);tag=f'float_floor_{regularizer:.8f}'+('_jac_clamp' if clamp else '')
    Image.fromarray(raw).save(dest/f'{tag}.png')
    active_pixels=np.any(raw!=0,axis=2)|(np.any(target!=0,axis=2) if target is not None else False)
    row={'scene':name,'regularizer':regularizer,'jacobian_fov_clamp':clamp,'dominant_contributors':dominant,'width':w,'height':h,'processed_depth_sorted_prefix':consumed,'total_depth_visible':len(ids),
         'all_pixels_terminated':bool(np.all(T<1e-4)),'contributing_gaussians':contributing,'mean_rgb':raw.mean((0,1)).tolist(),
         'std_rgb':raw.std((0,1)).tolist(),'unique_rgb':len(np.unique(raw.reshape(-1,3),axis=0)),
         'rtl_rmse_rgb8':float(np.sqrt(np.mean(diff**2))) if diff is not None else None,'rtl_max_abs_rgb8':float(np.max(np.abs(diff))) if diff is not None else None,
         'rtl_mae_rgb8':float(np.mean(np.abs(diff))) if diff is not None else None,'rtl_active_mae_rgb8':(float(np.mean(np.abs(diff[active_pixels]))) if active_pixels.any() else 0) if diff is not None else None,
         'seconds':time.monotonic()-beg,'scope':'float diagnostic using existing project SH interpretation; not bit-exact RTL oracle or GT; floor ablation is not a production fix'}
    (dest/f'{tag}.json').write_text(json.dumps(row,indent=2));print(json.dumps(row),flush=True);return row
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--scenes',nargs='+',default=['bonsai']);p.add_argument('--floors',nargs='+',type=float,default=[77/256,.003]);p.add_argument('--clamp',action='store_true');p.add_argument('--input-root',type=Path,default=BASE);p.add_argument('--output-root',type=Path,default=OUT);a=p.parse_args();BASE=a.input_root.resolve();OUT=a.output_root.resolve()
    for name in a.scenes:
        for floor in a.floors:run(name,floor,a.clamp)
