"""T07 evidence gate. Report-only; never changes the signed task status."""
import sys,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t07_common import BASE,T01,PROFILE,read,save,sha,source_manifest
from scripts.t06_release_common import bindings,integer
from scripts.run_t07_real import VARIANTS,state_values
from scripts.read_rgb888_frame import decode_rgb888
from PIL import Image
CACHE={}
def digest(path):
    p=Path(path);s=p.stat();key=(str(p),s.st_size,s.st_mtime_ns)
    if key not in CACHE:CACHE[key]=sha(p)
    return CACHE[key]
def matching(path,expected):assert digest(path)==expected.upper(),('hash mismatch',str(path))
def sources(records):
    for f,h in records.items():matching(ROOT/f,h)

def main():
    checks=[];performance=[];current=source_manifest()
    def gate(name,fn):
        try:result=fn();checks.append(dict(name=name,status='PASS',detail=result));print('PASS',name,flush=True)
        except Exception as e:checks.append(dict(name=name,status='FAIL',error=repr(e)));print('FAIL',name,repr(e),flush=True)
    def baseline():
        before=read(BASE/'source_before/manifest.json')
        assert before==read(T01/'frozen_source_manifest.json')
        for f,h in before.items():matching(BASE/'source_before'/f,h)
        changed=[f for f,h in current.items() if before.get(f,'').upper()!=h.upper()]
        return dict(frozen_before_files=len(before),current_files=len(current),changed=changed)
    gate('baseline_and_changed_source',baseline)
    def arithmetic():
        u=read(BASE/'units/report.json');s=read(BASE/'shape/report.json')
        assert u['status']==s['status']=='PASS' and u['termination_pairs']==32448 and s['vectors']==20000
        sources(u['source_sha256']);sources(s['source_sha256']);sources(u['production_source_sha256'])
        matching(BASE/'shape/vectors.memh',s['vectors_sha256'])
        for p in ['units/pixel','units/current_math','shape/run']:
            r=read(BASE/(p+'.execution.json'));assert r['exit_code']==0;matching(BASE/(p+'.log'),r['log_sha256'])
        return dict(termination_pairs=32448,shape_vectors=20000,independently_checked_rejected_pixels=s['independent_pixels_checked'])
    gate('pixel_protocol_and_independent_math',arithmetic)
    def real():
        expected=[]
        for v in VARIANTS:
            for n in read(PROFILE)['scenes']:
                for m in (range(4) if v=='C' else [0]):
                    for ax in (['ideal','limited'] if v=='C' else ['ideal']):expected.append(('subset',v,n,m,ax))
        for v in ['S','C']:
            expected += [('full',v,n,0,'ideal') for n in read(PROFILE)['scenes']]
        expected += [('repeat','C',n,3,'limited') for n in read(PROFILE)['scenes']]
        binaries={};rows=[]
        for kind,v,n,m,ax in expected:
            d=BASE/'real'/kind/v/n/(f'm{m}_{ax}' if kind=='subset' else '')
            row=read(d/'result.json');assert row['status']=='PASS';sources(row['source_sha256'])
            key=(kind,v)
            if key not in binaries:
                b=read(BASE/'build'/kind/v/'binary.json');matching(b['path'],b['binary_sha256']);sources(b['source_sha256'])
                assert Path(b['path']).read_bytes()[:4]==b'\x7fELF'
                bench=b['command'][b['command'].index('--top-module')+1]
                assert bench==('tb_t07_repeat' if kind=='repeat' else 'tb_t07_workload')
                mapping=bindings(bench);defs=dict(re.findall(r'-D(TB_[A-Z0-9_]+)=(\d+)',' '.join(b['command'])))
                defaults=dict(re.findall(r'`define\s+(TB_[A-Z0-9_]+)\s+(\d+)',(ROOT/f'verification/rtl/{bench}.sv').read_text()))
                top=(ROOT/'rtl/gs_accel_system_top.sv').read_text().split(') (',1)[0]
                for name,val in b['parameters'].items():
                    if name in mapping:observed=int(defs.get(mapping[name],defaults.get(mapping[name],'-999')))
                    else:
                        z=re.search(r'\b'+name+r"\s*=\s*([0-9]+(?:'[bdh][0-9a-fA-F]+)?)",top);assert z,name;observed=integer(z[1])
                    assert observed==val,(kind,v,name,observed,val)
                binaries[key]=b
            b=binaries[key];assert row['binary_sha256']==b['binary_sha256'] and row['parameters']==b['parameters']
            for f,h in row['evidence_sha256'].items():matching(d/f,h)
            cmd=read(d/'run.command.json')
            for token in cmd:
                if token.startswith(('+ATTR=','+MEAN=','+CAMERA=')):
                    name,path=token[1:].split('=',1);matching(path,row['input_sha256'][name])
            reference=Path(row['reference_directory']);matching(reference/'result.json',row['reference_result_sha256'])
            assert (d/'frame.rgb').read_bytes()==(reference/'frame.rgb').read_bytes()
            assert Image.open(d/'frame.png').tobytes()==decode_rgb888((d/'frame.rgb').read_bytes(),row['width'],row['height']).tobytes()
            a=state_values(d/'state.memh',2 if kind=='repeat' else 1);old=state_values(reference/'state.memh',2 if kind=='repeat' else 1)
            assert len(a)==len(old)
            assert all(rgb==rgb0 and (t==t0 or (v!='B' and max(t,t0)<=7)) for (rgb,t),(rgb0,t0) in zip(a,old))
            c=row['counters'];t=c['REAL_T07_TERMINATION']
            assert t['accepted']==t['alpha_issued']+t['skipped'] and t['enabled']==VARIANTS[v][1]
            assert c['REAL_SHAPE']['enabled']==VARIANTS[v][0] and c['REAL_ALPHA_SKIP']['enabled']==VARIANTS[v][2]
            if kind=='full' and v=='C':
                assert t['skipped']>0 and t['updates']>0 and c['REAL_SHAPE']['rejected_blocks']>0
                assert row['independent_float_mae']<=5 and row['command_cycles']<row['baseline_cycles']
                performance.append(row)
            if kind=='repeat':assert c['REAL_AUTO']['image_mismatches']==0
            rows.append(row)
        return dict(runs=len(rows),subset_runs=60,complete_model_runs=10,repeated_frame_scenes=5,binaries=len(binaries),
          no_pixel_skip_subset_scenes=[r['scene'] for r in rows if r['variant']=='C' and r['full_scene'] is False and r['mode']==0 and r['axi']=='ideal' and r['counters']['REAL_T07_TERMINATION']['skipped']==0])
    gate('source_bound_real_production_and_ablations',real)
    def order():
        b=read(T01/'build/order/binary.json');assert b['command'][b['command'].index('--top-module')+1]=='tb_t06_qsu_bsu'
        compiled=[f for f in b['command'] if f.endswith('.sv')];assert len(compiled)==4 and '-f' not in b['command']
        for f in compiled:matching(ROOT/f,b['source_sha256'][f])
        matching(b['path'],b['binary_sha256']);r=read(T01/'real/order/report.json');assert r['status']=='PASS' and len(r['results'])==5
        for row in r['results']:
            d=T01/'real/order'/row['scene'];a=read(d/'result.json')
            for f,h in a['evidence_sha256'].items():matching(d/f,h)
            inputs=Path(a['reference_directory']);matching(inputs/'manifest.json',a['input_manifest_sha256'])
            for f,h in read(inputs/'manifest.json')['vectors_sha256'].items():matching(inputs/f,h)
        return dict(reused=True,scenes=5,unchanged_compiled_sources=compiled,scope='Unchanged native QSU+BSU+shared-PE all-record component test; new top-level visible ordering separately rerun in T07.')
    gate('unchanged_all_record_sort_component',order)
    def regressions():
        legacy=read(BASE/'legacy_units/report.json');assert legacy['status']=='PASS' and legacy['compile_count']==84 and legacy['run_count']==83;sources(legacy['source_sha256'])
        for row in legacy['results']:
            # Multiple attempts are preserved; find the matching accepted log.
            candidates=list((BASE/'legacy_units').glob(f'{row["index"]:03d}*.log'))
            assert any(digest(p)==row['log_sha256'] for p in candidates)
        selected=read(BASE/'selected_units/report.json');assert selected['status']=='PASS' and len(selected['groups'])==8;sources(selected['source_sha256'])
        for row in selected['groups']:
            p=BASE/'selected_units'/row['name']/('native_report.json' if row['name']=='rgb_native' else 'report.json');matching(p,row['report_sha256'])
        recovery=read(BASE/'candidate_recovery/report.json');assert recovery['status']=='PASS' and len(recovery['results'])==10;sources(recovery['source_sha256'])
        for row in recovery['results']:matching(BASE/'candidate_recovery'/f'fault{row["fault"]}.log',row['execution']['log_sha256'])
        aux=read(BASE/'aux/report.json');assert aux['status']=='PASS';sources(aux['source_sha256']);sources(aux['production_source_sha256'])
        assert 'OK' in (BASE/'aux/python_checks.log').read_text()
        return dict(legacy_compiles=84,legacy_runs=83,selected_groups=8,candidate_control_recovery=10,
          scope='Legacy component controls plus explicitly enabled candidate recovery and independent math/profile lint; real full frames supply nonzero path proof.')
    gate('existing_capabilities_and_candidate_recovery',regressions)
    def physical():
        audit=read(BASE/'mapping/audit.json');assert audit['status']=='PASS_LOCAL_EVIDENCE_AUDIT' and len(audit['results'])==4
        for row in audit['results']:
            sources(row['source_sha256']);d=BASE/'mapping'/f'pixel{row["pixel_skip"]}'/row['pdk']
            lib=read(T01/'synthesis/alpha1'/row['pdk']/'mapping.json')
            assert row['liberty_sha256']==lib['liberty_sha256'];matching(lib['liberty'],row['liberty_sha256'])
            matching(d/'mapped.v',row['netlist_sha256']);matching(d/'sta.log',row['sta_log_sha256'])
            assert not row['unknown_cells'] and not row['whole_chip_frequency_verified']
            a=read(d/'sta_netlist_adapter.json');assert a['status']=='PASS_BIT_CONNECTIVITY_EQUIVALENT'
            matching(d/'mapped.sta.v',a['output_sha256'])
        shape=read(BASE/'shape_mapping/report.json');assert shape['status']=='PASS_AREA_MAPPING' and len(shape['results'])==2
        for row in shape['results']:
            lib=read(T01/'synthesis/alpha1'/row['pdk']/'mapping.json')
            assert row['library_sha256']==lib['liberty_sha256'];matching(lib['liberty'],row['library_sha256'])
            matching(ROOT/'rtl/raster/gaussian_shape_block_reject.sv',row['source_sha256'])
            matching(BASE/'shape_mapping'/row['pdk']/'mapped.v',row['netlist_sha256'])
        return dict(termination_comparisons=audit['comparisons'],shape_area=shape['results'],final_ppa_pass=False)
    gate('dual_process_local_cost_and_timing_diagnostics',physical)
    def structure():
        r=read(BASE/'production_structure/report.json');assert r['status']=='PASS' and len(r['results'])==2
        for row in r['results']:
            sources(row['source_sha256']);matching(row['coarse_json'],row['coarse_sha256'])
            matching(BASE/'production_structure'/f'pixel{row["enabled"]}'/'coarse.log',row['execution']['log_sha256'])
        return [{k:row[k] for k in ['enabled','generic_ff_bits','generic_memory_bits']} for row in r['results']]
    gate('actual_production_structure_pruning',structure)
    def tools():
        r=read(T01/'toolchain.json')
        for f in r['files']:matching(f['path'],f['sha256'])
        return dict(baseline_toolchain_sha256=digest(T01/'toolchain.json'),same_frozen_tool_payloads=True)
    gate('native_tool_payloads',tools)
    comparisons=[]
    if len(performance)==5:
        for row in performance:
            s=read(BASE/'real/full/S'/row['scene']/'result.json')
            comparisons.append(dict(scene=row['scene'],baseline_cycles=row['baseline_cycles'],shape_only_cycles=s['command_cycles'],combined_cycles=row['command_cycles'],
              combined_saved_percent=row['saved_percent'],pixel_incremental_saved_percent=100*(s['command_cycles']-row['command_cycles'])/s['command_cycles'],
              pixel_incremental_alpha_tasks_saved=s['counters']['REAL_T07_TERMINATION']['alpha_issued']-row['counters']['REAL_T07_TERMINATION']['alpha_issued'],
              pixel_incremental_R_services_saved=s['counters']['REAL_SHARED_PE']['R']-row['counters']['REAL_SHARED_PE']['R']))
    passed=all(r['status']=='PASS' for r in checks)
    save(BASE/'release_audit.json',dict(status='PASS_T07_EVIDENCE' if passed else 'INCOMPLETE',checks=checks,full_performance=performance,comparisons=comparisons,
       signed_off=False,acceptance_scope='Formal T07 shape/low-alpha/pixel termination profile, five selected scenes width128, current-function integration and bounded local cost decision; not final GT/native-resolution/global PPA or 30FPS.',
       decision='Retain shape plus pixel termination: exact RGB, bounded terminal-T equivalence, small positive incremental full-frame cycle benefit and substantial local area/state reduction. Stop optional tuning; proceed T08 with T11 budgets.' if passed else 'DO_NOT_SIGN',
       outstanding=['Top-level reset electrical/hold closure and all-corner frequency','Full-chip SRAM/storage/area and shared-DDR integration',
                    'Target-resolution full-model diagnostic at T08 entry, then T10 formal 13-scene multi-view GT','Activity power and final 30FPS',
                    'System-wide epoch recycling and backing-state initialization contract; local observed-transition wrap test is not full-system wrap acceptance']))
    save(BASE/'release_evidence_hashes.json',{p:h for (p,_,_),h in CACHE.items()})
    assert passed,checks
if __name__=='__main__':main()
