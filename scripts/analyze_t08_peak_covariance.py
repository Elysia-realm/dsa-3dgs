"""Explain an observed encoder failure by replaying covariance rounding stages."""
from pathlib import Path
import sys
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,read,save,sha
from model.io.t08_attribute_codec import unpack_legacy
from model.io.t08_precompute import world_covariance_q20

def rnd(x):
    return np.sign(x)*np.floor(np.abs(x)+.5)

def main():
    folder=BASE/'peak_pixel_20261122'
    probe=read(folder/'report.json')
    assert probe['stage_fields'][0]==probe['stage_fields'][1]
    actual=probe['stage_fields'][0]
    words=[int(s,16) for s in (folder/'0/attribute.memh').read_text().split()]
    _,q,scale=unpack_legacy(sum(v<<(128*i) for i,v in enumerate(words)))
    cov,ov=world_covariance_q20([q],[scale]);assert not ov[0]
    xx,xy,xz,yy,yz,zz=cov[0]
    world=np.array([[xx,xy,xz],[xy,yy,yz],[xz,yz,zz]],dtype=float)
    cam=np.array([v-(1<<64) if v>>63 else v for v in (int(s,16) for s in (folder/'camera.memh').read_text().split())])
    R=cam[:9].reshape(3,3)/(1<<20);fx,fy=cam[15:17]/65536
    x,y,z=np.asarray(actual['POSITION'][1:])/65536
    J=np.array([[fx/z,0,-fx*x/z**2],[0,fy/z,-fy*y/z**2]])
    assert abs(x/z)<.65*cam[25]/fx and abs(y/z)<.65*cam[26]/fy
    view=rnd(R@world@R.T)
    model=rnd(256*J@view@J.T/(1<<20))+np.eye(2)*cam[21]
    a,b,c=actual['PROJECTION'][-3:];assert np.array_equal(model,[[a,b],[b,c]])
    det=a*c-b*b;conic00=256*c/det
    assert det>0 and conic00>=8 and actual['ENCODER']==[0,1,0,0]
    save(folder/'covariance_analysis.json',dict(scene=probe['scene'],gid=probe['gid'],
       world_q20_codes=world.tolist(),world_min_eigenvalue_codes=float(np.linalg.eigvalsh(world)[0]),
       view_q20_codes=view.tolist(),view_min_eigenvalue_codes=float(np.linalg.eigvalsh(view)[0]),
       regularized_screen_q8=model.tolist(),determinant_q16=det,inverse00=conic00,
       conic_positive_limit_exclusive=8,probe_sha256=sha(folder/'report.json'),
       conclusion='Both formats give the same encoder error. Quantized covariance projection reproduced; inverse00 exceeds the positive Q4.40 limit.',
       scope='One real GID; evidence for this observed pixel, not a validated format change or full-scene incidence.'))
    print(world,view,model,conic00)

if __name__=='__main__':main()
