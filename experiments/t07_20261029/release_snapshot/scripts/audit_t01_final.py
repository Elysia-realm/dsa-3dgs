"""Evidence gate for T01 initial feedback; never promotes timing/PPA closure."""
import json,math,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,WORK,PROFILE,read,save,sha,frozen
CACHE={}
def digest(p):
    p=Path(p);key=(str(p),p.stat().st_size,p.stat().st_mtime_ns)
    if key not in CACHE:CACHE[key]=sha(p)
    return CACHE[key]
def matching(p,h):assert digest(p)==h.upper(),('hash mismatch',str(p))
def sources(m):
    assert m
    for f,h in m.items():matching(ROOT/f,h)
def timing_resources(log):
    text=Path(log).read_text();r={}
    for k,pattern in [('user_seconds',r'User time \(seconds\):\s*([\d.]+)'),('system_seconds',r'System time \(seconds\):\s*([\d.]+)'),('peak_rss_kib',r'Maximum resident set size \(kbytes\):\s*(\d+)')]:
        m=re.search(pattern,text);r[k]=float(m[1]) if m else None
    return r
def main():
    checks=[];matrix=[];performance=[];profile=read(PROFILE)
    def check(name,fn):
        try:detail=fn();checks.append(dict(name=name,status='PASS',detail=detail));print('PASS',name,flush=True)
        except Exception as e:checks.append(dict(name=name,status='FAIL',error=repr(e)));print('FAIL',name,repr(e),flush=True)
    check('frozen_production_source',lambda:dict(files=len(frozen()),profile_sha256=digest(PROFILE)))
    def tools():
        t=read(BASE/'toolchain.json')
        for row in t['files']:matching(row['path'],row['sha256'])
        matching(t['oss_archive']['path'].replace('D:\\3DGS','/mnt/d/3DGS').replace('\\','/'),t['oss_archive']['sha256'])
        return dict(payload_files=len(t['files']),yosys=t['versions']['yosys'].strip())
    check('native_tool_versions_and_payloads',tools)
    def functional():
        r=read(BASE/'migration_audit.json');assert r['status']=='PASS_MIGRATION_FUNCTIONAL_NOT_T01_SIGNOFF'
        assert all(x['status']=='PASS' for x in r['checks']);sources(r['source_sha256'])
        for kind,rows in r['results'].items():
            assert len(rows)==(40 if kind=='subset' else 5)
            for row in rows:
                sources(row['source_sha256']);n=row['scene']
                if kind=='subset':
                    ax='limited' if row['axi_profile']=='limited' else 'ideal';d=BASE/'real'/kind/n/f'm{row["mode"]}_{ax}'
                else:d=BASE/'real'/kind/n
                current=read(d/'result.json');assert current['status']=='PASS'
                for f,h in current['evidence_sha256'].items():matching(d/f,h)
                b=read(BASE/'build'/kind/'binary.json');matching(b['path'],current['binary_sha256'])
                if kind=='full':
                    c=current['counters'];m=read(Path(current['reference_directory']).parent/'manifest.json')
                    perf=dict(scene=n,camera=current['camera_index'],gaussians=current['gaussians'],full_scene=True,
                      width=current['width'],height=current['height'],mode='G',axi='legacy_ideal',command_cycles=current['command_cycles'],
                      hypothetical_200MHz_fps=200_000_000/current['command_cycles'],host_wall_seconds=current['execution']['wall_seconds'],
                      host_process=timing_resources(d/'run.log'),independent_float_mae=current['independent_float_mae'],counters=c,
                      dma_bus_bytes={k:int(v)*16 for k,v in c['REAL_DMA_COUNTS'].items() if k.endswith('beats')},
                      measured_hardware_fps=None,verified_operating_frequency_mhz=None,core_power_w=None,
                      timing_boundary='RTL command acceptance through final RGB response/DONE; host process time separately includes TB input loading/output dumps',
                      input_sha256=current['input_sha256'],source_manifest_sha256=digest(BASE/'frozen_source_manifest.json'))
                    p=c['REAL_SHARED_PE'];dma=c['REAL_DMA_COUNTS'];q=c['REAL_QSU']
                    perf['separate_service_lower_bounds']={'shared_GPR_services':p['G']+p['P']+p['R'],'P_services':p['P'],'qsu_read_beats':dma['qsu_read_beats'],'attribute_beats':dma['attribute_beats']}
                    perf['qsu_average_leaf_records']=q['input']/q['leaves'];performance.append(perf)
        return dict(subset_runs=40,full_model_scenes=5,nonempty_repeat_scenes=5,full_order_scenes=5)
    check('source_bound_functional_migration',functional)
    def original_fields():
        r=read(BASE/'encoding/input_encoding_report.json');assert r['status']=='PASS' and len(r['results'])==10;sources(r['source_sha256'])
        for row in r['raw_ply'].values():matching(ROOT/row['path'],row['sha256'])
        return dict(datasets=10,sampled_SH_fields=sum(x['SH_fields_checked'] for x in r['results']))
    check('raw_PLY_and_encoded_fields',original_fields)
    def padding():
        p=read(BASE/'hist_padding_proof/proof.json');assert p['status']=='PASS_POINTER_BOUNDS_INDUCTION'
        matching(ROOT/'rtl/sort/autonomous_qsu.sv',p['original_rtl_sha256'])
        for f,key in [('proof.log','log_sha256'),('bounds.ys','proof_script_sha256'),('autonomous_qsu_bounds.sv','proof_source_sha256')]:matching(BASE/'hist_padding_proof'/f,p[key])
        log=(BASE/'hist_padding_proof/proof.log').read_text();assert 'Induction step proven: SUCCESS!' in log and 'No SAT model' not in log
        for alpha in [0,1]:
            d=BASE/'synthesis'/f'alpha{alpha}';padded=read(d/'padding_definition.json');changes=padded['changes']
            assert len(changes)==38 and sorted(x['row'] for x in changes)==list(range(218,256))
            assert all(x['after']=="1712'0" and x['before'] in ('undriven',"1712'x") for x in changes)
            matching(WORK/'synthesis'/f'alpha{alpha}'/'memory_mapped.il',padded['input_sha256'])
            matching(WORK/'synthesis'/f'alpha{alpha}'/'memory_padding_defined.il',padded['output_sha256'])
            pre=read(d/'premap.json');matching(pre['artifact'],pre['artifact_sha256']);assert pre['execution']['exit_code']==0
            matching(d/'premap.log',pre['execution']['log_sha256'])
            assert 'Found and reported 0 problems.' in (d/'premap.log').read_text()
        return dict(exact_padding_bits=65056,valid_rows=218,formal_scope=p['scope'])
    check('padding_refinement_and_no_undriven_nets',padding)
    def physical(alpha,pdk):
        d=BASE/'synthesis'/f'alpha{alpha}'/pdk;m=read(d/'mapping.json');a=read(d/'mapping_audit.json');s=read(d/'sta_result.json');adapt=read(d/'sta_netlist_adapter.json')
        if pdk=='nangate45':
            lib_record=next(x for x in read(ROOT/'experiments/environment_setup_20261024/nangate_compatibility_audit.json')['libraries'] if x['corner']=='typical')
        else:
            lib_record=next(x for x in read(ROOT/'asic/reports/t01/toolchain_manifest.json')['libraries'] if x['corner']=='TT' and x['pdk'].startswith('ICsprout55'))
        assert m['liberty_sha256']==lib_record['sha256'].upper(),'Library differs from frozen TT release'
        expected=profile['parameters'].copy();expected['ENABLE_ALPHA_ZERO_SKIP']=alpha
        assert m['parameters']==expected and not m['blackboxed_modules'];sources(m['source_sha256'])
        assert a['status']=='PASS_LIBRARY_COVERAGE' and not a['unknown_cells']
        assert m['execution']['exit_code']==s['execution']['exit_code']==0 and s['coverage_ok'] and not s['warnings']
        for path,h in [(d/'gs_accel_system_top_mapped.v',m['netlist_sha256']),(Path(m['liberty']),m['liberty_sha256']),
          (d/'mapping.log',m['execution']['log_sha256']),(d/'mapped_stat.json',a['mapped_stat_sha256']),
          (d/'gs_accel_system_top_mapped.sta.v',s['sta_netlist_sha256']),(d/'sta.log',s['execution']['log_sha256']),
          (d/'applied.sdc',s['sdc_sha256']),(ROOT/'asic/scripts/run_t01_wsl_sta.tcl',s['sta_script_sha256'])]:matching(path,h)
        assert adapt['status']=='PASS_BIT_CONNECTIVITY_EQUIVALENT' and adapt['top']=='gs_accel_system_top'
        matching(ROOT/'asic/scripts/t01_sta_netlist_adapter.py',adapt['adapter_sha256'])
        matching(ROOT/'asic/scripts/t01_structural_width_proof.py',adapt['proof']['checker_sha256'])
        assert adapt['proof']['status']=='PASS_STRUCTURAL_SIGNEDNESS_INDEPENDENCE' and adapt['proof']['counts']['safe_width_adjustments']==0
        assert adapt['proof']['counts']['open_connections']==0
        assert adapt['input_sha256']==m['netlist_sha256'] and adapt['output_sha256']==s['sta_netlist_sha256']
        assert s['netlist_sha256']==m['netlist_sha256'] and s['liberty_sha256']==m['liberty_sha256']
        log=(d/'sta.log').read_text();assert 'T01_LINKED_TOP=gs_accel_system_top' in log and 'T01_STA_REPORT_END_REQUIRES_AUDIT' in log
        assert 'T01_COVERAGE_OK=1' in log and 'T01_BEGIN_ASYNC_RESET_CHECKS' in log and 'T01_BEGIN_ELECTRICAL' in log
        assert 'set_false_path' not in (d/'applied.sdc').read_text()
        c=s['constraints'];assert c['clock_period_ns']==5 and c['uncertainty_ns']==0.25 and c['input_max_ns']==c['output_max_ns']==0.5 and not c['reset_false_path']
        assert c['output_load']==(3.899 if pdk=='nangate45' else 0.003539972)
        assert all(math.isfinite(x) for x in s['slack_ns'].values())
        row=dict(alpha=alpha,pdk=pdk,corner='TT',area_mm2=a['standard_cell_area_mm2'],cells=a['library_cell_instances'],
          setup_wns_ns=s['slack_ns']['max'],hold_wns_ns=s['slack_ns']['min'],constraint_coverage=True,unknown_cells=0,
          electrical_violations_reported='VIOLATED' in log.split('T01_BEGIN_ELECTRICAL',1)[1],
          timing_200MHz_verified=False,final_4mm2_verified=False,final_macro_storage_verified=False,
          model_validity='Register-array implementation; ideal interconnect/clock. Severe electrical violations cause out-of-characterization extrapolation. WNS is a diagnostic tool result, not a physically validated delay/Fmax estimate.',
          mapping_process=m['execution'],sta_process=s['execution'],sta_host=timing_resources(d/'sta.log'),
          source_sha256=m['source_sha256'],library_sha256=m['liberty_sha256'],netlist_sha256=m['netlist_sha256'],sta_log_sha256=s['execution']['log_sha256'],module_costs=a['module_costs'])
        assert row['electrical_violations_reported']
        matrix.append(row);return {k:row[k] for k in ['area_mm2','setup_wns_ns','hold_wns_ns','constraint_coverage']}
    for alpha in [0,1]:
        for pdk in ['nangate45','icsprout55']:check(f'alpha{alpha}_{pdk}_mapping_and_STA',lambda a=alpha,p=pdk:physical(a,p))
    def alpha_control():
        r=read(BASE/'alpha_control/report.json');assert r['status']=='PASS' and len(r['results'])==5;sources(r['source_sha256'])
        assert r['sole_parameter_delta']=={'ENABLE_ALPHA_ZERO_SKIP':[1,0]}
        for x in r['results']:
            matching(BASE/'alpha_control'/x['scene']/'frame.rgb',x['rgb_sha256']);assert x['saved_cycles']>0
        return {'scenes':5,'min_cycle_saving_percent':min(x['saved_percent'] for x in r['results']),'max_cycle_saving_percent':max(x['saved_percent'] for x in r['results'])}
    check('same_condition_alpha_control',alpha_control)
    comparisons=[]
    if len(matrix)==4:
        for pdk in ['nangate45','icsprout55']:
            off=next(r for r in matrix if r['pdk']==pdk and r['alpha']==0);on=next(r for r in matrix if r['pdk']==pdk and r['alpha']==1)
            comparisons.append(dict(pdk=pdk,area_delta_mm2=on['area_mm2']-off['area_mm2'],area_delta_percent=100*(on['area_mm2']-off['area_mm2'])/off['area_mm2'],decision='Retain existing exact alpha skip; subset-cycle benefit with small mapped overhead. No new RTL optimization; final targets remain open.'))
    status='PASS_T01_INITIAL_FEEDBACK_EVIDENCE' if all(c['status']=='PASS' for c in checks) else 'INCOMPLETE'
    report=dict(status=status,checks=checks,physical_matrix=matrix,alpha_comparison=comparisons,full_model_performance=performance,
      acceptance_scope='WSL integration and first source-bound dual-process TT mapping/top-level STA diagnostics under register storage. Not final timing/electrical closure, SRAM/DDR, native/GT/30FPS or power acceptance.',
      signoff_recommendation='ELIGIBLE_AFTER_HUMAN_READABLE_SCOPE_AND_RISK_REVIEW' if status.startswith('PASS') else 'DO_NOT_SIGN',signed_off=False,
      open_design_work=[dict(owner='T11 (front-load alongside T07/T08)',issue='core_rst_ni=rst_ni&&!soft_reset_pulse drives an excessive unbuffered reset load; repair electrical/reset-distribution implementation and revalidate recovery/removal. Do not infer Fmax from current extrapolated WNS.'),
       dict(owner='T11',issue='Replace register-array first-feedback implementation with validated memory ports/latencies/macros and account for control, padding and all storage.'),
       dict(owner='T07/T08 and mandatory post-T08 performance check',issue='QSU traffic, attribute beats and shared-service bounds exceed the assumed 200MHz/30FPS budget; reduce work/bytes and evaluate necessary throughput changes.'),
       dict(owner='T12',issue='Final same-version SS/TT/FF timing/electrical closure, area, activity power and verified-frequency FPS.'),dict(owner='T10',issue='Formal 13-scene, native/target-resolution, >=5 views per scene and GT quality scope remains pending.')])
    save(BASE/'final_audit.json',report)
    save(BASE/'final_evidence_hashes.json',{p:h for (p,_,_),h in CACHE.items()})
    assert status.startswith('PASS'),checks
if __name__=='__main__':main()
