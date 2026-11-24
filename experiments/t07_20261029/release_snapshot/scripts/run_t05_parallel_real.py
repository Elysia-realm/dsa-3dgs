"""T05 spatial/folded, common and native capacity, multi-subset RGB matrix."""
import sys,json,random,subprocess,os,time,re,hashlib,argparse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.build_full_frame_batch_index import rtl_depth_q16
from scripts.read_rgb888_frame import decode_rgb888
OUT=ROOT/'experiments/t05_parallel_20261011/real'
NAMES=['bonsai','counter','room','kitchen','garden']
CONFIGS={'fold8':(8,0),'pipe8':(8,1),'fold16':(16,0),'pipe16':(16,1)}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def sources():
    paths=[ROOT/x for x in (ROOT/'verification/rtl/system_top_sources.f').read_text().splitlines() if x.strip()]
    paths+=list((ROOT/'rtl').rglob('*.svh'))+[ROOT/'verification/rtl/tb_real_dma_workload.sv']
    return {p.relative_to(ROOT).as_posix():sha(p) for p in paths}

def prepare():
    for name in NAMES:
        old=ROOT/'experiments/t04_20261005/real_rgb'/name
        m=json.loads((old/'manifest.json').read_text());sel=old/'selected'
        means=[int(x,16) for x in (sel/'mean.memh').read_text().split()][:512]
        attrs=(sel/'attribute.memh').read_text().split()[:512*9]
        camera=[int(x,16) for x in (sel/'camera.memh').read_text().split()]
        w,h=64,m['height']//2
        for ix,scale in [(15,w/m['width']),(16,h/m['height']),(17,w/m['width']),(18,h/m['height'])]:
            v=camera[ix]-(1<<64) if camera[ix]>>63 else camera[ix];camera[ix]=round(v*scale)&((1<<64)-1)
        camera[25:27]=[w,h]
        def signed(v):return v-(1<<27) if v&(1<<26) else v
        xyz=np.array([[signed((x>>b)&((1<<27)-1))/65536 for b in (32,59,86)] for x in means])
        fixed=m['camera_fixed'];depths,overflow=rtl_depth_q16(xyz,np.array(fixed['rotation_q20'][6:9]),fixed['translation_q16'][2])
        assert not np.any(overflow)
        order=sorted(range(512),key=lambda i:(int(depths[i]),i))
        for size in (8,16):
            folder=OUT/name/f'g{size}';folder.mkdir(parents=True,exist_ok=True)
            rng=random.Random(11505);trace=[];batches=[];pos=0
            while pos<len(order):
                ids=order[pos:pos+4*size]
                # Real subsets cannot straddle identical-depth pivot boundaries.
                if any(depths[ids[b-1]]==depths[ids[b]] for b in range(size,len(ids),size)):
                    ids=ids[:size]
                pivots=[int(depths[ids[b]]) for b in range(size,len(ids),size)]
                pivots=(pivots+[int(depths[ids[-1]])+1]*3)[:3]
                shuffled=ids.copy();rng.shuffle(shuffled)
                assignment=np.searchsorted(pivots,np.array([depths[i] for i in ids]),side='right')
                counts=[int(np.sum(assignment==g)) for g in range(4)];assert max(counts)<=size
                n=len(batches);p=folder/f'rtl_batch_{n:04d}';p.mkdir(exist_ok=True)
                c=camera.copy();c[22:25]=pivots;c[27]=(0x47534301<<32)|len(ids)
                (p/'camera.memh').write_text(''.join(f'{x:016x}\n' for x in c))
                (p/'mean.memh').write_text(''.join(f'{means[i]:032x}\n' for i in shuffled))
                (p/'global_gid.memh').write_text(''.join(f'{i:08x}\n' for i in shuffled))
                (p/'attribute_sparse.memh').write_text(''.join(x+'\n' for i in shuffled for x in attrs[9*i:9*i+9]))
                trace += [[int(depths[i]),i,shuffled.index(i)] for i in ids]
                batches.append({'index':n,'count':len(ids),'group_counts':counts,'pivots':pivots});pos+=len(ids)
            manifest={'scene':name,'camera_index':m['camera_index'],'width':w,'height':h,'gaussians':512,'subset_capacity':size,'batches':batches,
                'expected_sorted_stream':trace,'original_gaussian_indices':m['original_gaussian_indices'][:512],
                'source_manifest':str(old/'manifest.json'),'source_manifest_sha256':sha(old/'manifest.json'),
                'scope':'real subset, CPU globally ordered ranges/pivots; input shuffled across four subsets per command; no T06 autonomy claim',
                'input_sha256':{p.relative_to(folder).as_posix():sha(p) for p in folder.glob('rtl_batch_*/*.memh')}}
            (folder/'manifest.json').write_text(json.dumps(manifest,indent=2));print(name,size,len(batches),flush=True)

def build(variant,engine,release=False):
    k,pipe=CONFIGS[variant];folder=OUT/'build';folder.mkdir(parents=True,exist_ok=True)
    defs=['-DSYNTHESIS','-DTB_FINAL_RGB=1','-DTB_BITONIC_SORT=1',f'-DTB_BSU_PIPELINED={pipe}','-DTB_USE_SHARED_RASTER_PE=1',
        '-DTB_MAX_AXI_WRITES=64','-DTB_MAX_COUNT=64','-DTB_MAX_PIXELS=4096','-DTB_GID_W=32','-DTB_SEQ_W=16',
        f'-DTB_GROUP_CAPACITY={k}',f'-DTB_SORT_CAPACITY={k}','-DTB_STATE_ENTRIES=4096','-DTB_LANES=4','-Irtl/raster']
    env=os.environ.copy()
    if release:defs.append('-DTB_RELEASE_DEFAULTS')
    if engine=='icarus':cmd=[r'D:\IcarusVerilog\iverilog\bin\iverilog.exe','-g2012',*defs,'-s','tb_real_dma_workload','-o',str(folder/f'{variant}.vvp'),
         '-f','verification/rtl/system_top_sources.f','verification/rtl/tb_real_dma_workload.sv']
    else:
        env.update(MSYSTEM='UCRT64',CHERE_INVOKING='1')
        flags=['--binary','--build','-j','2','-CFLAGS','-D_GLIBCXX_USE_CXX11_ABI=0','--sv','--timing','-Wno-fatal',*defs,
               '--top-module','tb_real_dma_workload','--Mdir',f'tmp/verilator_t05_parallel_{variant}',
               '-f','verification/rtl/system_top_sources.f','verification/rtl/tb_real_dma_workload.sv','-o','t05_parallel.exe']
        cmd=[r'D:\Tools\msys64\usr\bin\bash.exe','-lc','cd /d/3DGS && verilator '+' '.join(flags)]
    with (folder/f'{variant}_{engine}.log').open('w') as log:c=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    (folder/f'{variant}_{engine}_command.json').write_text(json.dumps(cmd,indent=2))
    if c.returncode:raise RuntimeError((folder/f'{variant}_{engine}.log').read_text()[-3000:])
    (folder/f'{variant}_{engine}_sources.json').write_text(json.dumps(sources(),indent=2))
    print('BUILT',variant,engine,flush=True)

def simulate(case):
    name,size,variant,mode,profile=case;k,pipe=CONFIGS[variant]
    folder=OUT/name/f'g{size}';m=json.loads((folder/'manifest.json').read_text());dest=folder/f'{variant}_m{mode}_{profile}';dest.mkdir(exist_ok=True)
    for key,value in json.loads((OUT/'build'/f'{variant}_icarus_sources.json').read_text()).items():assert sha(ROOT/key)==value,'stale build'
    args=[f'+BATCH_ROOT={folder.as_posix()}',f'+BATCH_LAST={len(m["batches"])-1}',f'+FRAME={(dest/"state.memh").as_posix()}',
          f'+RGB={(dest/"rgb.memh").as_posix()}',f'+SORTED_TRACE={(dest/"sorted.txt").as_posix()}',f'+FRAME_MODE={mode}','+MAX_TIMEOUT=3000000']
    lat=[0,0,1,0,2] if profile=='ideal' else [8,2,4,1,8]
    args += [f'+{a}={b}' for a,b in zip(['READ_LATENCY','READ_GAP','READY_PERIOD','READY_LOW','WRITE_RESPONSE_LATENCY'],lat)]
    env=os.environ.copy();env['PATH']=r'D:\Tools\msys64\ucrt64\bin;'+env['PATH']
    cmd=[str(ROOT/f'tmp/verilator_t05_parallel_{variant}/t05_parallel.exe'),*args];engine='verilator';t=time.monotonic()
    try:c=subprocess.run(cmd,cwd=ROOT,env=env,capture_output=True,text=True)
    except OSError as e:
        if getattr(e,'winerror',None)!=4551:raise
        (dest/'executable_block.json').write_text(json.dumps({'winerror':4551,'fallback':'installed Icarus; security policy unchanged'}))
        engine='icarus';cmd=[r'D:\IcarusVerilog\iverilog\bin\vvp.exe',str(OUT/'build'/f'{variant}.vvp'),*args]
        c=subprocess.run(cmd,cwd=ROOT,env=env,capture_output=True,text=True)
    (dest/'command.json').write_text(json.dumps(cmd,indent=2));(dest/'run.log').write_text(c.stdout+c.stderr)
    if c.returncode or 'PASS: tb_real_dma_workload' not in c.stdout:raise RuntimeError(f'{case}: '+c.stdout[-2500:]+c.stderr)
    trace=[[int(x) for x in line.split()] for line in (dest/'sorted.txt').read_text().splitlines()]
    assert trace==m['expected_sorted_stream'],f'{case}: sort mismatch'
    rgb=bytes(int(x,16) for x in (dest/'rgb.memh').read_text().split());w,h=m['width'],m['height'];stride=(w*3+15)&~15
    oracle=bytearray(stride*h);state=[int(x,16) for x in (dest/'state.memh').read_text().split()]
    for i,s in enumerate(state):
        if (s>>55)&65535!=1:continue
        y,x=divmod(i,w)
        for ch in range(3):oracle[y*stride+x*3+ch]=min(255,(((s>>(ch*13))&8191)*255+2048)//4096)
    assert rgb==oracle,f'{case}: RGB mismatch'
    (dest/'frame.rgb').write_bytes(rgb);Image.fromarray(decode_rgb888(rgb,w,h)).save(dest/'frame.png')
    shared=dict(re.findall(r'(\w+)=(\d+)',next(line for line in c.stdout.splitlines() if line.startswith('REAL_SHARED_PE'))))
    sort=dict(re.findall(r'(\w+)=(\d+)',next(line for line in c.stdout.splitlines() if line.startswith('REAL_SORT_WORK'))))
    assert min(int(shared[a]) for a in ['G','P','R'])>0
    assert int(sort['caps'])==9+(16 if pipe else 0)+(k<<16)
    assert 'error=00000000' in c.stdout
    row={'scene':name,'camera_index':m['camera_index'],'subset_capacity':size,'k':k,'pipeline':pipe,'variant':variant,'mode':mode,'profile':profile,
         'width':w,'height':h,'gaussians':512,'batches':len(m['batches']),'cycles':int(re.search(r'REAL_PERF cycles=(\d+)',c.stdout)[1]),
         'rgb_sha256':sha(dest/'frame.rgb'),'sorted_outputs':len(trace),'shared':shared,'sort':sort,'simulator':engine,'seconds':time.monotonic()-t,'status':'PASS'}
    (dest/'result.json').write_text(json.dumps(row,indent=2));print('PASS',case,row['cycles'],flush=True);return row

def finish():
    results=[json.loads(p.read_text()) for p in OUT.glob('*/g*/*/result.json')]
    for name in NAMES:assert len({r['rgb_sha256'] for r in results if r['scene']==name})<=1,'different images'
    report={'status':'PASS' if len(results)==240 else 'PARTIAL','results':results,'source_sha256':sources(),
            'scope':'common size8 and native size16; 4 subsets per command where depth boundaries permit; no CPU cost in RTL cycles'}
    (OUT/'report.json').write_text(json.dumps(report,indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['prepare','build','run','finish']);p.add_argument('--scenes',nargs='+',default=NAMES)
    p.add_argument('--variants',nargs='+',default=list(CONFIGS));p.add_argument('--engine',choices=['icarus','verilator'],default='icarus');a=p.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    if a.action=='prepare':prepare()
    elif a.action=='build':
        with ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(lambda v:build(v,a.engine),a.variants))
    elif a.action=='run':
        cases=[(s,n,v,m,p) for s in a.scenes for n in (8,16) for v in a.variants if CONFIGS[v][0]>=n for m in range(4) for p in ['ideal','limited']]
        if (OUT/'report.json').exists():
            prior=json.loads((OUT/'report.json').read_text());assert prior['source_sha256']==sources(),'stale run sources'
        pending=[c for c in cases if not (OUT/c[0]/f'g{c[1]}'/f'{c[2]}_m{c[3]}_{c[4]}'/'result.json').exists()]
        print('pending',len(pending),'reused',len(cases)-len(pending),flush=True)
        with ThreadPoolExecutor(max_workers=12) as pool:list(pool.map(simulate,pending))
        finish()
    else:finish()
