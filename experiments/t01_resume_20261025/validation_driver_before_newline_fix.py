"""Native Linux replay of frozen production workloads, with fresh outputs only."""
import argparse,json,os,re,shlex,sys,traceback
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,WORK,PROFILE,OLD,FULL,read,save,sha,frozen,initialize,run_logged
from scripts.t06_release_common import assert_command_profile
from scripts.read_rgb888_frame import decode_rgb888

SCENES=read(PROFILE)['scenes']
BUILD_COMMANDS={'subset':OLD/'build/H/command.json','full':FULL/'build/command.json',
 'repeat':OLD/'repeat/build/H/command.json','order':OLD/'full_order/build_command.json'}
VERILATOR=os.environ.get('GS_VERILATOR',str(Path.home()/'eda/opt/oss-cad-suite-20260706/oss-cad-suite/bin/verilator'))

def build(kind):
    initialize();folder=BASE/'build'/kind;folder.mkdir(parents=True,exist_ok=True)
    legacy=read(BUILD_COMMANDS[kind]);tokens=shlex.split(legacy[-1]);tokens=tokens[tokens.index('verilator'):]
    cmd=[VERILATOR];i=1;builddir=WORK/'build'/kind;builddir.mkdir(parents=True,exist_ok=True);exe=builddir/'simulation'
    while i<len(tokens):
        token=tokens[i]
        if token=='-CFLAGS' and tokens[i+1]=='-D_GLIBCXX_USE_CXX11_ABI=0':i+=2;continue
        if token in ('--Mdir','-o','-j'):
            cmd.extend([token,{'--Mdir':str(builddir),'-o':'simulation','-j':'2'}[token]]);i+=2;continue
        cmd.append(token);i+=1
    bench=cmd[cmd.index('--top-module')+1]
    sources=dict(frozen());sources[f'verification/rtl/{bench}.sv']=sha(ROOT/f'verification/rtl/{bench}.sv')
    if kind!='order':effective=assert_command_profile(cmd,bench)
    else:effective={'AUTO_QSU_PRECOUNT_CHILDREN':1,'max_count':7000000}
    marker=folder/'binary.json'
    if marker.exists():
        info=read(marker)
        assert info['source_sha256']==sources and info['command']==cmd and sha(exe)==info['binary_sha256']
        return exe,info
    run_logged(cmd,folder/'build.log')
    assert exe.read_bytes()[:4]==b'\x7fELF','Linux binary required'
    assert sources=={f:sha(ROOT/f) if len(h)==64 and h.upper()==h else sha(ROOT/f).lower() for f,h in sources.items()}
    info=dict(path=str(exe),binary_sha256=sha(exe),command=cmd,source_sha256=sources,
      legacy_command_sha256=sha(BUILD_COMMANDS[kind]),effective_parameters=effective,
      normalization='Linux native tool, separate build/output paths, omit Windows-specific libstdc++ ABI flag; RTL/testbench defines unchanged')
    save(marker,info);print('BUILT',kind,flush=True);return exe,info

def convert_path(s):return s.replace('\\','/').replace('D:/3DGS','/mnt/d/3DGS')
def blocks(text):return {line.split()[0]:{k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)} for line in text.splitlines() if line.startswith('REAL_')}
def validate_input(folder):
    m=read(folder/'manifest.json')
    for f,h in m['input_sha256'].items():assert sha(folder/f)==h.upper(),(folder,f)
    return m
def run_case(kind,n,mode=0,axi='ideal'):
    exe,info=build(kind)
    if kind=='subset':old=OLD/'subset'/n/f'H_m{mode}_{axi}';inputs=old.parent;dest=BASE/'real'/kind/n/f'm{mode}_{axi}'
    elif kind=='full':old=FULL/n/'H';inputs=old.parent;dest=BASE/'real'/kind/n
    elif kind=='repeat':old=OLD/'repeat'/n;inputs=ROOT/'experiments/t06_precount_mem_20261022/real/subset'/n;dest=BASE/'real'/kind/n
    else:old=OLD/'full_order'/n;inputs=old;dest=BASE/'real'/kind/n
    dest.mkdir(parents=True,exist_ok=True)
    if (dest/'result.json').exists():
        row=read(dest/'result.json');assert row['binary_sha256']==info['binary_sha256']
        for f,h in row['evidence_sha256'].items():assert sha(dest/f)==h
        return row
    m=read(inputs/'manifest.json') if kind=='order' else validate_input(inputs)
    if kind=='order':
        for f,h in m['vectors_sha256'].items():assert sha(inputs/f)==h.upper()
    original=read(old/'command.json');args=[x for x in original if x.startswith('+')]
    cmd=[str(exe)];outflags={'FRAME':'state.memh','RGB':'rgb.memh','SORTED_TRACE':'sorted.txt'}
    for x in args:
        key=x[1:].split('=',1)[0]
        cmd.append('+'+key+'='+str(dest/outflags[key]) if key in outflags else convert_path(x))
    execution=run_logged(cmd,dest/'run.log')
    log=(dest/'run.log').read_text();assert 'PASS' in log and 'FATAL' not in log
    counters=blocks(log);oldcounters=blocks((old/'run.log').read_text())
    row=dict(status='PASS',kind=kind,scene=n,camera_index=SCENES[n],mode=mode,axi_profile=axi,
      full_scene=kind in ('full','order'),gaussians=m['gaussians'],source_sha256=info['source_sha256'],
      binary_sha256=info['binary_sha256'],input_manifest_sha256=sha(inputs/'manifest.json'),execution=execution,
      reference_directory=str(old),reference_result_sha256=sha(old/'result.json') if (old/'result.json').exists() else None)
    if kind=='order':
        line=next(line for line in log.splitlines() if line.startswith('PASS T06'))
        metrics={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)}
        assert metrics['n']==m['gaussians']
        row['metrics']=metrics
    else:
        assert 'error=00000000' in log and 'disjoint=1' in log
        raw=bytes(int(v,16) for v in (dest/'rgb.memh').read_text().split())
        oracle=inputs/'oracle/frame.rgb'
        assert raw==oracle.read_bytes(),('oracle RGB mismatch',kind,n)
        if (old/'frame.rgb').exists():assert raw==(old/'frame.rgb').read_bytes()
        repeat=2 if kind=='repeat' else 1
        assert (dest/'sorted.txt').read_bytes()==repeat*(inputs/'expected_sorted.txt').read_bytes()
        w,h=m['width'],m['height'];stride=(w*3+15)&~15;expected=bytearray(stride*h)
        states=(dest/'state.memh').read_text().split();assert len(states)==w*h
        for i,s in enumerate(states):
            v=int(s,16)
            if (v>>55)&65535!=repeat:continue
            y,x=divmod(i,w)
            for c in range(3):expected[y*stride+3*x+c]=min(255,(((v>>(13*c))&8191)*255+2048)//4096)
        assert raw==expected,'state to RGB mismatch'
        (dest/'frame.rgb').write_bytes(raw);Image.fromarray(decode_rgb888(raw,w,h)).save(dest/'frame.png')
        assert Image.open(dest/'frame.png').tobytes()==raw
        assert counters['REAL_END_TO_END']['command_cycles']==oldcounters['REAL_END_TO_END']['command_cycles'],('cycles differ',kind,n)
        assert counters==oldcounters,('counter drift',kind,n,{k:(v,oldcounters.get(k)) for k,v in counters.items() if v!=oldcounters.get(k)})
        if kind=='repeat':
            auto=counters['REAL_AUTO'];assert auto['observe_mode']==3 and auto['selected_mode']==0 and auto['image_mismatches']==0
            assert 'epoch=2 error=00000000' in log
        else:
            assert all(counters['REAL_SHARED_PE'][k]>0 for k in ['G','P','R'])
            assert counters['REAL_ALPHA_SKIP']['enabled']==1 and counters['REAL_RGB_BURST']['configured']==16
        row.update(width=w,height=h,frames=repeat,counters=counters,command_cycles=counters['REAL_END_TO_END']['command_cycles'],rgb_sha256=sha(dest/'frame.rgb'),input_sha256=m['input_sha256'])
        if kind=='full':
            floatdir=ROOT/('experiments/t06_full_f_20261019/float_refs' if n in ('train','truck') else 'experiments/t06_20261018/float_full')
            reference=floatdir/n/'float_floor_0.30078125_jac_clamp.png'
            a=np.asarray(Image.open(dest/'frame.png'),dtype=float);b=np.asarray(Image.open(reference),dtype=float)
            assert a.shape==b.shape;mae=float(np.abs(a-b).mean());assert mae<=5
            row.update(independent_float_mae=mae,float_reference_sha256=sha(reference))
    for f,h in info['source_sha256'].items():assert sha(ROOT/f)==h.upper()
    row['evidence_sha256']={p.name:sha(p) for p in dest.iterdir() if p.is_file() and p.name!='result.json'}
    save(dest/'result.json',row);print('PASS',kind,n,mode,axi,flush=True);return row

def main():
    p=argparse.ArgumentParser();p.add_argument('kind',choices=['subset','full','repeat','order']);p.add_argument('--jobs',type=int,default=2);p.add_argument('--build-only',action='store_true');a=p.parse_args()
    initialize();dest=BASE/'real'/a.kind;dest.mkdir(parents=True,exist_ok=True)
    save(dest/'status.json',dict(status='BUILDING',pid=os.getpid(),signed_off=False))
    build(a.kind)
    if a.build_only:return
    cases=[(a.kind,n,m,ax) for n in SCENES for m in range(4) for ax in ['ideal','limited']] if a.kind=='subset' else [(a.kind,n,0,'ideal') for n in SCENES]
    save(dest/'status.json',dict(status='RUNNING',pid=os.getpid(),cases=len(cases),signed_off=False))
    with ThreadPoolExecutor(max_workers=a.jobs) as pool:rows=list(pool.map(lambda x:run_case(*x),cases))
    save(dest/'report.json',dict(status='PASS',kind=a.kind,source_sha256=frozen(),profile_sha256=sha(PROFILE),results=rows))
    save(dest/'status.json',dict(status='PASS',cases=len(rows),signed_off=False))
if __name__=='__main__':
    try:main()
    except BaseException as e:
        traceback.print_exc();raise
