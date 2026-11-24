"""Same-version shuffled-subset end-to-end BSU/GPR/RGB ablation matrix."""
import argparse,hashlib,json,os,random,re,subprocess,sys,time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.build_full_frame_batch_index import rtl_depth_q16
from scripts.read_rgb888_frame import decode_rgb888
OUT=ROOT/'experiments/t05_20261009/real'
NAMES=['bonsai','counter','room','kitchen','garden']
VARIANTS={'bsu8':(8,1,0,1),'bsu16':(16,1,0,1),'linear':(8,0,0,0),'odd':(8,0,1,0),'bsu8_local_r':(8,1,0,0)}
PYTHON=sys.executable
SIMULATOR='verilator'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def prepare():
    for name in NAMES:
        source=ROOT/'experiments/t04_20261005/real_rgb'/name
        m=json.loads((source/'manifest.json').read_text());sel=source/'selected'
        means=[int(x,16) for x in (sel/'mean.memh').read_text().split()][:512]
        attrs=(sel/'attribute.memh').read_text().split()[:512*9]
        camera=[int(x,16) for x in (sel/'camera.memh').read_text().split()]
        w,h=64,m['height']//2
        for ix,ratio in [(15,w/m['width']),(16,h/m['height']),(17,w/m['width']),(18,h/m['height'])]:
            val=camera[ix]-(1<<64) if camera[ix]>>(63) else camera[ix]
            camera[ix]=round(val*ratio)&((1<<64)-1)
        camera[25:27]=[w,h]
        def signed(v):return v-(1<<27) if v&(1<<26) else v
        xyz=np.array([[signed((x>>b)&((1<<27)-1))/65536 for b in (32,59,86)] for x in means])
        fixed=m['camera_fixed'];depths,_=rtl_depth_q16(xyz,np.array(fixed['rotation_q20'][6:9]),fixed['translation_q16'][2])
        order=sorted(range(512),key=lambda i:(int(depths[i]),i))
        folder=OUT/name;folder.mkdir(parents=True,exist_ok=True)
        # All configurations see IDENTICAL inputs/groups <=8, including K16.
        # Separate full-K16 module tests cover its natural maximum occupancy.
        rng=random.Random(509);trace=[]
        for n,start in enumerate(range(0,512,8)):
            ids=order[start:start+8];shuffled=ids.copy();rng.shuffle(shuffled)
            p=folder/f'rtl_batch_{n:04d}';p.mkdir(exist_ok=True)
            c=camera.copy();c[22:25]=[0,0,0];c[27]=(0x47534301<<32)|len(ids)
            (p/'camera.memh').write_text(''.join(f'{x:016x}\n' for x in c))
            (p/'mean.memh').write_text(''.join(f'{means[i]:032x}\n' for i in shuffled))
            (p/'global_gid.memh').write_text(''.join(f'{i:08x}\n' for i in shuffled))
            (p/'attribute_sparse.memh').write_text(''.join(x+'\n' for i in shuffled for x in attrs[i*9:i*9+9]))
            trace.extend([[int(depths[i]),i,shuffled.index(i)] for i in ids])
        manifest={'scene':name,'camera_index':m['camera_index'],'width':w,'height':h,'gaussians':512,'batches':64,
            'source_manifest':str(source/'manifest.json'),'source_manifest_sha256':sha(source/'manifest.json'),
            'original_gaussian_indices':m['original_gaussian_indices'][:512],
            'scope':'real subset, CPU defines globally ordered batch ranges; deterministic group shuffle requires RTL sorting, T06 autonomy not claimed',
            'expected_sorted_stream':trace,'input_sha256':{p.relative_to(folder).as_posix():sha(p) for p in folder.glob('rtl_batch_*/*.memh')}}
        (folder/'manifest.json').write_text(json.dumps(manifest,indent=2))
        print(f'Prepared {name} {w}x{h}',flush=True)

def build(variant):
    k,bsu,odd,r=VARIANTS[variant];dest=ROOT/f'tmp/verilator_t05_{variant}'
    flags=['--binary','--build','-j','2','-CFLAGS','-D_GLIBCXX_USE_CXX11_ABI=0','--sv','--timing','-Wno-fatal','-DSYNTHESIS',
        '-DTB_FINAL_RGB=1',f'-DTB_BITONIC_SORT={bsu}',f'-DTB_USE_PARALLEL_GROUP_SORT={odd}',f'-DTB_USE_SHARED_RASTER_PE={r}',
        '-DTB_MAX_AXI_WRITES=64','-DTB_MAX_COUNT=8','-DTB_MAX_PIXELS=4096','-DTB_GID_W=32','-DTB_SEQ_W=16',
        f'-DTB_GROUP_CAPACITY={k}',f'-DTB_SORT_CAPACITY={k}','-DTB_STATE_ENTRIES=4096','-DTB_LANES=4',
        '-Irtl/raster','--top-module','tb_real_dma_workload','--Mdir',dest.relative_to(ROOT).as_posix(),
        '-f','verification/rtl/system_top_sources.f','verification/rtl/tb_real_dma_workload.sv','-o','t05.exe']
    folder=OUT/'build';folder.mkdir(exist_ok=True)
    env=os.environ.copy();env.update(MSYSTEM='UCRT64',CHERE_INVOKING='1')
    cmd=[r'D:\Tools\msys64\usr\bin\bash.exe','-lc',"cd /d/3DGS && verilator "+' '.join(flags)]
    (folder/f'{variant}_command.json').write_text(json.dumps(cmd))
    with (folder/f'{variant}.log').open('w') as log:
        p=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    if p.returncode:raise RuntimeError(f'build {variant} failed: '+(folder/f'{variant}.log').read_text()[-3000:])
    print('Built '+variant,flush=True)

def simulate(case):
    name,variant,mode,profile=case
    folder=OUT/name;m=json.loads((folder/'manifest.json').read_text());dest=folder/f'{variant}_m{mode}_{profile}';dest.mkdir(exist_ok=True)
    exe=ROOT/f'tmp/verilator_t05_{variant}/t05.exe'
    actual_simulator='verilator' if SIMULATOR in ('verilator','auto') else 'icarus'
    launch=[str(exe)] if actual_simulator=='verilator' else [r'D:\IcarusVerilog\iverilog\bin\vvp.exe',str(OUT/'build'/f'{variant}.vvp')]
    cmd=launch+[f'+BATCH_ROOT={folder.as_posix()}','+BATCH_LAST=63',f'+FRAME={(dest/"state.memh").as_posix()}',
         f'+RGB={(dest/"rgb.memh").as_posix()}',f'+SORTED_TRACE={(dest/"sorted.txt").as_posix()}',f'+LABEL={name}_{variant}',
         f'+FRAME_MODE={mode}','+MAX_TIMEOUT=2000000']
    lat=[0,0,1,0,2] if profile=='ideal' else [8,2,4,1,8]
    cmd+=[f'+{a}={b}' for a,b in zip(['READ_LATENCY','READ_GAP','READY_PERIOD','READY_LOW','WRITE_RESPONSE_LATENCY'],lat)]
    env=os.environ.copy();env['PATH']=r'D:\Tools\msys64\ucrt64\bin;'+env['PATH']
    t=time.monotonic()
    try:p=subprocess.run(cmd,cwd=ROOT,env=env,capture_output=True,text=True)
    except OSError as error:
        if SIMULATOR!='auto' or getattr(error,'winerror',None)!=4551:raise
        (dest/'executable_block.json').write_text(json.dumps({'winerror':4551,'blocked_executable':str(exe),
            'alternative':'Icarus interpreter on the same RTL; no security policy changes'},indent=2))
        actual_simulator='icarus';cmd=[r'D:\IcarusVerilog\iverilog\bin\vvp.exe',str(OUT/'build'/f'{variant}.vvp')]+cmd[1:]
        p=subprocess.run(cmd,cwd=ROOT,env=env,capture_output=True,text=True)
    (dest/'run.log').write_text(p.stdout+p.stderr);(dest/'command.json').write_text(json.dumps(cmd,indent=2))
    if p.returncode or 'PASS: tb_real_dma_workload' not in p.stdout:raise RuntimeError(f'{case}: '+p.stdout[-3500:]+p.stderr)
    observed=[[int(x) for x in line.split()] for line in (dest/'sorted.txt').read_text().splitlines()]
    if observed!=m['expected_sorted_stream']:raise RuntimeError(f'{case}: sorted stream mismatch')
    data=bytes(int(x,16) for x in (dest/'rgb.memh').read_text().split());w,h=m['width'],m['height'];stride=(w*3+15)&~15
    state=[int(x,16) for x in (dest/'state.memh').read_text().split()];oracle=bytearray(stride*h)
    for i,s in enumerate(state):
        if (s>>55)&65535!=1:continue
        y,x=divmod(i,w)
        for c in range(3):oracle[y*stride+x*3+c]=min(255,(((s>>(c*13))&8191)*255+2048)//4096)
    if data!=oracle:raise RuntimeError(f'{case}: RGB DMA mismatch')
    (dest/'frame.rgb').write_bytes(data);im=decode_rgb888(data,w,h);Image.fromarray(im).save(dest/'frame.png')
    counts=re.search(r'REAL_SHARED_PE enabled=(\d+) main_projection=(\d+) G=(\d+) P=(\d+) R=(\d+) G_stall=(\d+) P_stall=(\d+) R_stall=(\d+) utilization=(\d+) competing=(\d+) main_mac=(\d+)',p.stdout)
    values=list(map(int,counts.groups()));cycles=int(re.search(r'REAL_PERF cycles=(\d+)',p.stdout)[1])
    sort_line=next(x for x in p.stdout.splitlines() if x.startswith('REAL_SORT_WORK'))
    k,bsu,_,r=VARIANTS[variant]
    if bsu and (min(values[2:4])<=0 or (r and values[4]<=0)):raise RuntimeError('missing actual G/P/R traffic')
    if 'error=00000000' not in p.stdout:raise RuntimeError('missing zero final error')
    result={'scene':name,'camera_index':m['camera_index'],'variant':variant,'mode':mode,'profile':profile,'width':w,'height':h,'simulator':actual_simulator,
            'gaussians':512,'batches':64,'cycles':cycles,'G':values[2],'P':values[3],'R':values[4],
            'G_stall':values[5],'P_stall':values[6],'R_stall':values[7],'competing':values[9],
            'sorted_outputs':len(observed),'sort_work':sort_line,'rgb_sha256':sha(dest/'frame.rgb'),
            'nonblack_pixels':int(np.any(im!=0,axis=2).sum()),'status':'PASS','seconds':time.monotonic()-t}
    (dest/'result.json').write_text(json.dumps(result,indent=2));print(f'PASS {case} cycles={cycles}',flush=True)
    return result

def run(names,variants):
    cases=[(n,v,m,p) for n in names for v in variants for m in range(4) for p in ('ideal','limited')]
    report_path=OUT/'report.json'
    if report_path.exists():
        prior=json.loads(report_path.read_text())
        for relative,digest in prior['source_sha256'].items():
            if sha(ROOT/relative)!=digest:raise RuntimeError(f'stale evidence source: {relative}; use a fresh evidence directory')
        pending=[]
        for n,v,m,p in cases:
            saved=OUT/n/f'{v}_m{m}_{p}'/'result.json'
            if saved.exists() and json.loads(saved.read_text()).get('status')=='PASS':continue
            pending.append((n,v,m,p))
        print(f'Reusing {len(cases)-len(pending)} matching-source results; running {len(pending)} remaining',flush=True)
        cases=pending
    results=[]
    with ThreadPoolExecutor(max_workers=12) as pool:
        for r in pool.map(simulate,cases):results.append(r)
    finish()

def finish():
    results=[json.loads(p.read_text()) for n in NAMES for p in (OUT/n).glob('*/result.json')]
    for n in NAMES:
        entries=[r for r in results if r['scene']==n]
        if len({r['rgb_sha256'] for r in entries})>1:raise RuntimeError(f'{n} image differs across modes/variants/profiles')
    paths=[ROOT/x for x in (ROOT/'verification/rtl/system_top_sources.f').read_text().splitlines() if x.strip()]
    paths+=list((ROOT/'rtl').rglob('*.svh'))+[ROOT/'verification/rtl/tb_real_dma_workload.sv']
    report={'status':'PASS' if len(results)==len(NAMES)*len(VARIANTS)*8 else 'PARTIAL','scope':'CPU ordered ranges, shuffled real subsets; all RGB from RTL DMA',
            'results':results,'source_sha256':{p.relative_to(ROOT).as_posix():sha(p) for p in paths}}
    (OUT/'report.json').write_text(json.dumps(report,indent=2))

def build_icarus(variant):
    k,bsu,odd,r=VARIANTS[variant];folder=OUT/'build';folder.mkdir(exist_ok=True)
    cmd=[r'D:\IcarusVerilog\iverilog\bin\iverilog.exe','-g2012','-DSYNTHESIS',
        '-DTB_FINAL_RGB=1',f'-DTB_BITONIC_SORT={bsu}',f'-DTB_USE_PARALLEL_GROUP_SORT={odd}',f'-DTB_USE_SHARED_RASTER_PE={r}',
        '-DTB_MAX_AXI_WRITES=64','-DTB_MAX_COUNT=8','-DTB_MAX_PIXELS=4096','-DTB_GID_W=32','-DTB_SEQ_W=16',
        f'-DTB_GROUP_CAPACITY={k}',f'-DTB_SORT_CAPACITY={k}','-DTB_STATE_ENTRIES=4096','-DTB_LANES=4',
        '-Irtl/raster','-s','tb_real_dma_workload','-o',str(folder/f'{variant}.vvp'),
        '-f','verification/rtl/system_top_sources.f','verification/rtl/tb_real_dma_workload.sv']
    with (folder/f'{variant}_icarus.log').open('w') as log:
        p=subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    (folder/f'{variant}_icarus_command.json').write_text(json.dumps(cmd,indent=2))
    if p.returncode:raise RuntimeError(f'Icarus compile failed {variant}')
    print('Built Icarus '+variant,flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['prepare','build','run','finish']);p.add_argument('--variants',nargs='+',default=list(VARIANTS));p.add_argument('--scenes',nargs='+',default=NAMES)
    p.add_argument('--simulator',choices=['verilator','icarus','auto'],default='verilator');a=p.parse_args();SIMULATOR=a.simulator
    OUT.mkdir(parents=True,exist_ok=True)
    if a.action=='prepare':prepare()
    elif a.action=='build':
        with ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(build if SIMULATOR=='verilator' else build_icarus,a.variants))
    elif a.action=='run':run(a.scenes,a.variants)
    else:finish()
