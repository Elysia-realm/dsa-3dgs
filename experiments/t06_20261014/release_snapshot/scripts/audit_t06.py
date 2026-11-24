"""Join actual T06 evidence; missing full frames always keep signoff pending."""
import argparse,hashlib,json,re,shutil,statistics,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from PIL import Image
BASE=ROOT/'experiments/t06_20261014'
SCENES=['bonsai','counter','room','kitchen','garden']
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for block in iter(lambda:f.read(1<<20),b''):h.update(block)
    return h.hexdigest()
def verify_sources(hashes,root=ROOT):
    for f,h in hashes.items():assert sha(root/f)==h,'source mismatch '+str(root/f)
def main(finalize=False):
    reports={k:read(BASE/p) for k,p in {'units':'units_v2/report.json','protocol':'protocol_v2/report.json',
        'subset':'release_subset/latest_run.json','synthesis':'synthesis_v2/report.json'}.items()}
    assert all(r['status']=='PASS' for r in reports.values())
    assert len(reports['units']['results'])==16 and len(reports['protocol']['results'])==15
    assert len(reports['subset']['results'])==40
    sources={}
    for key in ['units','protocol','synthesis']:
        verify_sources(reports[key]['source_sha256']);sources.update(reports[key]['source_sha256'])
    for r in reports['subset']['results']:verify_sources(r['source_sha256']);sources.update(r['source_sha256'])
    full_order=[];frames=[];missing=[]
    for name in SCENES:
        folder=BASE/'full_order'/name;result=read(folder/'result_v2.json');verify_sources(result['source_sha256'])
        sources.update(result['source_sha256']);assert result['status']=='PASS'
        m=read(folder/'manifest.json');assert sha(folder/'input.memh')==m['input_sha256'];assert sha(folder/'expected.memh')==m['expected_sha256']
        metrics={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',(folder/'run_v2.log').read_text().splitlines()[0])}
        full_order.append({'scene':name,'gaussians':result['gaussians'],'status':'PASS','metrics':metrics})
        folder=BASE/'full_render'/name;m=read(folder/'manifest.json');prod=folder/'production_v2';oracle=folder/'oracle'
        row={'scene':name,'camera_index':m['camera_index'],'gaussians':m['gaussians'],'depth_visible':m['visible'],
             'full_scene':True,'width':m['width'],'height':m['height'],'mode':'G','axi_profile':'ideal',
             'cpu_ordering':False,'cpu_preprocessing':m['software_preprocessing'],'status':'PENDING'}
        for p in [prod,oracle]:
            if not (p/'result.json').exists():missing.append(str((p/'result.json').relative_to(BASE)))
        if (prod/'result.json').exists():
            p=read(prod/'result.json');verify_sources(p['source_sha256']);sources.update(p['source_sha256'])
            assert p['status'] in ['PASS_DATAPATH_PENDING_IMAGE_ORACLE','PASS']
            assert (prod/'sorted.txt').read_bytes()==(folder/'expected_sorted.txt').read_bytes()
            for file,h in m['input_sha256'].items():assert sha(folder/file)==h,str(folder/file)
            raw=(prod/'frame.rgb').read_bytes();assert sha(prod/'frame.rgb')==p['rgb_sha256']
            assert raw==bytes(int(x,16) for x in (prod/'rgb.memh').read_text().split())
            assert raw==Image.open(prod/'frame.png').tobytes()
            row.update(status='PASS_DATAPATH_PENDING_ORACLE',cycles=p['cycles'],qsu=p['qsu'],rgb_sha256=p['rgb_sha256'],
                       scratch_bytes=16*(p['qsu']['reads']+p['qsu']['writes']),
                       sorted_stream_sha256=m['oracle_sha256'],input_sha256=m['input_sha256'],source_ply_sha256=m['source_ply_sha256'])
            assert p['qsu']['input']==m['visible'] and p['qsu']['reads']==p['qsu']['axi_reads'] and p['qsu']['writes']==p['qsu']['axi_writes']
            log=(prod/'run.log').read_text()
            work={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',next(line for line in log.splitlines() if line.startswith('REAL_SORT_WORK')))}
            shared={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',next(line for line in log.splitlines() if line.startswith('REAL_SHARED_PE')))}
            leaves=p['qsu']['leaves']
            assert work['caps']==0x00100019 and work['shared']==leaves and work['groups']==leaves
            assert work['local']==79*leaves and work['phases']==10*leaves
            assert work['phase_grants']>0 and work['fallback']>0 and min(shared[k] for k in ['G','P','R'])>0
            row['bsu_work']=work;row['shared_PE']=shared
            if (oracle/'result.json').exists():
                o=read(oracle/'result.json');assert o['status']=='PASS_ORACLE' and not o['autonomous']
                verify_sources(o['source_sha256'],BASE/'pre_leaf_buffer_snapshot')
                assert raw==(oracle/'frame.rgb').read_bytes(),'full RGB oracle mismatch '+name
                assert sha(oracle/'frame.rgb')==o['rgb_sha256']
                row['status']='PASS';row['independent_rgb_oracle_matches']=True
        frames.append(row)
    logs=BASE/'logs';logs.mkdir(exist_ok=True)
    for src,dst in [('tmp/t06_release_regression.log','iverilog_release.log'),('tmp/t06_release_lint.log','verilator_release.log'),
                    ('tmp/t06_abort_before_fix.log','half_leaf_failure_before_fix.log'),('tmp/t06_abort_after_fix.log','half_leaf_fixed.log'),
                    ('tmp/t06_full_order_v2_run.log','full_order_release.log'),('tmp/t06_protocol_v2_final.log','protocol_release.log')]:
        shutil.copy2(ROOT/src,logs/dst)
    assert (logs/'iverilog_release.log').read_text(errors='replace').count('PASS: tb_')==80
    assert 'PASS: Verilator lint completed' in (logs/'verilator_release.log').read_text(errors='replace')
    if finalize:
        assert not missing and all(x['status']=='PASS' for x in frames),missing
        testlog=(logs/'python_final.log').read_text(errors='replace');assert re.search(r'\nOK\s*$',testlog),testlog[-1500:]
        visual=read(BASE/'visual_review.json');assert set(visual['reviewed_scenes'])==set(SCENES) and visual['current_rgb_hashes']=={r['scene']:r['rgb_sha256'] for r in frames}
    # Preserve complete build context, including previously unchanged includes.
    for f in ['verification/rtl/system_top_sources.f','verification/run_t06.ps1','verification/test_t06_evidence.py',
              'docs/T06自主QSU与BSU统一验收计划_2026-10-14.md','docs/T06自主分组与片外暂存接口_v1.md',
              'docs/开发日志_2026-10-15_T06自主分组断点与验收进展.md',
              'scripts/build_full_frame_batch_index.py','model/io/scene.py','model/io/dma_workload.py']:
        sources[f]=sha(ROOT/f)
    for p in list((ROOT/'scripts').glob('*t06*.py'))+list((ROOT/'rtl').rglob('*.svh')):
        sources[p.relative_to(ROOT).as_posix()]=sha(p)
    for f in sources:
        dest=BASE/'release_snapshot'/f;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/f,dest)
    subset_cycles={}
    for profile in ['ideal','limited']:
        old=read(ROOT/'experiments/t05_parallel_20261011/release/report.json')['results']
        diffs=[]
        for r in reports['subset']['results']:
            if r['profile']!=profile:continue
            before=next(x['cycles'] for x in old if x['scene']==r['scene'] and x['mode']==r['mode'] and x['profile']==profile)
            diffs.append(100*(before-r['cycles'])/before)
        subset_cycles[profile]={'runs':len(diffs),'mean_saved_percent':statistics.mean(diffs),'min_saved_percent':min(diffs),'max_saved_percent':max(diffs)}
    result={'task':'T06','status':'COMPLETE_FUNCTIONAL' if finalize else 'VERIFYING_FULL_MODELS','signed_off':bool(finalize),
        'date':'2026-10-16','production_top':'gs_accel_system_top','configuration':{'K':16,'pipeline':True,'sequence_bits':32,'pivots':7,'buckets':8,'atomic_leaf_banks':2,'runtime_qsu_enable':True,'shared_GPR':True,'RGB_DMA':True},
        'unit_cases':16,'protocol_cases':15,'rtl_regressions':80,'current_real_subset_runs':40,
        'full_order_scenes':full_order,'full_model_frames':frames,
        'full_model_autonomous_frames':sum(x['status'].startswith('PASS') for x in frames),
        'full_model_rgb_oracle_matches':sum(x['status']=='PASS' for x in frames),'pending_evidence':missing,
        'subset_vs_cpu_preordered_T05_cycles':subset_cycles,
        'comparison_warning':'T05 excludes host global sorting/batch/pivot time; current QSU includes scratch traffic. Not same software/hardware work split or a universal acceleration claim.',
        'resolved_failures':['Half-leaf R error stranded BSU: reproduced, fixed with atomic dual leaf banks, regression and production recovery passed'],
        'interrupted_runs':['Pre-fix Counter/Room/Kitchen/Garden production runs intentionally stopped after defect discovery; never counted PASS',
                            '2026-10-16 Garden production and Room/Kitchen/Garden reference simulations resumed after process interruption; partial traces not accepted'],
        'limits':['Full scenes are 16-pixel-wide functional renders, not target resolution/GT quality',
                  '40 four-mode/two-AXI runs use 512-record real subsets; full scenes use G/ideal only',
                  'No 30FPS, mapped chip area, clock, SRAM/LPDDR4, activity-power or T10/T12 signoff',
                  'Runtime QSU enable must be set; reset defaults preserve legacy command compatibility',
                  'Independent reference uses CPU global sort and frozen legacy grouping; not autonomous evidence'],
        'source_sha256':sources}
    (BASE/'full_render/report.json').write_text(json.dumps({'status':'PASS' if not missing and all(x['status']=='PASS' for x in frames) else 'PARTIAL','results':frames},ensure_ascii=False,indent=2),encoding='utf-8')
    if finalize:
        evidence=set()
        for pattern in ['units_v2/**/*.json','units_v2/**/*.log','protocol_v2/**/*.json','protocol_v2/**/*.log',
                        'release_subset/**/*.json','release_subset/**/*.log','release_subset/**/frame.rgb','release_subset/**/frame.png',
                        'release_subset/**/rgb.memh','release_subset/**/state.memh','release_subset/**/sorted.txt',
                        'full_order/*/*_v2.json','full_order/*/run_v2.log','full_render/report.json',
                        'full_render/*/manifest.json','full_render/*/production_v2/*','full_render/*/oracle/*',
                        'synthesis_v2/*','logs/*','visual_review.json']:
            evidence.update(p for p in BASE.glob(pattern) if p.is_file())
        result['artifact_sha256']={p.relative_to(BASE).as_posix():sha(p) for p in sorted(evidence)}
    (BASE/'audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'status':result['status'],'full_datapath':result['full_model_autonomous_frames'],'full_rgb_oracle_matches':result['full_model_rgb_oracle_matches'],'pending':missing,'subset_comparison':subset_cycles},indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--finalize',action='store_true');main(p.parse_args().finalize)
