"""Fail-closed selected-profile release gate; never sets implementation signoff."""
import argparse,json,re,sys,traceback
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t06_release_common import BASE,OLD,PROFILE,profile,assert_command_profile,check_frozen_sources
from scripts.run_t06_perf_optimization import read,save,sha
FULL=ROOT/'experiments/t06_full_precount_mem_20261022'

def verify_sources(mapping):
    assert mapping,'missing source provenance'
    for f,h in mapping.items():assert sha(ROOT/f)==h,('stale source',f)

def main():
    checks=[];evidence={};performance=None
    def check(name,fn):
        try:
            detail=fn();checks.append(dict(name=name,status='PASS',detail=detail))
        except Exception as e:
            checks.append(dict(name=name,status='MISSING' if isinstance(e,FileNotFoundError) else 'FAIL',error=repr(e)))
    def report(path,count=None):
        f=ROOT/path;r=read(f);assert r['status']=='PASS',(path,r['status'])
        if count is not None:assert len(r['results'])==count,(path,len(r['results']))
        verify_sources(r['source_sha256']);evidence[path]=sha(f);return r
    def config():
        sources=check_frozen_sources()
        for cmd in [BASE/'build/H/command.json',OLD/'build/H/command.json',FULL/'build/command.json']:
            assert_command_profile(read(cmd))
        for f,h in read(FULL/'build/sources.json').items():assert sha(ROOT/f)==h
        evidence[PROFILE.relative_to(ROOT).as_posix()]=sha(PROFILE)
        return dict(profile=profile()['profile_id'],frozen_source_files=len(sources),runtime_qsu_enable_required=True)
    check('release_profile_and_frozen_RTL',config)
    reused=[('qsu_boundaries','experiments/t06_precount_mem_20261022/units/report.json',19),
      ('qsu_abort_backpressure','experiments/t06_precount_mem_20261022/faults/report.json',8),
      ('profile_camera_fault_recovery','experiments/t06_precount_mem_20261022/recovery/report.json',10),
      ('default_80_regression_and_H_lint','experiments/t06_precount_mem_20261022/compat/report.json',2),
      ('qsu_generic_memory','experiments/t06_precount_mem_20261022/synthesis/report.json',2),
      ('rgb_burst_errors','experiments/t06_rgb_burst_20261022/units/report.json',41),
      ('rgb_native_stage_only','experiments/t06_rgb_burst_20261022/units/native_report.json',2),
      ('dot3_arithmetic','experiments/t06_dot3_20261021/units/report.json',None),
      ('dot3_resources','experiments/t06_dot3_20261021/resources/report.json',2),
      ('address_guard','experiments/t06_20261018/memory_layout_units/report.json',7),
      ('projection_semantics','experiments/t06_20261018/unit_checks/report.json',None),
      ('current_legacy_protocol','experiments/t06_release_20261022/protocol/report.json',15)]
    for name,path,count in reused:
        def test(path=path,count=count):
            r=report(path,count);return dict(report=path,cases=len(r.get('results',[])),reuse='only exact current source hashes')
        check(name,test)
    def real():
        r=report('experiments/t06_release_20261022/real_report.json',40)
        assert r['profile_sha256']==sha(PROFILE)
        expected={(n,m,a) for n in profile()['scenes'] for m in range(4) for a in ['ideal','limited']}
        assert {(x['scene'],x['mode'],x['profile']) for x in r['results']}==expected
        for x in r['results']:
            verify_sources(x['source_sha256']);d=BASE/'subset'/x['scene']/f'H_m{x["mode"]}_{x["profile"]}'
            m=read(d.parent/'manifest.json');assert not m['full_scene'] and m['gaussians']==512
            for f,h in m['input_sha256'].items():assert sha(d.parent/f)==h
            cmd=read(d/'command.json');assert '+AUTO_QSU' in cmd and not any('BATCH_ROOT' in a for a in cmd)
            raw=(d/'frame.rgb').read_bytes();assert sha(d/'frame.rgb')==x['rgb_sha256']
            assert raw==Image.open(d/'frame.png').tobytes()==bytes(int(v,16) for v in (d/'rgb.memh').read_text().split())==(d.parent/'oracle/frame.rgb').read_bytes()
            assert (d/'sorted.txt').read_bytes()==(d.parent/'expected_sorted.txt').read_bytes()
            c=x['counters'];assert c['REAL_QSU']['input']==512 and c['REAL_QSU']['reads']==c['REAL_QSU']['axi_reads']
            assert all(c['REAL_SHARED_PE'][k]>0 for k in ['G','P','R'])
            assert c['REAL_ALPHA_SKIP']['enabled']==1 and c['REAL_RGB_BURST']['configured']==16
            assert 'error=00000000' in (d/'run.log').read_text() and 'disjoint=1' in (d/'run.log').read_text()
        return dict(runs=40,full_scene=False,width=128)
    check('fresh_profile_real_40',real)
    def repeated():
        r=report('experiments/t06_release_20261022/repeat/report.json',5);assert r['profile_sha256']==sha(PROFILE)
        assert {x['scene'] for x in r['results']}==set(profile()['scenes'])
        for x in r['results']:
            assert x['status']=='PASS' and x['frames']==2 and x['auto']['observe_mode']==3 and x['auto']['selected_mode']==0 and x['auto']['image_mismatches']==0
            assert sha(BASE/'repeat'/x['scene']/'run.log')==x['log_sha256']
        return dict(scenes=5,nonempty_frames=10,scope=r['scope'])
    check('nonempty_continuous_frames_and_epoch',repeated)
    def order():
        r=report('experiments/t06_release_20261022/full_order/report.json',5)
        assert {x['scene'] for x in r['results']}==set(profile()['scenes'])
        for x in r['results']:
            d=BASE/'full_order'/x['scene'];m=read(d/'manifest.json');orig=read(FULL/x['scene']/'manifest.json')
            assert m['gaussians']==x['metrics']['n']==orig['gaussians'] and m['full_scene']
            assert sha(d/'manifest.json')==x['manifest_sha256'] and sha(d/'run.log')==x['log_sha256']
            for f,h in m['vectors_sha256'].items():assert sha(d/f)==h
            assert 'PASS T06' in (d/'run.log').read_text()
        return dict(scenes=5,scope='all Gaussian keys including depth-culled; module-only capacity proof')
    check('complete_model_QSU_BSU_order',order)
    def full():
        nonlocal performance
        from scripts.audit_t06_precount_full import main as full_audit
        full_audit();performance=read(FULL/'functional_performance_audit.json')
        assert len(performance['results'])==5 and not performance['pending_float']
        assert {x['scene'] for x in performance['results']}==set(profile()['scenes'])
        for x in performance['results']:
            verify_sources(x['source_sha256']);assert x['full_scene'] and x['saved_percent']>0
            c=x['production_measurements']['counters'];q=c['REAL_QSU'];b=c['REAL_SORT_WORK'];n=q['leaves']
            assert (b['shared'],b['local'],b['phases'],b['groups'])==(n,79*n,10*n,n)
            assert b['phase_grants']>0 and b['fallback']>0
        for root in ['experiments/t06_20261018/float_full','experiments/t06_full_f_20261019/float_refs']:
            r=read(ROOT/root/'report.json');assert r['status']=='REFERENCE_READY';verify_sources(r['source_sha256'])
        evidence[(FULL/'functional_performance_audit.json').relative_to(ROOT).as_posix()]=sha(FULL/'functional_performance_audit.json')
        return dict(scenes=5,scope='complete models, G/legacy ideal, width128; independent float semantics, not formal GT')
    check('complete_production_RGB_order_float_and_performance',full)
    def inputs():
        r=read(BASE/'input_encoding_report.json');assert r['status']=='PASS' and len(r['results'])==10
        assert {x['scene'] for x in r['results']}==set(profile()['scenes'])
        assert all(x['records_checked']>=14 and x['SH_fields_checked']>=14*48 for x in r['results'])
        report('experiments/t06_release_20261022/aux_report.json')
        return dict(field_layout_cases=10,rule=r['rule'])
    check('literal_PLY_layout_and_auxiliary_contracts',inputs)
    def visuals():
        r=read(BASE/'visual_review.json');assert set(r['reviewed_scenes'])==set(profile()['scenes'])
        for n,h in r['rgb_sha256'].items():assert sha(FULL/n/'H/frame.rgb')==h
        assert r['no_unexplained_uniform_frames'] and not r['formal_GT_signoff']
        return r
    check('actual_five_images_reviewed',visuals)
    def resource():
        r=read(BASE/'resource_decision.json');assert r['decision']=='ACCEPT_H_FUNCTIONAL_PROFILE_PPA_PENDING'
        assert r['additional_histogram_bits']==386912 and not r['whole_chip_PPA_pass']
        verify_sources(r['source_sha256']);return r
    check('bounded_resource_and_optimization_decision',resource)
    pending=[x for x in checks if x['status']!='PASS']
    state=read(ROOT/'verification/implementation_status.json')
    signed=not pending and state.get('t06_signed_off',False) and state.get('t06_audit_report')=='experiments/t06_release_20261022/audit.json'
    result=dict(status='COMPLETE_FUNCTIONAL' if not pending else 'INCOMPLETE_RELEASE',signed_off=signed,
      profile=profile(),profile_sha256=sha(PROFILE),checks=checks,pending_evidence=pending,evidence_sha256=evidence,
      full_model_autonomous_frames=5 if any(x['name']=='complete_production_RGB_order_float_and_performance' and x['status']=='PASS' for x in checks) else 0,
      full_model_rgb_oracle_matches=5 if performance is not None and not performance['pending_float'] else 0,
      performance=performance,limitations=['T06 functional scope only; not T00 30FPS/native-resolution/GT/PPA','Kitchen/Garden deferred for new tests, final 13-scene contract unchanged','Legacy ideal AXI includes mean/attribute beat bubbles and no common physical DDR bandwidth arbitration','Native full-order executable rejected by Windows; Icarus required; no security bypass'])
    save(BASE/'audit.json',result)
    for x in checks:print(x['status'],x['name'],x.get('error',''))
    return not pending
if __name__=='__main__':sys.exit(0 if main() else 1)
