"""Bounded B/W/F production-top comparison; Kitchen/Garden temporarily excluded.

Existing RTL options are exercised, not silently made production defaults.
The single-command timing observer includes the initial camera fetch.
"""
import argparse,json,os,re,shutil,subprocess,sys,time,traceback
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t06_real import sha
from scripts.read_rgb888_frame import decode_rgb888
from scripts.prepare_t06_full_render import attribute_words
from scripts.build_full_frame_batch_index import pack_mean_records,rtl_depth_q16
from model.io.scene import discover_scenes,read_cameras,scaled_camera
from model.io.dma_workload import select_real_gaussians,camera_fixed
BASE=ROOT/'experiments/t06_perf_20261018';DATA=BASE/'subset';JOB=BASE/'jobs'
SCENES={'bonsai':146,'counter':120,'room':155,'train':150,'truck':125}
VARIANTS={'B':(2,2,0,0),'W':(4,4,0,0),'F':(4,4,1,1)}
BUILD_TAG='perf'
BENCH_TOP='tb_t06_perf_workload'
EXTRA_DEFINES={}
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def save(p,x):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(x,ensure_ascii=False,indent=2),encoding='utf-8')
def source_hashes():
    files=(ROOT/'verification/rtl/system_top_sources.f').read_text().splitlines()
    files+=[f'verification/rtl/{BENCH_TOP}.sv','verification/rtl/t06_perf_measurements.svh',
      'verification/rtl/t06_scratch_signals.svh','verification/rtl/t06_memory_scratch.svh','verification/rtl/t06_memory_layout.svh']
    return {f:sha(ROOT/f) for f in files if f.strip()}
def prepare():
    scenes={s.name:s for s in discover_scenes(ROOT/'data')}
    for n,cam_id in SCENES.items():
        out=DATA/n;out.mkdir(parents=True,exist_ok=True)
        if (out/'manifest.json').exists():
            for f,h in read(out/'manifest.json')['input_sha256'].items():assert sha(out/f)==h
            continue
        if n in ['bonsai','counter','room']:
            old=ROOT/'experiments/t06_20261018/subset'/n
            for f in ['mean.memh','attribute.memh','camera.memh','manifest.json','expected_sorted.txt']:shutil.copy2(old/f,out/f)
        else:
            scene=scenes[n];camera=scaled_camera(read_cameras(scene.cameras_json)[cam_id],128)
            gids,batch,_=select_real_gaussians(scene,camera,512);fixed=camera_fixed(camera)
            aw=attribute_words(batch);mw=pack_mean_records(np.arange(512,dtype=np.uint32),batch.mean)
            cam=[*fixed['rotation_q20'],*fixed['translation_q16'],*fixed['position_q16'],*fixed['fx_fy_cx_cy_q16'],*fixed['near_far_q16'],fixed['regularizer_q8'],0,0,0,camera.width,camera.height,(0x47534301<<32)|512]
            (out/'camera.memh').write_text(''.join(f'{int(v)&((1<<64)-1):016x}\n' for v in cam))
            (out/'mean.memh').write_text(''.join(f'{int(hi):016x}{int(lo):016x}\n' for lo,hi in mw))
            (out/'attribute.memh').write_text(''.join(f'{int(row[k+1]):016x}{int(row[k]):016x}\n' for row in aw for k in range(0,18,2)))
            depth,overflow=rtl_depth_q16(batch.mean,np.array(fixed['rotation_q20'][6:9]),fixed['translation_q16'][2]);assert not overflow.any()
            ids=np.flatnonzero((depth>=fixed['near_far_q16'][0])&(depth<=fixed['near_far_q16'][1]));assert len(ids)==512
            order=ids[np.argsort(depth[ids],kind='stable')]
            (out/'expected_sorted.txt').write_text(''.join(f'{int(depth[i])} {int(i)} {int(i)}\n' for i in order))
            save(out/'manifest.json',dict(scene=n,camera_index=cam_id,gaussians=512,visible=512,full_scene=False,width=camera.width,height=camera.height,
              original_gaussian_indices=gids,software_preprocessing='deterministic scene-wide visible subset in original PLY order, encode only; no CPU pivots or batches',
              source_ply_sha256=sha(scene.final_ply),input_sha256={p.name:sha(p) for p in out.glob('*.memh')},oracle_sha256=sha(out/'expected_sorted.txt')))
        print('PREPARED',n,flush=True)
def build(v):
    win,mshr,resp,commit=VARIANTS[v];dest=BASE/'build'/v;dest.mkdir(parents=True,exist_ok=True);src=source_hashes()
    exe=ROOT/f'tmp/verilator_t06_{BUILD_TAG}_{v}/t06_perf.exe'
    if (dest/'sources.json').exists() and exe.exists():assert read(dest/'sources.json')==src;return
    flags=['--binary','--build','-j','2','-CFLAGS','-D_GLIBCXX_USE_CXX11_ABI=0','--sv','--timing','-Wno-fatal','-DSYNTHESIS',
      '-DTB_FINAL_RGB=1','-DTB_BITONIC_SORT=1','-DTB_BSU_PIPELINED=1','-DTB_USE_SHARED_RASTER_PE=1','-DTB_MAX_AXI_WRITES=64',
      '-DTB_MAX_COUNT=512','-DTB_MAX_PIXELS=16384','-DTB_GID_W=32','-DTB_SEQ_W=32','-DTB_GROUP_CAPACITY=16','-DTB_SORT_CAPACITY=16',
      '-DTB_STATE_ENTRIES=4096','-DTB_LANES=4',f'-DTB_STATE_WINDOW_ENTRIES={win}',f'-DTB_STATE_MSHR_COUNT={mshr}',
      f'-DTB_RESPONSE_BLEND_BYPASS={resp}',f'-DTB_BLEND_COMMIT_BYPASS={commit}','-Irtl/raster',
      *EXTRA_DEFINES.get(v,[]),'--top-module',BENCH_TOP,'--Mdir',f'tmp/verilator_t06_{BUILD_TAG}_{v}',
      '-f','verification/rtl/system_top_sources.f',f'verification/rtl/{BENCH_TOP}.sv','-o','t06_perf.exe']
    cmd=[r'D:\Tools\msys64\usr\bin\bash.exe','-lc','cd /d/3DGS && verilator '+' '.join(flags)]
    env=os.environ.copy();env.update(MSYSTEM='UCRT64',CHERE_INVOKING='1');save(dest/'command.json',cmd)
    with (dest/'build.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    assert r.returncode==0,(dest/'build.log').read_text()[-2000:];assert source_hashes()==src
    save(dest/'sources.json',src);save(dest/'binary.json',{'sha256':sha(exe),'path':str(exe)});print('BUILT',v,flush=True)
def references():
    # Frozen, already validated legacy sorting oracle; never the candidate path.
    from scripts import run_t06_memory_release as memory
    from scripts import run_t06_oracle_render as oracle
    memory.configure();oracle.OUT=DATA
    (DATA/'oracle_build').mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/'experiments/t06_20261018/full_render/oracle_build/sources.json',DATA/'oracle_build/sources.json')
    for n in SCENES:
        if not (DATA/n/'oracle/result.json').exists():oracle.run(n)
        else:assert read(DATA/n/'oracle/result.json')['source_sha256']==oracle.source_hashes()
def icarus_binary(v):
    win,mshr,resp,commit=VARIANTS[v];dest=BASE/'build'/v;dest.mkdir(parents=True,exist_ok=True);binary=dest/'perf.vvp'
    src=source_hashes();marker=dest/'icarus_sources.json'
    if marker.exists() and binary.exists():assert read(marker)==src;return binary
    defs=['-DSYNTHESIS','-DTB_FINAL_RGB=1','-DTB_BITONIC_SORT=1','-DTB_BSU_PIPELINED=1','-DTB_USE_SHARED_RASTER_PE=1',
      '-DTB_MAX_AXI_WRITES=64','-DTB_MAX_COUNT=512','-DTB_MAX_PIXELS=16384','-DTB_GID_W=32','-DTB_SEQ_W=32',
      '-DTB_GROUP_CAPACITY=16','-DTB_SORT_CAPACITY=16','-DTB_STATE_ENTRIES=4096','-DTB_LANES=4',
      f'-DTB_STATE_WINDOW_ENTRIES={win}',f'-DTB_STATE_MSHR_COUNT={mshr}',f'-DTB_RESPONSE_BLEND_BYPASS={resp}',f'-DTB_BLEND_COMMIT_BYPASS={commit}']
    cmd=[r'D:\IcarusVerilog\iverilog\bin\iverilog.exe','-g2012',*defs,*EXTRA_DEFINES.get(v,[]),'-Irtl/raster','-s',BENCH_TOP,'-o',str(binary),'-f','verification/rtl/system_top_sources.f',f'verification/rtl/{BENCH_TOP}.sv']
    save(dest/'icarus_command.json',cmd)
    with (dest/'icarus_build.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    assert r.returncode==0,(dest/'icarus_build.log').read_text()[-2000:];assert source_hashes()==src;save(marker,src)
    return binary
def run(case):
    v,n,mode,profile=case;folder=DATA/n;m=read(folder/'manifest.json');dest=folder/f'{v}_m{mode}_{profile}';dest.mkdir(exist_ok=True)
    src=read(BASE/'build'/v/'sources.json');assert src==source_hashes()
    if (dest/'result.json').exists():
        row=read(dest/'result.json');assert row['source_sha256']==src;assert sha(dest/'frame.rgb')==row['rgb_sha256'];return row
    exe=ROOT/f'tmp/verilator_t06_{BUILD_TAG}_{v}/t06_perf.exe';assert sha(exe)==read(BASE/'build'/v/'binary.json')['sha256']
    cmd=[str(exe),'+AUTO_QSU',f'+MEAN={(folder/"mean.memh").as_posix()}',f'+ATTR={(folder/"attribute.memh").as_posix()}',
      f'+CAMERA={(folder/"camera.memh").as_posix()}',f'+FRAME={(dest/"state.memh").as_posix()}',f'+RGB={(dest/"rgb.memh").as_posix()}',
      f'+SORTED_TRACE={(dest/"sorted.txt").as_posix()}',f'+FRAME_MODE={mode}','+MAX_TIMEOUT=10000000']
    lat=[0,0,1,0,2] if profile=='ideal' else [8,2,4,1,8]
    cmd += [f'+{k}={val}' for k,val in zip(['READ_LATENCY','READ_GAP','READY_PERIOD','READY_LOW','WRITE_RESPONSE_LATENCY'],lat)]
    save(dest/'command.json',cmd);env=os.environ.copy();env['PATH']=r'D:\Tools\msys64\ucrt64\bin;'+env['PATH'];start=time.monotonic();engine='verilator'
    if (BASE/'build'/v/'executable_block.json').exists():
        cmd=[r'D:\IcarusVerilog\iverilog\bin\vvp.exe',str(icarus_binary(v)),*cmd[1:]];engine='icarus';save(dest/'command.json',cmd)
    try:
        with (dest/'run.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    except OSError as e:
        if getattr(e,'winerror',None)!=4551:raise
        save(BASE/'build'/v/'executable_block.json',dict(winerror=4551,binary_sha256=sha(exe),action='Use installed Icarus; no security-policy bypass'))
        cmd=[r'D:\IcarusVerilog\iverilog\bin\vvp.exe',str(icarus_binary(v)),*cmd[1:]];engine='icarus';save(dest/'command.json',cmd)
        with (dest/'run.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    log=(dest/'run.log').read_text();assert r.returncode==0 and f'PASS: {BENCH_TOP}' in log,log[-3000:]
    blocks={line.split()[0]:{k:int(val) for k,val in re.findall(r'(\w+)=(\d+)',line)} for line in log.splitlines() if line.startswith('REAL_')}
    t=blocks['REAL_END_TO_END'];assert t['command_count']==1 and t['command_cycles']==t['camera_setup_cycles']+t['post_batch_cycles']
    assert t['command_cycles']>blocks['REAL_PERF']['cycles'] and abs(t['post_batch_cycles']-blocks['REAL_PERF']['cycles'])<=2
    assert (t['window'],t['mshr'],t['response_bypass'],t['commit_bypass'])==VARIANTS[v]
    assert blocks['REAL_DMA_COUNTS']['mean_beats']==m['gaussians'] and blocks['REAL_DMA_COUNTS']['camera_beats']==14
    assert (dest/'sorted.txt').read_bytes()==(folder/'expected_sorted.txt').read_bytes()
    rgb=bytes(int(s,16) for s in (dest/'rgb.memh').read_text().split());assert rgb==(folder/'oracle/frame.rgb').read_bytes()
    # Independently check state-to-RGB conversion, including background and row padding.
    state=[int(s,16) for s in (dest/'state.memh').read_text().split()];w,h=m['width'],m['height'];stride=(w*3+15)&~15;expected=bytearray(stride*h)
    for i,s in enumerate(state):
        if (s>>55)&65535!=1:continue
        y,x=divmod(i,w)
        for c in range(3):expected[y*stride+3*x+c]=min(255,(((s>>(13*c))&8191)*255+2048)//4096)
    assert rgb==expected;assert source_hashes()==src
    (dest/'frame.rgb').write_bytes(rgb);Image.fromarray(decode_rgb888(rgb,w,h)).save(dest/'frame.png')
    if VARIANTS[v][2]:assert blocks['REAL_BLEND_BYPASS']['fires']>0
    if VARIANTS[v][3]:assert blocks['REAL_COMMIT_BYPASS']['fires']>0
    row=dict(status='PASS',variant=v,scene=n,mode=mode,profile=profile,simulator=engine,full_scene=False,gaussians=512,seconds=time.monotonic()-start,
      command_cycles=t['command_cycles'],counters=blocks,rgb_sha256=sha(dest/'frame.rgb'),source_sha256=src,input_sha256=m['input_sha256'])
    save(dest/'result.json',row);print('PASS',v,n,mode,profile,t['command_cycles'],flush=True);return row
def matrix():
    rows=[]
    for v in VARIANTS:
        # One serial smoke initializes any allowed simulator fallback before parallel runs.
        run((v,next(iter(SCENES)),0,'ideal'))
        cases=[(v,n,m,p) for n in SCENES for m in range(4) for p in ['ideal','limited']]
        with ThreadPoolExecutor(max_workers=4) as pool:rows+=list(pool.map(run,cases))
    comparisons=[]
    for n in SCENES:
        for m in range(4):
            for p in ['ideal','limited']:
                x={r['variant']:r['command_cycles'] for r in rows if (r['scene'],r['mode'],r['profile'])==(n,m,p)}
                comparisons.append(dict(scene=n,mode=m,profile=p,cycles=x,W_saved_percent=100*(x['B']-x['W'])/x['B'],F_saved_percent=100*(x['B']-x['F'])/x['B'],bypass_saved_percent=100*(x['W']-x['F'])/x['W']))
    save(BASE/'selection_report.json',dict(status='PASS_SUBSET_SELECTION_NOT_RELEASE',signed_off=False,results=rows,comparisons=comparisons,
      scope='five real subsets, three configs, four modes, two AXI; full-scene, default integration, PPA and 30FPS not signed off'))
def status(phase,**kw):save(JOB/'status.json',dict(status=phase,pid=os.getpid(),signed_off=False,**kw))
def main(action):
    if action in ['all','prepare']:status('PREPARING');prepare()
    if action in ['all','build']:
        status('BUILDING')
        for v in VARIANTS:build(v)
    if action in ['all','run']:
        status('REFERENCE_VALIDATION');references();status('RUNNING_120_CASE_MATRIX');matrix();status('SUBSET_SELECTION_FINISHED_REVIEW_REQUIRED')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['all','prepare','build','run']);a=p.parse_args();JOB.mkdir(parents=True,exist_ok=True)
    with (JOB/'worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main(a.action)
        except BaseException as e:status('FAILED_REVIEW_REQUIRED',error=repr(e));traceback.print_exc();raise
