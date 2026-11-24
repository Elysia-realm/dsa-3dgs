"""Recheck experimentally selected native subsets against raw geometry and order."""
from pathlib import Path
import sys
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from model.io.scene import read_cameras
from model.reference.math3d import project_gaussian,alpha_at
from model.reference.model import Gaussian3D, RenderConfig
from scripts.build_full_frame_batch_index import rtl_depth_q16
from scripts.build_full_frame_rtl_batch import load_selected_gaussians
from scripts.read_rgb888_frame import decode_rgb888
from scripts.t08_common import BASE,read,save,sha
from scripts.run_t08_bbox_native_pair import OUT


def render(source,camera,ids):
    config=RenderConfig(near=.2,far=1000,covariance_regularizer=77/256)
    trans=np.ones((camera.height,camera.width),np.float32)
    rgb=np.zeros((camera.height,camera.width,3),np.float32)
    for i in ids:
        point=Gaussian3D(int(i),source['mean'][i],source['scale'][i],source['quaternion'][i],
                         float(source['opacity'][i]),sh=source['sh'][i])
        g=project_gaussian(point,camera,config)
        if g is None:continue
        x0,y0,x1,y1=g.bbox
        dx=np.arange(x0,x1,dtype=np.float64)-g.mean2d[0]
        for y in range(y0,y1,64):
            stop=min(y+64,y1)
            dy=np.arange(y,stop,dtype=np.float64)[:,None]-g.mean2d[1]
            quad=g.conic[0,0]*dx*dx+2*g.conic[0,1]*dy*dx+g.conic[1,1]*dy*dy
            a=np.minimum(config.alpha_max,point.opacity*np.exp(-.5*np.maximum(quad,0)))
            t=trans[y:stop,x0:x1]
            a[(a<config.alpha_threshold)|(t<config.transmittance_threshold)]=0
            rgb[y:stop,x0:x1]+=(t*a)[:,:,None]*g.color
            t*=1-a
    return np.clip(np.floor(rgb*255+.5),0,255).astype(np.uint8)


def largest_error_pixel(rgb,fp,source,camera,ids,gids):
    difference=np.abs(rgb.astype(np.int16)-fp.astype(np.int16)).max(axis=2)
    y,x=map(int,np.unravel_index(difference.argmax(),difference.shape))
    config=RenderConfig(near=.2,far=1000,covariance_regularizer=77/256)
    terms=[];t=1.
    for i in ids:
        p=Gaussian3D(int(i),source['mean'][i],source['scale'][i],source['quaternion'][i],
                     float(source['opacity'][i]),sh=source['sh'][i])
        g=project_gaussian(p,camera,config)
        if g is None:continue
        x0,y0,x1,y1=g.bbox
        if not(x0<=x<x1 and y0<=y<y1):continue
        a=alpha_at(g,x,y,config)
        if a<config.alpha_threshold or t<config.transmittance_threshold:continue
        terms.append(dict(dense_gid=int(i),ply_gid=gids[i],alpha=a,transmittance_before=t,
                          contribution_rgb8=(t*a*255*g.color).tolist(),center=g.mean2d.tolist(),bbox=g.bbox))
        t*=1-a
    return dict(x=x,y=y,rtl=rgb[y,x].tolist(),reference=fp[y,x].tolist(),pixels_above_32=int((difference>32).sum()),
                pixels_above_64=int((difference>64).sum()),reference_terms=terms)


def main():
    global OUT
    if sys.argv[1:]==['--serial']:
        old_out=OUT
        OUT=BASE/'bbox_pair_serial_native_20261122'
    elif sys.argv[1:]:
        raise SystemExit('expected --serial or no arguments')
    else:
        old_out=None
    report=read(OUT/'report.json')
    rows=[];sheet=Image.new('RGB',(480,150*len(report['results'])));draw=ImageDraw.Draw(sheet)
    for idx,item in enumerate(report['results']):
        inp=item['inputs'];scene=inp['scene'];gids=inp['gids'];srcdir=OUT/'inputs'/scene
        assert all(sha(srcdir/f)==h for f,h in inp['input_sha256'].items())
        native=read(BASE/'inputs/native'/scene/'manifest.json')
        assert sha(native['ply'])==native['ply_sha256'] and sha(native['camera_source'])==native['camera_source_sha256']
        source=load_selected_gaussians(Path(native['ply']),np.asarray(gids))
        camera=read_cameras(native['camera_source'])[inp['camera']]
        words=[int(v,16) for v in (srcdir/'camera.memh').read_text().split()]
        signed=lambda x:x-(1<<64) if x>>63 else x
        z,ov=rtl_depth_q16(source['mean'],np.array([signed(x) for x in words[6:9]]),signed(words[11]))
        assert not ov.any()
        ids=np.flatnonzero((z>=words[19])&(z<=words[20]))
        ids=ids[np.argsort(z[ids],kind='stable')]
        sort_oracle=''.join(f'{z[i]} {i} {i}\n' for i in ids)
        fp=render(source,camera,ids);out=OUT/'semantic'/scene;out.mkdir(parents=True,exist_ok=True)
        Image.fromarray(fp).save(out/'raw_reference.png')
        for r in item['rows']:
            d=OUT/'real'/scene/str(r['enabled'])
            if old_out:
                baseline=read(old_out/'real'/scene/'result.json')
                assert baseline['inputs']==inp
                earlier=baseline['rows'][r['enabled']]
                assert r['rgb_dma_sha256']==earlier['rgb_dma_sha256'] and r['sorted_sha256']==earlier['sorted_sha256']
                if r['enabled']==0:assert r['cycles']==earlier['cycles']
            assert (d/'sorted.txt').read_text()==sort_oracle
            for file,key in [('frame.png','png_sha256'),('rgb.memh','rgb_dma_sha256'),('run.log','log_sha256')]:
                assert sha(d/file)==r[key]
            rgb=decode_rgb888(bytes.fromhex((d/'rgb.memh').read_text()),camera.width,camera.height)
            assert Image.open(d/'frame.png').tobytes()==rgb.tobytes()
        delta=np.abs(rgb.astype(np.int16)-fp.astype(np.int16))
        mask=np.any(rgb!=0,axis=2)|np.any(fp!=0,axis=2)
        assert mask.any()
        off,on=item['rows']
        row=dict(scene=scene,records=len(gids),pixels=camera.width*camera.height,active_pixels=int(mask.sum()),
                 internal_float_mae=float(delta.mean()),active_float_mae=float(delta[mask].mean()),max_error=int(delta.max()),
                 off_cycles=off['cycles'],on_cycles=on['cycles'],skips=on['skips'],
                 saved_percent=100*(1-on['cycles']/off['cycles']),float_image_sha256=sha(out/'raw_reference.png'),
                 peak_pixel=largest_error_pixel(rgb,fp,source,camera,ids,gids))
        rows.append(row)
        for col,array in enumerate([rgb,fp]):
            thumb=Image.fromarray(array);thumb.thumbnail((230,125));sheet.paste(thumb,(col*240,150*idx))
        draw.text((0,150*idx+125),scene+' RTL                     floating reference',fill='white')
        print(row,flush=True)
    sheet.save(OUT/'semantic/contact.jpg')
    save(OUT/'semantic/audit.json',dict(status='ORDER_AND_DMA_VERIFIED_FLOAT_DIAGNOSTIC',results=rows,
        report_sha256=sha(OUT/'report.json'),source_sha256={f:sha(ROOT/f) for f in ['scripts/audit_t08_bbox_native_pair.py',
        'model/reference/math3d.py','model/reference/model.py','scripts/build_full_frame_batch_index.py',
        'scripts/build_full_frame_rtl_batch.py','model/io/scene.py']},signed_off=False,
        scope='Raw PLY/native camera float reference on selected subsets, GID order checked by independent integer oracle. D06 matched GT pending.'))

if __name__=='__main__':main()
