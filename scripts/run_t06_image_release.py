"""Corrected image semantics release: fresh encoded data, 128-wide real DMA.

All image outputs from this runner are actual RTL DMA bytes; the separate
float diagnosis is labeled as software and never substituted for RTL output.
"""
import argparse,json,os,shutil,sys,time,traceback
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t06_real as common
from scripts import run_t06_full_render as production
from scripts import run_t06_oracle_render as oracle
from scripts import prepare_t06_full_render as encoder
from scripts.build_full_frame_rtl_batch import load_selected_gaussians
from scripts.build_full_frame_batch_index import pack_mean_records,rtl_depth_q16
from model.io.scene import GaussianBatch
from model.io.scene import open_ply_vertices
BASE=ROOT/'experiments/t06_20261017';FULL=BASE/'full_render';SUB=BASE/'subset'
NAMES=common.SCENES
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def save(p,data):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
def prepare_subset():
    for name in NAMES:
        dest=SUB/name;dest.mkdir(parents=True,exist_ok=True)
        origin=read(ROOT/'experiments/t04_20261005/real_rgb'/name/'manifest.json');gids=np.asarray(origin['original_gaussian_indices'][:512],dtype=np.uint32)
        attrs=load_selected_gaussians(ROOT/'data'/name/'point_cloud/iteration_30000/point_cloud.ply',gids)
        batch=GaussianBatch(0,512,attrs['mean'],attrs['scale'],attrs['quaternion'],attrs['opacity'],attrs['sh'])
        aw=encoder.attribute_words(batch);mw=pack_mean_records(np.arange(512,dtype=np.uint32),batch.mean)
        cam=[int(v,16) for v in (FULL/name/'camera.memh').read_text().split()];cam[27]=(0x47534301<<32)|512
        (dest/'camera.memh').write_text(''.join(f'{v:016x}\n' for v in cam))
        (dest/'mean.memh').write_text(''.join(f'{int(hi):016x}{int(lo):016x}\n' for lo,hi in mw))
        (dest/'attribute.memh').write_text(''.join(f'{int(row[k+1]):016x}{int(row[k]):016x}\n' for row in aw for k in range(0,18,2)))
        fixed=origin['camera_fixed'];depth,overflow=rtl_depth_q16(batch.mean,np.array(fixed['rotation_q20'][6:9]),fixed['translation_q16'][2]);assert not np.any(overflow)
        visible=(depth>=fixed['near_far_q16'][0])&(depth<=fixed['near_far_q16'][1]);ids=np.flatnonzero(visible);order=ids[np.argsort(depth[ids],kind='stable')]
        assert len(ids)==512 and np.any(depth[1:]<depth[:-1]),'must be real unsorted input'
        (dest/'expected_sorted.txt').write_text(''.join(f'{int(depth[i])} {int(i)} {int(i)}\n' for i in order))
        save(dest/'manifest.json',{'scene':name,'camera_index':origin['camera_index'],'gaussians':512,'visible':512,'full_scene':False,
            'width':cam[25],'height':cam[26],'original_gaussian_indices':gids.tolist(),'encoding':'official channel-major PLY SH; fixed-point wire format unchanged',
            'software_preprocessing':'select fixed real subset in original PLY order, encode only; no pivots/depth-sort/batches for production',
            'input_sha256':{p.name:common.sha(p) for p in dest.glob('*.memh')},'oracle_sha256':common.sha(dest/'expected_sorted.txt')})
        print('PREPARED SUBSET',name,flush=True)
def build():
    common.OUT=FULL;common.build('verilator',1,6000000,16384)
    oracle.OUT=FULL;oracle.build()
    for which in ['build','oracle_build']:
        (SUB/which).mkdir(parents=True,exist_ok=True)
        for p in (FULL/which).glob('*.json'):shutil.copy2(p,SUB/which/p.name)
    print('BUILDS READY',flush=True)
def verify_encoding():
    rows=[]
    for root in [FULL,SUB]:
        for name in NAMES:
            folder=root/name;m=read(folder/'manifest.json');header,v=open_ply_vertices(ROOT/'data'/name/'point_cloud/iteration_30000/point_cloud.ply')
            n=m['gaussians'];samples=sorted(set([0,n-1]+np.random.default_rng(1706).integers(0,n,14).tolist()))
            with (folder/'attribute.memh').open('rb') as f:
                line_bytes=len(f.readline());assert (folder/'attribute.memh').stat().st_size==n*9*line_bytes
                for local in samples:
                    gid=m['original_gaussian_indices'][local] if not m['full_scene'] else local
                    f.seek(local*9*line_bytes);word=sum(int(f.readline(),16)<<(128*k) for k in range(9))
                    assert word>>1118==0
                    for channel in range(3):
                        for basis in range(16):
                            field=f'f_dc_{channel}' if basis==0 else f'f_rest_{channel*15+basis-1}'
                            code=int(np.clip(np.rint(float(v[field][gid])*4096),-(1<<17),(1<<17)-1))&((1<<18)-1)
                            assert ((word>>(18*(channel*16+basis)))&((1<<18)-1))==code,(name,local,field)
            for f,h in m['input_sha256'].items():assert common.sha(folder/f)==h,'changed input '+str(folder/f)
            if m['full_scene']:assert n==header.vertex_count
            rows.append({'dataset':root.name,'scene':name,'records_checked':len(samples),'SH_fields_checked':48*len(samples),'full_scene':m['full_scene'],'gaussians':n,'status':'PASS'})
    save(BASE/'input_encoding_report.json',{'status':'PASS','results':rows,'rule':'literal official channel-major f_rest field indexing; independent of shared loader reshape'})
    print('INPUT ENCODING PASS',flush=True)
def subset():
    production.OUT=SUB;oracle.OUT=SUB
    for name in NAMES:
        p=SUB/name/'oracle/result.json'
        if not p.exists():oracle.run(name)
        else:assert read(p)['status']=='PASS_ORACLE'
    cases=[(n,m,p) for n in NAMES for m in range(4) for p in ['ideal','limited']]
    def run(case):
        n,m,p=case;folder=SUB/n/f'm{m}_{p}';result=folder/'result.json'
        if result.exists():assert read(result)['source_sha256']==common.sources(),'stale subset output'
        else:production.run(n,mode=m,profile=p,run_folder=f'm{m}_{p}')
        assert (folder/'frame.rgb').read_bytes()==(SUB/n/'oracle/frame.rgb').read_bytes(),'subset/reference RGB mismatch'
        row=read(result);row['independent_sort_rgb_matches']=True;return row
    with ThreadPoolExecutor(max_workers=4) as pool:rows=list(pool.map(run,cases))
    # An alias for the separate float renderer; copied real RTL bytes only.
    for n in NAMES:
        dest=SUB/n/'production_v2';dest.mkdir(exist_ok=True)
        for f in ['frame.png','frame.rgb']:shutil.copy2(SUB/n/'m0_ideal'/f,dest/f)
    save(SUB/'report.json',{'status':'PASS','results':rows,'scope':'corrected SH and FOV; five real 512-record subsets, four modes, two AXI profiles, 128-pixel width'})
def full(workers):
    production.OUT=FULL;oracle.OUT=FULL
    cases=[(kind,n) for n in NAMES for kind in ['production','oracle']]
    def run(case):
        kind,n=case;folder=FULL/n/('production_v2' if kind=='production' else 'oracle');p=folder/'result.json'
        if p.exists():
            r=read(p);expected=common.sources() if kind=='production' else oracle.source_hashes();assert r['source_sha256']==expected,'stale full-model result'
            return
        if kind=='production':production.run(n)
        else:oracle.run(n)
    with ThreadPoolExecutor(max_workers=workers) as pool:list(pool.map(run,cases))
    rows=[]
    for n in NAMES:
        p=FULL/n;assert (p/'production_v2/frame.rgb').read_bytes()==(p/'oracle/frame.rgb').read_bytes(),'full image mismatch '+n
        row=read(p/'production_v2/result.json');row['independent_sort_rgb_matches']=True;rows.append(row)
    save(FULL/'report.json',{'status':'PASS','results':rows,'scope':'complete original-order models; 128-pixel width; G/ideal; current corrected renderer'})
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['prepare-subset','build','subset','full','verify-encoding']);p.add_argument('--workers',type=int,default=4);a=p.parse_args()
    if a.action=='prepare-subset':prepare_subset()
    elif a.action=='build':build()
    elif a.action=='subset':subset()
    elif a.action=='full':full(a.workers)
    elif a.action=='verify-encoding':verify_encoding()
