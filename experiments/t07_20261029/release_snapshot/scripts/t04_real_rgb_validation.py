"""Reproducible real-data RGB DMA validation; CPU sorting/batching is explicit.

The PNG is ONLY an unpacking of accepted RTL AXI W bytes. The state-to-RGB
oracle is used for comparison, never as the saved image source.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import subprocess
import sys
import time
from dataclasses import asdict
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from model.io import discover_scenes
from model.io.dma_workload import write_workload, CAMERA_DESCRIPTOR_TAG
from scripts.build_full_frame_batch_index import rtl_depth_q16
from scripts.read_rgb888_frame import decode_rgb888

def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for data in iter(lambda: stream.read(1024*1024), b''): h.update(data)
    return h.hexdigest()

def prepare(out, names, count, dimension):
    scenes = {s.name:s for s in discover_scenes(ROOT/'data')}
    for name in names:
        folder=out/name
        print('Preparing '+name, flush=True)
        start=time.monotonic()
        m=asdict(write_workload(scenes[name],folder/'selected',count=count,max_dimension=dimension))
        mean=[int(x,16) for x in (folder/'selected/mean.memh').read_text().split()]
        attr=(folder/'selected/attribute.memh').read_text().split()
        cam=[int(x,16) for x in (folder/'selected/camera.memh').read_text().split()]
        # Quantized depth oracle uses the exact same input Q16 and Q20 as RTL.
        def signed(v,w): return v-(1<<w) if v&(1<<(w-1)) else v
        xyz=np.array([[signed((x>>b)&((1<<27)-1),27)/65536 for b in (32,59,86)] for x in mean])
        fixed=m['camera_fixed']
        depths,overflow=rtl_depth_q16(xyz,np.array(fixed['rotation_q20'][6:9]),fixed['translation_q16'][2])
        if np.any(overflow): raise ValueError('depth overflow')
        order=sorted(range(count),key=lambda i:(int(depths[i]),i))
        batch_size=128
        batches=[]
        for n,start_offset in enumerate(range(0,count,batch_size)):
            ids=order[start_offset:start_offset+batch_size]
            p=folder/f'rtl_batch_{n:04d}';p.mkdir(parents=True,exist_ok=True)
            c=cam.copy();c[22:25]=[0,0,0] # all positive-depth items use one group; capacity=128
            c[27]=(CAMERA_DESCRIPTOR_TAG<<32)|len(ids)
            (p/'camera.memh').write_text(''.join(f'{x:016x}\n' for x in c),encoding='ascii')
            (p/'mean.memh').write_text(''.join(f'{mean[i]:032x}\n' for i in ids),encoding='ascii')
            (p/'global_gid.memh').write_text(''.join(f'{i:08x}\n' for i in ids),encoding='ascii')
            (p/'attribute_sparse.memh').write_text(''.join(x+'\n' for i in ids for x in attr[i*9:i*9+9]),encoding='ascii')
            batches.append({'index':n,'count':len(ids),'min_depth':int(depths[ids[0]]),'max_depth':int(depths[ids[-1]])})
        m.update({'batches':batches,'scope':'deterministic visible Gaussian subset; CPU exact-depth sorting and 128-entry continuation batches; not T06 autonomous or T10 full scene',
                  'source_ply':str(scenes[name].final_ply),'source_ply_sha256':sha(scenes[name].final_ply),
                  'source_cameras_sha256':sha(scenes[name].cameras_json),'preparation_seconds':time.monotonic()-start})
        (folder/'manifest.json').write_text(json.dumps(m,indent=2),encoding='utf-8')
        print(f"Prepared {name}: camera={m['camera_index']} {m['width']}x{m['height']}, {count} Gaussians, {len(batches)} batches",flush=True)

def run(out,names,exe):
    results=[]
    for name in names:
        folder=(out/name).resolve();m=json.loads((folder/'manifest.json').read_text())
        for profile,args in [('ideal',[0,0,1,0,2]),('limited',[8,2,4,1,8])]:
            dest=folder/profile;dest.mkdir(exist_ok=True)
            cmd=[str(exe.resolve()),f'+BATCH_ROOT={folder.as_posix()}',f'+BATCH_LAST={len(m["batches"])-1}',
                 f'+FRAME={(dest/"state.memh").as_posix()}',f'+RGB={(dest/"frame_rgb.memh").as_posix()}',
                 f'+LABEL={name}_{profile}','+FRAME_MODE=0','+MAX_TIMEOUT=20000000']
            cmd += [f'+{k}={v}' for k,v in zip(['READ_LATENCY','READ_GAP','READY_PERIOD','READY_LOW','WRITE_RESPONSE_LATENCY'],args)]
            start=time.monotonic();p=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)
            (dest/'run.log').write_text(p.stdout+p.stderr,encoding='utf-8')
            (dest/'command.json').write_text(json.dumps(cmd,indent=2),encoding='utf-8')
            result={'scene':name,'camera_index':m['camera_index'],'width':m['width'],'height':m['height'],'gaussians':m['gaussian_count'],
                    'batches':len(m['batches']),'mode':'G','profile':profile,'seconds':time.monotonic()-start,'returncode':p.returncode}
            if p.returncode!=0: raise RuntimeError(f'{name}/{profile} failed: {p.stdout[-3000:]}')
            if 'REAL_RGB' not in p.stdout: raise RuntimeError('final RGB DMA not exercised')
            data=bytes(int(x,16) for x in (dest/'frame_rgb.memh').read_text().split())
            state=[int(x,16) for x in (dest/'state.memh').read_text().split()]
            w,h=m['width'],m['height'];stride=(w*3+15)&~15
            oracle=bytearray(stride*h)
            for i,s in enumerate(state):
                if ((s>>55)&65535)!=1: continue
                y,x=divmod(i,w)
                for c in range(3): oracle[y*stride+x*3+c]=min(255,((((s>>(13*c))&8191)*255+2048)>>12))
            mismatches=sum(a!=b for a,b in zip(data,oracle))+abs(len(data)-len(oracle))
            if mismatches: raise RuntimeError(f'{name}/{profile}: {mismatches} RGB bytes mismatch')
            (dest/'frame.rgb').write_bytes(data)
            rgb=decode_rgb888(data,w,h)
            Image.fromarray(rgb).save(dest/'frame.png')
            result.update({'status':'PASS','rgb_byte_mismatches':mismatches,'rgb_bytes':len(data),'rgb_sha256':sha(dest/'frame.rgb'),
                           'nonblack_pixels':int(np.any(rgb!=0,axis=2).sum()),'image':str(dest/'frame.png'),
                           'summary':[x for x in p.stdout.splitlines() if x.startswith(('REAL_RGB','REAL_PERF','REAL_CONTINUATION'))]})
            results.append(result)
            (out/'real_rgb_report.json').write_text(json.dumps({'status':'IN_PROGRESS','results':results},indent=2),encoding='utf-8')
            print(f"PASS {name}/{profile}: {result['nonblack_pixels']}/{w*h} nonblack pixels, {result['seconds']:.1f}s",flush=True)
        if results[-1]['rgb_sha256']!=results[-2]['rgb_sha256']: raise RuntimeError('backpressure changes image')
    sources={line.strip():sha(ROOT/line.strip()) for line in (ROOT/'verification/rtl/system_top_sources.f').read_text().splitlines() if line.strip()}
    sources['verification/rtl/tb_real_dma_workload.sv']=sha(ROOT/'verification/rtl/tb_real_dma_workload.sv')
    (out/'real_rgb_report.json').write_text(json.dumps({'status':'PASS','scope':'T04 real subset output validation, CPU sorted continuation; not full-scene/GT/performance signoff',
        'scene_count':len(names),'run_count':len(results),'failed':0,'results':results,'source_sha256':sources},indent=2),encoding='utf-8')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['prepare','run']);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--scenes',nargs='+',default=['bonsai','counter','room','kitchen','garden'])
    p.add_argument('--count',type=int,default=8192);p.add_argument('--dimension',type=int,default=128)
    p.add_argument('--executable',type=Path,default=ROOT/'tmp/verilator_t04_rgb/tb_t04_rgb.exe')
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
    if a.action=='prepare':prepare(a.output,a.scenes,a.count,a.dimension)
    else:run(a.output,a.scenes,a.executable)
