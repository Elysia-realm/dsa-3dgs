"""Full-model QSU+BSU capacity/global-order proof; NOT production-render proof."""
import argparse,json,os,subprocess,sys,time
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t06_qsu_units import FILES,sha
from scripts.build_full_frame_batch_index import rtl_depth_q16
from model.io.scene import open_ply_vertices
OUT=ROOT/'experiments/t06_20261014/full_order'
SCENES=['bonsai','counter','room','kitchen','garden']
def prepare(names):
    for name in names:
        dest=OUT/name;dest.mkdir(parents=True,exist_ok=True)
        ply=ROOT/'data'/name/'point_cloud/iteration_30000/point_cloud.ply'
        h,v=open_ply_vertices(ply)
        reference=json.loads((ROOT/'experiments/t04_20261005/real_rgb'/name/'manifest.json').read_text())
        xyz=np.column_stack([v[f] for f in ['x','y','z']])
        cam=reference['camera_fixed'];depth,overflow=rtl_depth_q16(xyz,np.array(cam['rotation_q20'][6:9]),cam['translation_q16'][2])
        n=h.vertex_count
        # PLY order is retained. GID and full 32-bit sequence are the PLY index.
        def write(path,indices):
            with path.open('w') as f:
                for i in indices:f.write(f'{((int(depth[i])&((1<<27)-1))<<64)|(int(i)<<32)|int(i):023x}\n')
        write(dest/'input.memh',range(n))
        write(dest/'expected.memh',np.argsort(depth,kind='stable'))  # oracle ONLY
        m={'scene':name,'camera_index':reference['camera_index'],'gaussians':n,'full_scene':True,
           'scope':'all PLY records; exact quantized/saturated depth oracle at QSU input, not production top/visibility/RGB validation',
           'prepass_numeric_overflows':int(overflow.sum()),'input_order':'original PLY; CPU never pivots or constructs subsets',
           'source_ply_sha256':sha(ply),'input_sha256':sha(dest/'input.memh'),'expected_sha256':sha(dest/'expected.memh')}
        (dest/'manifest.json').write_text(json.dumps(m,indent=2));print('PREPARED',name,n,'overflows',int(overflow.sum()),flush=True)
def build():
    folder=OUT/'build_v2';folder.mkdir(parents=True,exist_ok=True)
    flags=['--binary','--build','-j','2','-CFLAGS','-D_GLIBCXX_USE_CXX11_ABI=0','--sv','--timing','-Wno-fatal','-DSYNTHESIS','-DT06_MAX_COUNT=6000000',
           '--top-module','tb_t06_qsu_bsu','--Mdir','tmp/verilator_t06_full_order_v2',*FILES,'-o','t06_full_order.exe']
    cmd=[r'D:\Tools\msys64\usr\bin\bash.exe','-lc','cd /d/3DGS && verilator '+' '.join(flags)]
    env=os.environ.copy();env.update(MSYSTEM='UCRT64',CHERE_INVOKING='1')
    with (folder/'build.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    (folder/'command.json').write_text(json.dumps(cmd,indent=2))
    if r.returncode:raise RuntimeError((folder/'build.log').read_text()[-2500:])
    (folder/'sources.json').write_text(json.dumps({f:sha(ROOT/f) for f in FILES},indent=2));print('BUILT',flush=True)
def run(names):
    for name in names:
        for f,h in json.loads((OUT/'build_v2/sources.json').read_text()).items():assert sha(ROOT/f)==h,'stale build'
        dest=OUT/name;m=json.loads((dest/'manifest.json').read_text())
        cmd=[str(ROOT/'tmp/verilator_t06_full_order_v2/t06_full_order.exe'),f'+N={m["gaussians"]}',f'+INPUT={(dest/"input.memh").as_posix()}',f'+EXPECTED={(dest/"expected.memh").as_posix()}']
        env=os.environ.copy();env['PATH']=r'D:\Tools\msys64\ucrt64\bin;'+env['PATH'];t=time.monotonic()
        (dest/'command_v2.json').write_text(json.dumps(cmd,indent=2))
        with (dest/'run_v2.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
        log=(dest/'run_v2.log').read_text();assert r.returncode==0 and 'PASS T06' in log,log[-2500:]
        (dest/'result_v2.json').write_text(json.dumps({'status':'PASS','scene':name,'gaussians':m['gaussians'],'seconds':time.monotonic()-t,'source_sha256':{f:sha(ROOT/f) for f in FILES}},indent=2))
        print('PASS',name,log.splitlines()[0],flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['prepare','build','run']);p.add_argument('--scenes',nargs='+',default=SCENES);a=p.parse_args()
    if a.action=='prepare':prepare(a.scenes)
    elif a.action=='build':build()
    else:run(a.scenes)
