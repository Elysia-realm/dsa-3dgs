"""Bounded T07 real-data ablation using native ELF builds and RTL RGB DMA."""
import argparse,sys,re,os
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
import numpy as np
from PIL import Image
from scripts.t07_common import BASE,WORK,T01,PROFILE,read,save,sha,run_logged,source_manifest,snapshot
from scripts.run_t01_wsl_real import blocks
from scripts.read_rgb888_frame import decode_rgb888

VARIANTS={'B':(0,0,1),'S':(1,0,1),'P':(0,1,1),'C':(1,1,1),'A':(0,0,0)}
SCENES=read(PROFILE)['scenes']
BENCH='verification/rtl/tb_t07_workload.sv'

def current_sources(kind=None):
    m=source_manifest();m[BENCH]=sha(ROOT/BENCH)
    if kind=='repeat':m['verification/rtl/tb_t07_repeat.sv']=sha(ROOT/'verification/rtl/tb_t07_repeat.sv')
    return m

def build(kind,variant):
    d=BASE/'build'/kind/variant;w=WORK/'build'/kind/variant;w.mkdir(parents=True,exist_ok=True)
    cmd=read(T01/'build'/kind/'binary.json')['command'].copy()
    oldtop=cmd[cmd.index('--top-module')+1]
    newtop='tb_t07_repeat' if kind=='repeat' else 'tb_t07_workload'
    cmd=[x.replace(oldtop,newtop) for x in cmd]
    for key,value in [('--Mdir',str(w)),('-j','2')]:cmd[cmd.index(key)+1]=value
    shape,pixel,alpha=VARIANTS[variant]
    overrides={'TB_ENABLE_SHAPE_BLOCK_REJECT':shape,'TB_ENABLE_ALPHA_ZERO_SKIP':alpha,'TB_PIXEL_TERMINATION_SKIP':pixel}
    cmd=[x for x in cmd if not any(x.startswith('-D'+k+'=') for k in overrides)]
    cmd += ['-D'+k+'='+str(v) for k,v in overrides.items()]
    m=current_sources(kind);marker=d/'binary.json';exe=w/'simulation'
    if marker.exists():
        info=read(marker);assert info['source_sha256']==m and info['command']==cmd and sha(exe)==info['binary_sha256']
        return info
    run_logged(cmd,d/'build.log')
    assert exe.read_bytes()[:4]==b'\x7fELF' and current_sources(kind)==m
    params=read(PROFILE)['parameters'].copy();params.update(ENABLE_SHAPE_BLOCK_REJECT=shape,ENABLE_PIXEL_TERMINATION_SKIP=pixel,ENABLE_ALPHA_ZERO_SKIP=alpha)
    info=dict(path=str(exe),command=cmd,parameters=params,source_sha256=m,binary_sha256=sha(exe))
    save(marker,info);snapshot('source_current_repeat' if kind=='repeat' else 'source_current',m);print('BUILT',kind,variant,flush=True);return info

def state_values(path,epoch):
    values=[]
    for s in path.read_text().split():
        v=int(s,16)
        values.append((v&((1<<39)-1),(v>>39)&65535) if ((v>>55)&65535)==epoch else (0,65535))
    return values

def run_case(kind,variant,n,mode,axi,info):
    old=T01/'real'/kind/n/(f'm{mode}_{axi}' if kind=='subset' else '')
    if kind=='repeat':old=T01/'real/repeat'/n
    ref=read(old/'result.json');m=current_sources(kind);assert info['source_sha256']==m
    d=BASE/'real'/kind/variant/n/(f'm{mode}_{axi}' if kind=='subset' else '');d.mkdir(parents=True,exist_ok=True)
    marker=d/'result.json'
    if marker.exists():
        prior=read(marker);assert prior['binary_sha256']==info['binary_sha256'] and prior['status']=='PASS'
        for f,h in prior['evidence_sha256'].items():assert sha(d/f)==h
        return prior
    cmd=read(old/'run.command.json');cmd[0]=info['path']
    for i,x in enumerate(cmd):
        if x.startswith('+'):
            key=x[1:].split('=',1)[0]
            if key in {'FRAME','RGB','SORTED_TRACE'}:cmd[i]='+'+key+'='+str(d/{'FRAME':'state.memh','RGB':'rgb.memh','SORTED_TRACE':'sorted.txt'}[key])
    source_inputs={x.split('=',1)[0][1:]:Path(x.split('=',1)[1]) for x in cmd if x.startswith(('+ATTR=','+MEAN=','+CAMERA='))}
    input_hashes={k:sha(p) for k,p in source_inputs.items()}
    assert input_hashes=={k:ref['input_sha256'][f].upper() for k,f in [('ATTR','attribute.memh'),('MEAN','mean.memh'),('CAMERA','camera.memh')]}
    save(d/'launch.json',dict(source_sha256=m,binary_sha256=info['binary_sha256'],input_sha256=input_hashes,driver_sha256=sha(Path(__file__)),parameters=info['parameters']))
    execution=run_logged(cmd,d/'run.log')
    log=(d/'run.log').read_text();c=blocks(log)
    assert ('PASS: tb_t07_repeat' if kind=='repeat' else 'PASS: tb_t07_workload') in log and 'error=00000000' in log and 'disjoint=1' in log
    assert c['REAL_T07_TERMINATION']['enabled']==VARIANTS[variant][1]
    raw=bytes(int(v,16) for v in (d/'rgb.memh').read_text().split())
    assert raw==(old/'frame.rgb').read_bytes(),('RGB mismatch',kind,variant,n,mode,axi)
    assert (d/'sorted.txt').read_bytes().replace(b'\r\n',b'\n')==(old/'sorted.txt').read_bytes().replace(b'\r\n',b'\n'),('order mismatch',n)
    epoch=2 if kind=='repeat' else 1
    newstate=state_values(d/'state.memh',epoch);oldstate=state_values(old/'state.memh',epoch)
    assert len(newstate)==len(oldstate)
    tdiff=0
    for i,((rgb,t),(rgb0,t0)) in enumerate(zip(newstate,oldstate)):
        assert rgb==rgb0,('fixed RGB state mismatch',n,i,rgb,rgb0)
        if t!=t0:
            assert VARIANTS[variant][1] and t<=7 and t0<=7,('nonterminal T mismatch',n,i,t,t0)
            tdiff+=1
    w,h=ref['width'],ref['height'];stride=(w*3+15)&~15;expected=bytearray(stride*h)
    for i,(rgb,_) in enumerate(newstate):
        y,x=divmod(i,w)
        for channel in range(3):expected[y*stride+x*3+channel]=min(255,(((rgb>>(13*channel))&8191)*255+2048)//4096)
    assert raw==expected
    (d/'frame.rgb').write_bytes(raw);Image.fromarray(decode_rgb888(raw,w,h)).save(d/'frame.png')
    assert Image.open(d/'frame.png').tobytes()==decode_rgb888(raw,w,h).tobytes()
    if variant=='B':assert c['REAL_END_TO_END']['command_cycles']==ref['command_cycles'],('disabled path changed',n)
    if kind=='repeat':assert c['REAL_AUTO']['image_mismatches']==0 and 'epoch=2' in log
    if kind=='full':
        f=T01/'fresh_float'/n/'float_floor_0.30078125_jac_clamp.png'
        mae=float(np.abs(np.array(Image.open(d/'frame.png'),dtype=float)-np.array(Image.open(f),dtype=float)).mean());assert mae<=5
    else:mae=None
    assert current_sources(kind)==m and all(sha(p)==input_hashes[k] for k,p in source_inputs.items())
    cycles=c['REAL_END_TO_END']['command_cycles'];baseline=ref['command_cycles']
    row=dict(status='PASS',variant=variant,scene=n,mode=mode,axi=axi,camera=SCENES[n],
      gaussians=ref['gaussians'],full_scene=kind=='full',width=w,height=h,parameters=info['parameters'],
      command_cycles=cycles,baseline_cycles=baseline,saved_percent=100*(baseline-cycles)/baseline,
      terminal_T_differences=tdiff,independent_float_mae=mae,counters=c,input_sha256=input_hashes,
      source_sha256=m,binary_sha256=info['binary_sha256'],execution=execution,
      reference_directory=str(old),reference_result_sha256=sha(old/'result.json'))
    row['evidence_sha256']={p.name:sha(p) for p in d.iterdir() if p.is_file() and p.name!='result.json'}
    save(marker,row);print('PASS',kind,variant,n,mode,axi,cycles,f'{row["saved_percent"]:.3f}%',flush=True);return row

def main():
    p=argparse.ArgumentParser();p.add_argument('kind',choices=['subset','full','repeat']);p.add_argument('--variants',nargs='+',choices=list(VARIANTS),default=['C'])
    p.add_argument('--matrix',action='store_true');p.add_argument('--jobs',type=int,default=2);p.add_argument('--scenes',nargs='+',choices=list(SCENES));a=p.parse_args()
    scenes=a.scenes or list(SCENES);rows=[]
    for v in a.variants:
        info=build(a.kind,v)
        cases=[(n,m,ax) for n in scenes for m in (range(4) if a.matrix else [0]) for ax in (['ideal','limited'] if a.matrix else ['ideal'])]
        if a.kind=='repeat':cases=[(n,3,'limited') for n in scenes]
        tag=a.kind+'_'+v+('_matrix' if a.matrix else '')+('_'+'_'.join(scenes) if a.scenes else '')
        save(BASE/(tag+'_status.json'),dict(status='RUNNING',cases=len(cases),pid=os.getpid(),signed_off=False))
        with ThreadPoolExecutor(max_workers=a.jobs) as pool:results=list(pool.map(lambda x:run_case(a.kind,v,*x,info),cases))
        save(BASE/(tag+'_report.json'),dict(status='PASS',source_sha256=current_sources(a.kind),results=results))
        save(BASE/(tag+'_status.json'),dict(status='PASS',cases=len(results),signed_off=False));rows+=results
    print('PASS real cases',len(rows))
if __name__=='__main__':main()
