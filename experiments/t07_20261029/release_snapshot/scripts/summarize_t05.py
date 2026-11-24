"""Archive actual T05 results and tradeoffs without extrapolating chip PPA."""
from pathlib import Path
import hashlib,json,re,statistics,shutil
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'experiments/t05_20261009'
def load(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    real=load(OUT/'real/report.json');mapping=load(OUT/'mapping/report.json')
    modules=load(OUT/'sorters/report.json');reconfig=load(OUT/'reconfiguration/report.json')
    cross=load(OUT/'simulator_equivalence/report.json')
    assert all(x['status']=='PASS' for x in [real,mapping,modules,reconfig,cross])
    assert len(real['results'])==200 and len(mapping['results'])==22
    for relative,h in real['source_sha256'].items():assert sha(ROOT/relative)==h,relative
    d={(x['scene'],x['variant'],x['mode'],x['profile']):x for x in real['results']}
    selected=[x for x in real['results'] if x['variant']=='bsu8'];comparisons={}
    for v in ['linear','odd','bsu16','bsu8_local_r']:
        changes=[100*(d[(x['scene'],v,x['mode'],x['profile'])]['cycles']-x['cycles'])/d[(x['scene'],v,x['mode'],x['profile'])]['cycles'] for x in selected]
        comparisons[v]={'runs':len(changes),'mean_saved_percent':statistics.mean(changes),'min_saved_percent':min(changes),
                        'max_saved_percent':max(changes),'faster':sum(x>0 for x in changes),'equal':sum(x==0 for x in changes),'slower':sum(x<0 for x in changes)}
    logs=OUT/'logs';logs.mkdir(exist_ok=True)
    for src,dst in [('tmp/t05_regression.log','iverilog.log'),('tmp/t05_lint.log','verilator_lint.log'),
                    ('tmp/t05_mapping.log','mapping_initial_parser_failure.log'),('tmp/t05_mapping_resume.log','mapping_metadata_failure.log'),
                    ('tmp/t05_real_matrix.log','blocked_executable.log'),('tmp/t05_mapping_production_width.log','mapping_final.log')]:
        shutil.copy2(ROOT/src,logs/dst)
    rtl_log=(logs/'iverilog.log').read_text(errors='replace');lint_log=(logs/'verilator_lint.log').read_text(errors='replace')
    assert rtl_log.count('PASS: tb_')==80 and 'PASS: all configured' in rtl_log
    assert 'PASS: Verilator lint completed' in lint_log
    python_log=(logs/'python_tests.log').read_text(errors='replace')
    assert 'Ran 60 tests' in python_log and 'OK (skipped=1)' in python_log
    # Local source snapshot makes later provenance checks independent of future edits.
    files=set(real['source_sha256'])|set(mapping['source_sha256'])
    files.update(['verification/rtl/tb_t05_sorters.sv','verification/rtl/tb_t05_reconfiguration.sv',
                  'scripts/run_t05_sorters.py','scripts/run_t05_real.py','scripts/run_t05_reconfiguration.py',
                  'scripts/map_t05_modules.py','scripts/check_t05_simulator_equivalence.py','scripts/summarize_t05.py',
                  'verification/run_t05.ps1','verification/test_t05_evidence.py',
                  'verification/test_implementation_status.py','verification/test_rtl_contract.py','verification/test_t04_real_rgb_evidence.py',
                  'docs/T05实现与验收计划_2026-10-09.md','docs/T05_BSU接口与共享资源规格_v1.md',
                  'docs/开发日志_2026-10-10_T05共享资源与Bitonic签核.md'])
    for relative in files:
        dest=OUT/'source_snapshot'/relative;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/relative,dest)
    summary={'task':'T05','signoff_date':'2026-10-10','status':'COMPLETE_FUNCTIONAL','selected_configuration':{
        'top':'gs_accel_system_top','USE_BITONIC_SORT':1,'SORT_CAPACITY':8,'GROUP_CAPACITY':8,'LANES':4,
        'USE_SHARED_PE':1,'USE_SHARED_PROJECTION_PE':1,'USE_SHARED_RASTER_PE':1,'USE_FINAL_RGB_DMA':1},
        'real_runs':200,'real_scenes':5,'gaussians_per_scene':512,'full_scene':False,'cpu_orders_batch_ranges':True,
        'real_report':'experiments/t05_20261009/real/report.json','comparisons_saved_percent':comparisons,
        'production_GPR_grants':{k:sum(x[k] for x in selected) for k in ['G','P','R']},
        'unit_sorter_configurations':len(modules['results']),'unit_output_checks':sum(x['outputs'] for x in modules['results']),
        'module_mapping_runs':22,'reconfiguration_scenes':5,'reconfiguration_frames':10,'regression_self_check_tests':80,
        'production_lint_pass':True,'cross_simulator_cycles_state_rgb_equal':True,
        'python_tests':{'total':60,'passed':59,'failed':0,'skipped':1,'skip_reason':'T04 source hashes are historical; current hashes checked strictly under T05'},
        'open_scope':['T06 autonomous pivot/capacity/global scheduling','T09 automatic performance calibration',
                      'T10 full 13 scenes, full models, formal views and GT','T11/T12 full-chip SRAM, STA, area and activity power'],
        'known_tradeoffs':['K8 is on average 0.08% slower than shared insertion and 1.06% slower than legacy Odd-Even on this workload.',
                           'Shared R adds about 0.10% cycles on average versus local R; context registers increase module area.',
                           'ABC shared-PE module delay is 5008.37 ps in ICsprout55 TT: a T11/T12 timing risk, not a passed 200MHz STA.'],
        'resolved_execution_failures':['Mapping parser initially assumed hierarchical stats; fixed for flat stats.',
                                       'Yosys $scopeinfo metadata explicitly removed before mapping; no unknown hardware cells remain.',
                                       'Windows signing policy blocked linear executable; same RTL run via Icarus, other variants via Verilator, cross-checked identically.'],
        'not_run':['Full-chip new-version mapping/STA/power','GT quality metrics','13-scene full-model matrix'],
        'source_snapshot':'experiments/t05_20261009/source_snapshot',
        'source_sha256':{p:sha(ROOT/p) for p in sorted(files)}}
    (OUT/'audit.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print(json.dumps({'status':summary['status'],'comparisons':comparisons},indent=2))
if __name__=='__main__':main()
