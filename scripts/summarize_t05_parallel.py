"""Finalize T05 v2 only from verified, version-separated evidence."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,statistics
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'experiments/t05_parallel_20261011'
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main(finalize=False):
    reports={key:read(BASE/path) for key,path in {
        'selection':'real/report.json','release':'release/report.json','mapping':'mapping/report.json',
        'units':'units/report.json','throughput':'throughput/report.json',
        'epochs':'release/reconfiguration/report.json','origin':'data_origin.json'}.items()}
    assert all(r['status']=='PASS' for r in reports.values())
    assert len(reports['selection']['results'])==240 and len(reports['release']['results'])==40
    assert len(reports['mapping']['results'])==8 and len(reports['epochs']['results'])==5
    for p,h in reports['selection']['source_sha256'].items():assert sha(BASE/'selection_snapshot'/p)==h,p
    for key in ['release','mapping','epochs']:
        for p,h in reports[key]['source_sha256'].items():assert sha(ROOT/p)==h,p
    for x in reports['mapping']['results']:
        assert not x['unmapped_cells']
        assert sha(BASE/'mapping'/x['name']/x['pdk']/'mapped.v')==x['netlist_sha256']
    rows=reports['selection']['results'];indexed={(r['scene'],r['subset_capacity'],r['variant'],r['mode'],r['profile']):r for r in rows}
    comparisons={}
    for n,v,m,w in [(8,'pipe8',8,'fold8'),(16,'pipe16',16,'fold16'),(16,'pipe16',8,'pipe8'),(8,'pipe16',8,'pipe8')]:
        changes=[100*(indexed[(r['scene'],m,w,r['mode'],r['profile'])]['cycles']-r['cycles'])/
                 indexed[(r['scene'],m,w,r['mode'],r['profile'])]['cycles'] for r in rows if r['subset_capacity']==n and r['variant']==v]
        comparisons[f'{v}_n{n}_vs_{w}_n{m}']={'runs':len(changes),'mean_saved_percent':statistics.mean(changes),
            'min_saved_percent':min(changes),'max_saved_percent':max(changes),'faster':sum(x>0 for x in changes),'slower':sum(x<0 for x in changes)}
    logs=BASE/'logs';logs.mkdir(exist_ok=True)
    for src,dst in [('tmp/t05_parallel_release_regression.log','iverilog_release.log'),
                    ('tmp/t05_parallel_release_lint.log','verilator_release_lint.log'),
                    ('tmp/t05_parallel_units_final.log','unit_summary.log'),
                    ('tmp/t05_parallel_throughput_saturated.log','throughput_summary.log'),
                    ('tmp/t05_parallel_matrix.log','selection_matrix.log'),
                    ('tmp/t05_parallel_release_matrix.log','release_matrix.log'),
                    ('tmp/t05_parallel_release_reconfiguration.log','release_epochs.log')]:shutil.copy2(ROOT/src,logs/dst)
    regression=(logs/'iverilog_release.log').read_text(errors='replace')
    assert regression.count('PASS: tb_')==80 and 'PASS: all configured' in regression
    assert 'PASS: Verilator lint completed' in (logs/'verilator_release_lint.log').read_text(errors='replace')
    python_info=None
    if finalize:
        state=read(ROOT/'verification/implementation_status.json')
        assert state['t05_signed_off'] and state['t05_status']=='COMPLETE'
        output=(logs/'python_final.log').read_text(encoding='utf-8',errors='replace')
        assert 'OK (skipped=1)' in output
        count=int(re.search(r'Ran (\d+) tests',output)[1]);python_info={'total':count,'passed':count-1,'skipped':1,'failed':0,
            'skip_reason':'historical T04 source check; current release and old T05 snapshots are checked separately'}
    files=set(reports['release']['source_sha256'])
    files.update(p.relative_to(ROOT).as_posix() for p in (ROOT/'scripts').glob('*t05_parallel*.py'))
    files.update(['verification/run_t05.ps1','verification/rtl/tb_t05_sorters.sv','verification/rtl/tb_t05_reconfiguration.sv',
                  'verification/rtl/system_top_sources.f','verification/test_t05_parallel_evidence.py',
                  'docs/T05并行性补足验收计划_2026-10-11.md','docs/T05_BSU接口与共享资源规格_v2.md',
                  'docs/开发日志_2026-10-13_T05并行性补足与重新签核.md'])
    files.update(['scripts/run_t05_sorters.py','scripts/map_t05_modules.py','asic/scripts/run_t01_synthesis.py',
                  'scripts/build_full_frame_batch_index.py','scripts/read_rgb888_frame.py','scripts/build_full_frame_rtl_batch.py',
                  'model/io/dma_workload.py','model/io/scene.py'])
    for k in (8,16):
        for name in (f'k{k}_input.memh',f'k{k}_expected.memh'):
            source=ROOT/'experiments/t05_20261009/sorters'/name
            dest=BASE/'oracle_inputs'/name;dest.parent.mkdir(exist_ok=True);shutil.copy2(source,dest)
    for p in files:
        dest=BASE/'release_snapshot'/p;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/p,dest)
    artifact_paths=[]
    for pattern in ['**/report.json','**/manifest.json','**/command.json','**/*_command.json','**/*_sources.json','**/executable_block.json',
                    '**/result.json','**/frame.rgb','**/frame.png','**/rgb.memh','**/state.memh','**/sorted.txt','logs/*.log','oracle_inputs/*.memh']:
        artifact_paths.extend(BASE.glob(pattern))
    artifact_paths += [BASE/'data_origin.json']
    summary={'task':'T05','status':'COMPLETE_FUNCTIONAL' if finalize else 'EVIDENCE_VALIDATED_PENDING_FINAL_STATE',
        'signoff_date':'2026-10-13' if finalize else None,'selected_configuration':{
            'top':'gs_accel_system_top','GROUP_CAPACITY':16,'SORT_CAPACITY':16,'BSU_PIPELINED':1,'USE_BITONIC_SORT':1,
            'USE_SHARED_PROJECTION_PE':1,'USE_SHARED_RASTER_PE':1,'USE_FINAL_RGB_DMA':1,'LANES':4},
        'acceptance_plan':'docs/T05并行性补足验收计划_2026-10-11.md',
        'selection_runs':240,'production_default_runs':40,'scenes':5,'gaussians_per_scene':512,
        'full_scene':False,'cpu_orders_ranges_and_pivots':True,'source_versions':{
            'selection':'selection_snapshot; explicit K8/K16 configurations before default capacity changed',
            'release':'current source; critical production parameters not overridden by testbench'},
        'unit_configurations':4,'unit_output_checks':sum(r['outputs'] for r in reports['units']['results']),
        'throughput_configurations':12,'selected_steady_group_interval':16,
        'selected_vs_folded_4lane_group_throughput_ratio':72/16,
        'selected_group_compute_structure':'10 elastic layers, 80 logical CAS: one shared G CAS and 79 dedicated CAS; two ingress banks',
        'mapping_runs':8,'comparisons':comparisons,'release_epoch_tests':5,'release_epoch_frames':10,
        'regression_tests_passed':80,'synthesis_compile_pass':True,'production_lint_pass':True,'python_checks':python_info,
        'data_origin':'data_origin.json; source PLY SHA and 512 records/scene repacked under current project encoding',
        'limits':['No full-model/GT/1080p quality or full-scene FPS signoff',
                  'No autonomous QSU/pivot/capacity management signoff; T06 remains required',
                  'No full-chip STA/SRAM/activity-power signoff; module area/delay are not chip PPA',
                  'Natural capacity speedup includes fewer command batches, not solely additional CAS parallelism'],
        'known_failures_and_resolutions':['Generated executable signing-policy blocks retained per run; installed Icarus used without changing security policy',
                                        'Initial throughput stimulus contained a group bubble; saturated stimulus rerun gives 8/16 cycle intervals',
                                        'Interrupted metadata marked completion before final audit/log existed; final state withheld until evidence validation and archive completion'],
        'source_sha256':{p:sha(ROOT/p) for p in sorted(files)},
        'artifact_sha256':{p.relative_to(BASE).as_posix():sha(p) for p in sorted(set(artifact_paths))}}
    (BASE/'audit.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print(json.dumps({'status':summary['status'],'source_files':len(files),'artifact_files':len(summary['artifact_sha256']),'comparisons':comparisons},indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--finalize',action='store_true');main(p.parse_args().finalize)
