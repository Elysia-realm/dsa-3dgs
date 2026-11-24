"""Autonomous QSU real-input production-top validation. Never CPU-sort its input."""
import argparse,hashlib,json,os,random,re,subprocess,sys,time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.build_full_frame_batch_index import rtl_depth_q16
from scripts.read_rgb888_frame import decode_rgb888
OUT=ROOT/'experiments/t06_20261014/real_subset'
SCENES=['bonsai','counter','room','kitchen','garden']
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def sources():
    files=(ROOT/'verification/rtl/system_top_sources.f').read_text().splitlines()
    files+=['verification/rtl/tb_real_dma_workload.sv','verification/rtl/t06_scratch_signals.svh','verification/rtl/t06_scratch_memory.svh']
    return {f:sha(ROOT/f) for f in files if f.strip()}
def prepare():
    for name in SCENES:
        dest=OUT/name;dest.mkdir(parents=True,exist_ok=True)
        old=ROOT/'experiments/t04_20261005/real_rgb'/name
        oldm=json.loads((old/'manifest.json').read_text())
        means=[int(x,16) for x in (old/'selected/mean.memh').read_text().split()][:512]
        attrs=(old/'selected/attribute.memh').read_text().split()[:512*9]
        reference=ROOT/'experiments/t05_parallel_20261011/release'/name/'g16'
        camera=[int(x,16) for x in (reference/'rtl_batch_0000/camera.memh').read_text().split()]
        camera[22:25]=[0,0,0];camera[27]=(0x47534301<<32)|512
        order=list(range(512));random.Random(60614).shuffle(order)  # no depth-dependent preprocessing
        def signed(v):return v-(1<<27) if v&(1<<26) else v
        xyz=np.array([[signed((x>>b)&((1<<27)-1))/65536 for b in (32,59,86)] for x in means])
        fixed=oldm['camera_fixed'];depth,overflow=rtl_depth_q16(xyz,np.array(fixed['rotation_q20'][6:9]),fixed['translation_q16'][2])
        assert not np.any(overflow)
        # Oracle only; never used to construct mean ordering, pivots or batches.
        oracle=sorted([[int(depth[i]),means[i]&0xffffffff,seq] for seq,i in enumerate(order)])
        (dest/'mean.memh').write_text(''.join(f'{means[i]:032x}\n' for i in order))
        (dest/'attribute.memh').write_text(''.join(x+'\n' for x in attrs))
        (dest/'camera.memh').write_text(''.join(f'{x:016x}\n' for x in camera))
        m={'scene':name,'camera_index':oldm['camera_index'],'gaussians':512,'full_scene':False,
           'width':camera[25],'height':camera[26],'software_preprocessing':'fixed format encoding and depth-independent random permutation; no CPU pivots/batches/sort',
           'original_gaussian_indices':oldm['original_gaussian_indices'][:512],'expected_sorted_stream':oracle,
           't05_rgb_reference':str(reference/'production16_m0_ideal/frame.rgb'),
           'source_manifest_sha256':sha(old/'manifest.json'),
           'input_sha256':{p.name:sha(p) for p in dest.glob('*.memh')}}
        (dest/'manifest.json').write_text(json.dumps(m,indent=2))
        print('PREPARED',name,flush=True)
def build(engine,pipe=1,max_count=512,max_pixels=4096):
    dest=OUT/'build';dest.mkdir(parents=True,exist_ok=True)
    defs=['-DSYNTHESIS','-DTB_FINAL_RGB=1','-DTB_BITONIC_SORT=1',f'-DTB_BSU_PIPELINED={pipe}','-DTB_USE_SHARED_RASTER_PE=1',
          '-DTB_MAX_AXI_WRITES=64',f'-DTB_MAX_COUNT={max_count}',f'-DTB_MAX_PIXELS={max_pixels}','-DTB_GID_W=32','-DTB_SEQ_W=32',
          '-DTB_GROUP_CAPACITY=16','-DTB_SORT_CAPACITY=16','-DTB_STATE_ENTRIES=4096','-DTB_LANES=4','-Irtl/raster']
    env=os.environ.copy();variant=f'pipe{pipe}';build_variant=variant if max_count==512 else f'{variant}_n{max_count}'
    if engine=='icarus':cmd=[r'D:\IcarusVerilog\iverilog\bin\iverilog.exe','-g2012',*defs,'-s','tb_real_dma_workload','-o',str(dest/f'{variant}.vvp'),'-f','verification/rtl/system_top_sources.f','verification/rtl/tb_real_dma_workload.sv']
    else:
        env.update(MSYSTEM='UCRT64',CHERE_INVOKING='1')
        flags=['--binary','--build','-j','2','-CFLAGS','-D_GLIBCXX_USE_CXX11_ABI=0','--sv','--timing','-Wno-fatal',*defs,
          '--top-module','tb_real_dma_workload','--Mdir',f'tmp/verilator_t06_{build_variant}',
          '-f','verification/rtl/system_top_sources.f','verification/rtl/tb_real_dma_workload.sv','-o','t06_real.exe']
        cmd=[r'D:\Tools\msys64\usr\bin\bash.exe','-lc','cd /d/3DGS && verilator '+' '.join(flags)]
    with (dest/f'{variant}_{engine}.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    (dest/f'{variant}_{engine}_command.json').write_text(json.dumps(cmd,indent=2))
    if r.returncode:raise RuntimeError((dest/f'{variant}_{engine}.log').read_text()[-3000:])
    (dest/f'{variant}_{engine}_sources.json').write_text(json.dumps(sources(),indent=2));print('BUILT',variant,engine,flush=True)
def run(case):
    name,mode,profile,pipe=case;folder=OUT/name;m=json.loads((folder/'manifest.json').read_text());variant=f'pipe{pipe}'
    dest=folder/f'{variant}_m{mode}_{profile}';dest.mkdir(exist_ok=True)
    args=['+AUTO_QSU',f'+MEAN={(folder/"mean.memh").as_posix()}',f'+ATTR={(folder/"attribute.memh").as_posix()}',
          f'+CAMERA={(folder/"camera.memh").as_posix()}',f'+FRAME={(dest/"state.memh").as_posix()}',f'+RGB={(dest/"rgb.memh").as_posix()}',
          f'+SORTED_TRACE={(dest/"sorted.txt").as_posix()}',f'+FRAME_MODE={mode}','+MAX_TIMEOUT=3000000']
    lat=[0,0,1,0,2] if profile=='ideal' else [8,2,4,1,8]
    args += [f'+{a}={b}' for a,b in zip(['READ_LATENCY','READ_GAP','READY_PERIOD','READY_LOW','WRITE_RESPONSE_LATENCY'],lat)]
    env=os.environ.copy();env['PATH']=r'D:\Tools\msys64\ucrt64\bin;'+env['PATH']
    engine='verilator';cmd=[str(ROOT/f'tmp/verilator_t06_{variant}/t06_real.exe'),*args];t=time.monotonic()
    for f,h in json.loads((OUT/'build'/f'{variant}_{engine}_sources.json').read_text()).items():assert sha(ROOT/f)==h,'stale build '+f
    try:r=subprocess.run(cmd,cwd=ROOT,env=env,capture_output=True,text=True)
    except OSError as e:
        if getattr(e,'winerror',None)!=4551:raise
        engine='icarus';cmd=[r'D:\IcarusVerilog\iverilog\bin\vvp.exe',str(OUT/'build'/f'{variant}.vvp'),*args]
        for f,h in json.loads((OUT/'build'/f'{variant}_{engine}_sources.json').read_text()).items():assert sha(ROOT/f)==h,'stale build '+f
        (dest/'executable_block.json').write_text(json.dumps({'winerror':4551,'fallback':'installed Icarus; security policy unchanged'}))
        r=subprocess.run(cmd,cwd=ROOT,env=env,capture_output=True,text=True)
    (dest/'command.json').write_text(json.dumps(cmd,indent=2));(dest/'run.log').write_text(r.stdout+r.stderr)
    if r.returncode or 'PASS: tb_real_dma_workload' not in r.stdout:raise RuntimeError(str(case)+r.stdout[-4500:]+r.stderr[-1500:])
    trace=[[int(x) for x in line.split()] for line in (dest/'sorted.txt').read_text().splitlines()]
    assert trace==m['expected_sorted_stream'],'global sort mismatch'
    rgb=bytes(int(x,16) for x in (dest/'rgb.memh').read_text().split())
    assert rgb==Path(m['t05_rgb_reference']).read_bytes(),'reference image differs'
    (dest/'frame.rgb').write_bytes(rgb);Image.fromarray(decode_rgb888(rgb,m['width'],m['height'])).save(dest/'frame.png')
    qsu={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',next(x for x in r.stdout.splitlines() if x.startswith('REAL_QSU')))}
    assert qsu['input']==512 and qsu['partitions']>0 and qsu['reads']==qsu['axi_reads'] and qsu['writes']==qsu['axi_writes']
    assert 'error=00000000' in r.stdout
    row={'scene':name,'mode':mode,'profile':profile,'pipeline':pipe,'status':'PASS','qsu':qsu,
         'cycles':int(re.search(r'REAL_PERF cycles=(\d+)',r.stdout)[1]),'rgb_sha256':sha(dest/'frame.rgb'),
         'simulator':engine,'seconds':time.monotonic()-t,'source_sha256':sources()}
    (dest/'result.json').write_text(json.dumps(row,indent=2));print('PASS',case,row['cycles'],flush=True);return row
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['prepare','build','run']);p.add_argument('--engine',default='icarus');p.add_argument('--pipe',type=int,default=1)
    p.add_argument('--out',type=Path,default=OUT)
    p.add_argument('--scenes',nargs='+',default=SCENES);p.add_argument('--modes',nargs='+',type=int,default=list(range(4)));p.add_argument('--profiles',nargs='+',default=['ideal','limited']);a=p.parse_args();OUT=a.out.resolve()
    if a.action=='prepare':prepare()
    elif a.action=='build':build(a.engine,a.pipe)
    else:
        cases=[(n,m,p,a.pipe) for n in a.scenes for m in a.modes for p in a.profiles]
        with ThreadPoolExecutor(max_workers=5) as pool:rows=list(pool.map(run,cases))
        (OUT/'latest_run.json').write_text(json.dumps({'status':'PASS','results':rows},indent=2))
