"""Current T06 image-corrected acceptance, with explicit incomplete states."""
import argparse,hashlib,json,re,shutil,sys
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
BASE=ROOT/'experiments/t06_20261017';OLD=ROOT/'experiments/t06_20261014';NAMES=['bonsai','counter','room','kitchen','garden']
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for data in iter(lambda:f.read(1<<20),b''):h.update(data)
    return h.hexdigest()
def verify(mapping):
    for p,h in mapping.items():assert sha(ROOT/p)==h,'stale source '+p
def main(finalize=False):
    sources={};reports={}
    for key,path in [('units','unit_checks/report.json'),('protocol','protocol/report.json'),('encoding','input_encoding_report.json'),('subset','subset/report.json')]:
        r=read(BASE/path);assert r['status']=='PASS';reports[key]=r
        if 'source_sha256' in r:verify(r['source_sha256']);sources.update(r['source_sha256'])
    assert len(reports['protocol']['results'])==15 and len(reports['subset']['results'])==40
    for r in reports['subset']['results']:verify(r['source_sha256']);sources.update(r['source_sha256'])
    rows=[];pending=[];float_subset=[]
    for n in NAMES:
        # QSU/BSU-only full-model evidence is reused only with exact module/TB hashes.
        q=read(OLD/'full_order'/n/'result_v2.json');verify(q['source_sha256']);sources.update(q['source_sha256']);assert q['status']=='PASS'
        f=read(BASE/'float_subset'/n/'float_floor_0.30078125_jac_clamp.json')
        assert f['rtl_mae_rgb8']<=2 and f['rtl_active_mae_rgb8']<=5;float_subset.append({'scene':n,'mae':f['rtl_mae_rgb8'],'active_mae':f['rtl_active_mae_rgb8']})
        folder=BASE/'full_render'/n;m=read(folder/'manifest.json');prod=folder/'production_v2';oracle=folder/'oracle'
        row={'scene':n,'camera_index':m['camera_index'],'gaussians':m['gaussians'],'depth_visible':m['visible'],'width':m['width'],'height':m['height'],
             'full_scene':True,'mode':'G','AXI':'ideal','cpu_global_ordering':False,'status':'PENDING'}
        assert m['width']==128
        for d in [prod,oracle]:
            if not (d/'result.json').exists():pending.append(str((d/'result.json').relative_to(BASE)))
        if (prod/'result.json').exists():
            p=read(prod/'result.json');verify(p['source_sha256']);sources.update(p['source_sha256'])
            raw=(prod/'frame.rgb').read_bytes();assert sha(prod/'frame.rgb')==p['rgb_sha256']
            assert raw==bytes(int(x,16) for x in (prod/'rgb.memh').read_text().split())==Image.open(prod/'frame.png').tobytes()
            assert (prod/'sorted.txt').read_bytes()==(folder/'expected_sorted.txt').read_bytes()
            row.update(status='PASS_DATAPATH_PENDING_REFERENCES',cycles=p['cycles'],qsu=p['qsu'],rgb_sha256=p['rgb_sha256'])
            log=(prod/'run.log').read_text();assert 'error=00000000' in log
            bsu={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',next(x for x in log.splitlines() if x.startswith('REAL_SORT_WORK')))}
            count=p['qsu']['leaves'];assert (bsu['caps'],bsu['shared'],bsu['local'],bsu['phases'],bsu['groups'])==(0x100019,count,79*count,10*count,count)
            assert bsu['phase_grants']>0 and bsu['fallback']>0;row['bsu_work']=bsu
            float_image=BASE/'float_full'/n/'float_floor_0.30078125_jac_clamp.png'
            if not float_image.exists():pending.append(str(float_image.relative_to(BASE)))
            if (oracle/'result.json').exists() and float_image.exists():
                o=read(oracle/'result.json');verify(o['source_sha256']);sources.update(o['source_sha256']);assert o['status']=='PASS_ORACLE'
                assert raw==(oracle/'frame.rgb').read_bytes(),'independent sort RGB mismatch '+n
                a=np.asarray(Image.open(prod/'frame.png'),dtype=float);b=np.asarray(Image.open(float_image),dtype=float)
                assert a.shape==b.shape;mae=float(np.mean(np.abs(a-b)));assert mae<=5,('full float semantic mismatch',n,mae)
                row.update(status='PASS',independent_sort_rgb_matches=True,independent_float_rgb8_mae=mae)
        rows.append(row)
    if (BASE/'float_full/report.json').exists():
        f=read(BASE/'float_full/report.json');assert f['status']=='REFERENCE_READY';verify(f['source_sha256']);sources.update(f['source_sha256'])
    else:pending.append('float_full/report.json')
    logs=BASE/'logs';logs.mkdir(exist_ok=True)
    for f in ['t06_image_fix_regression.log','t06_image_fix_lint.log','t06_image_units.log','t06_image_release_protocol.log']:
        shutil.copy2(ROOT/'tmp'/f,logs/f)
    assert (logs/'t06_image_fix_regression.log').read_text(errors='replace').count('PASS: tb_')==80
    assert 'PASS: Verilator lint completed' in (logs/'t06_image_fix_lint.log').read_text(errors='replace')
    for folder in ['full_render','subset']:
        for n in NAMES:
            p=BASE/folder/n;m=read(p/'manifest.json')
            for f,h in m['input_sha256'].items():assert sha(p/f)==h,str(p/f)
    if finalize:
        assert not pending and all(r['status']=='PASS' for r in rows),pending
        visual=read(BASE/'visual_review.json');assert set(visual['reviewed_scenes'])==set(NAMES)
        assert visual['current_rgb_hashes']=={r['scene']:r['rgb_sha256'] for r in rows}
        assert re.search(r'\nOK\s*$',(logs/'python_final.log').read_text(errors='replace'))
    for p in list((ROOT/'scripts').glob('*t06*.py'))+list((ROOT/'rtl').rglob('*.svh'))+[
        ROOT/'verification/run_t06.ps1',ROOT/'verification/test_t06_image_release.py',ROOT/'verification/rtl/system_top_sources.f',
        ROOT/'docs/开发日志_2026-10-17_T06图像根因与重验收.md',ROOT/'docs/T06自主分组与片外暂存接口_v1.md',
        ROOT/'docs/T06自主QSU与BSU统一验收计划_2026-10-14.md']:
        sources[p.relative_to(ROOT).as_posix()]=sha(p)
    for p in sources:
        dest=BASE/'release_snapshot'/p;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/p,dest)
    report={'task':'T06','date':'2026-10-17','status':'COMPLETE_FUNCTIONAL' if finalize else 'VERIFYING_CORRECTED_IMAGES','signed_off':bool(finalize),
        'corrected_defects':['missing covariance FOV Jacobian clamp','incorrect PLY SH channel/basis ordering'],
        'historical_shared_bug_evidence':'experiments/t06_20261014; old five-way RGB matches do not prove image semantics',
        'configuration':{'K':16,'spatial_BSU':True,'QSU_pivots':7,'sequence_bits':32,'atomic_leaf_banks':2,'RGB_DMA':True,'width':128},
        'current_subset_runs':40,'protocol_cases':15,'clamp_unit_transactions':8,'format_and_projection_python_tests':8,'rtl_regressions':80,
        'reused_full_order_scenes':5,'reused_full_order_records':11748270,'float_subset_metrics':float_subset,
        'full_model_frames':rows,'full_model_autonomous_frames':sum(r['status'].startswith('PASS') for r in rows),
        'full_model_rgb_oracle_matches':sum(r['status']=='PASS' for r in rows),'pending_evidence':pending,'source_sha256':sources,
        'limits':['128-wide functional validation, not 1080p/native-resolution GT acceptance',
                  'float reference follows project quantization and clipping; not official GPU/GT quality signoff',
                  'No full-chip mapped PPA/STA/power/30FPS signoff','Runtime QSU enable must be set explicitly; legacy command compatibility retained']}
    if finalize:
        paths=set()
        for pattern in ['**/report.json','**/manifest.json','**/result.json','**/command.json','**/*_command.json','**/*_sources.json','**/run.log','**/frame.rgb','**/frame.png','**/sorted.txt','**/state.memh','**/rgb.memh','logs/*','visual_review.json']:
            paths.update(p for p in BASE.glob(pattern) if p.is_file())
        report['artifact_sha256']={p.relative_to(BASE).as_posix():sha(p) for p in sorted(paths)}
    (BASE/'audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'status':report['status'],'full_datapath':report['full_model_autonomous_frames'],'fully_matched':report['full_model_rgb_oracle_matches'],'pending':pending},indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--finalize',action='store_true');main(p.parse_args().finalize)
