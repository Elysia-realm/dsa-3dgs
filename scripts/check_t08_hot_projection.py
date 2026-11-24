"""Independent raw-PLY projection of native-window task and commit leaders."""
from pathlib import Path
import sys
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from model.io.scene import read_cameras
from model.reference.math3d import quaternion_to_rotation
from scripts.build_full_frame_rtl_batch import load_selected_gaussians
from scripts.t08_common import BASE,SCENES,read,save,sha

OUT=BASE/'native_gaussian_work_20261122'


def inspect(camera, data, index, bbox):
    view=camera.world_to_camera[:3,:3].astype(np.float64)
    x,y,z=view@data['mean'][index]+camera.world_to_camera[:3,3]
    assert z>0
    center=np.array([camera.fx*x/z+camera.cx,camera.fy*y/z+camera.cy])
    slopes=np.clip([x/z,y/z],[-0.65*camera.width/camera.fx,-0.65*camera.height/camera.fy],
                   [0.65*camera.width/camera.fx,0.65*camera.height/camera.fy])
    J=np.array([[camera.fx/z,0,-camera.fx*slopes[0]/z],[0,camera.fy/z,-camera.fy*slopes[1]/z]])
    rot=quaternion_to_rotation(data['quaternion'][index]).astype(np.float64)
    A=(J@view@rot)*data['scale'][index]
    cov=A@A.T+np.eye(2)*(77/256)
    inv=np.linalg.inv(cov)
    x0,y0,x1,y1=bbox
    opacity=float(data['opacity'][index])
    alpha_limit=2*np.log(max(opacity,1e-30)/(16/4096))
    # The old RTL square radius uses a Gershgorin bound and a discrete opacity
    # table. Reconstruct its ideal real-valued counterpart independently.
    levels=[(16,0),(18,0.5),(21,0.75),(26,1),(34,1.25),(49,1.5),(73,1.75),(118,2),
            (201,2.25),(364,2.5),(701,2.75),(8191,3)]
    sigma=next(v for a,v in levels if np.rint(opacity*4096)<=a)
    radius=int(np.ceil(np.ceil(16*np.sqrt(np.abs(cov).sum(axis=1).max()))/16*sigma))
    floor=np.floor(center).astype(int)
    ideal_square=np.clip([floor[0]-radius,floor[1]-radius,floor[0]+radius+1,floor[1]+radius+1],
                         [0,0,0,0],[camera.width,camera.height,camera.width,camera.height]).tolist()
    dx=np.arange(x0,x1)-center[0];passing=0;minimum=np.inf
    for start in range(y0,y1,64):
        dy=np.arange(start,min(start+64,y1))[:,None]-center[1]
        q=inv[0,0]*dx**2+2*inv[0,1]*dy*dx+inv[1,1]*dy**2
        minimum=min(minimum,q.min())
        passing+=int(np.count_nonzero(q<=alpha_limit))
    return dict(depth=float(z),mean_pixels=center.tolist(),opacity=opacity,raw_scale=data['scale'][index].tolist(),
                covariance_px2=cov.tolist(),float_square_bbox=ideal_square,rtl_bbox=bbox,
                bbox_max_edge_difference=max(abs(a-b) for a,b in zip(ideal_square,bbox)),
                rtl_bbox_pixels=(x1-x0)*(y1-y0),float_alpha_pass_pixels_in_rtl_bbox=passing,
                peak_float_alpha_in_rtl_bbox=float(opacity*np.exp(-minimum/2)))


def main():
    info=read(OUT/'build/binary.json')
    assert sha(Path(info['exe']))==info['elf_sha256'] and all(sha(ROOT/f)==h for f,h in info['sources'].items())
    results=[]
    for scene in SCENES:
        d=OUT/scene;row=read(d/'result.json');launch=read(d/'launch.json')
        native=read(BASE/'inputs/native'/scene/'manifest.json')
        assert sha(d/'gaussian_work.txt')==row['work_trace_sha256']
        assert sha(d/'events.txt')==row['trace_sha256']==read(BASE/'native_locality_20261122'/scene/'result.json')['trace_sha256']
        assert sha(d/'launch.json')==row['launch_sha256'] and launch['binary_sha256']==info['elf_sha256']
        assert sha(d/'run.log')==row['execution']['log_sha256'] and row['execution']['exit_code']==0
        assert sha(native['ply'])==native['ply_sha256'] and sha(native['camera_source'])==native['camera_source_sha256']
        camera=read_cameras(native['camera_source'])[SCENES[scene]]
        leaders={}
        for w in row['work_attribution']:
            for key in ('tasks','commits'):
                r=w['top_by_'+key][0]
                assert r['bbox'] is not None
                if r['gid'] in leaders:assert leaders[r['gid']]==r['bbox']
                leaders[r['gid']]=r['bbox']
        data=load_selected_gaussians(Path(native['ply']),np.array(list(leaders),dtype=np.uint32))
        for i,(gid,bbox) in enumerate(leaders.items()):
            geometry=inspect(camera,data,i,bbox)
            results.append(dict(scene=scene,gid=gid,**geometry))
            print(scene,gid,geometry['bbox_max_edge_difference'],geometry['rtl_bbox_pixels'],geometry['float_alpha_pass_pixels_in_rtl_bbox'])
    save(OUT/'hot_projection.json',dict(status='RAW_GEOMETRY_DIAGNOSTIC',results=results,
         source_sha256={f:sha(ROOT/f) for f in ['scripts/check_t08_hot_projection.py','model/reference/math3d.py',
                'model/io/scene.py','scripts/build_full_frame_rtl_batch.py']},
         scope='Window leaders only. Float integer-pixel alpha support over each full observed bbox before termination. Numerical diagnostic; RTL culling requires separate fixed-point proof.',signed_off=False))


if __name__=='__main__':main()
