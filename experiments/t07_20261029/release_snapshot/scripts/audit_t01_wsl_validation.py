"""Fail-closed native production migration gate; this gate never signs off T01."""
import argparse,hashlib,json,math,re,sys
from pathlib import Path
from PIL import Image
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,PROFILE,OLD,FULL,read,save,sha,frozen
def verify_sources(m):
    assert m
    for f,h in m.items():assert sha(ROOT/f)==h.upper(),('source drift',f)
def effective(cmd):
    values={x[1:].split('=',1)[0]:x.split('=',1)[1] for x in cmd if x.startswith('+') and '=' in x}
    keys=['READ_LATENCY','READ_GAP','READY_PERIOD','READY_LOW','WRITE_RESPONSE_LATENCY']
    axi={k:int(values[k]) for k in keys if k in values}
    return values,axi
def check_row(path,kind):
    r=read(path/'result.json');assert r['status']=='PASS';verify_sources(r['source_sha256'])
    b=read(BASE/'build'/kind/'binary.json');assert sha(b['path'])==r['binary_sha256']==b['binary_sha256']
    for f,h in r['evidence_sha256'].items():assert sha(path/f)==h
    cmd=read(path/'run.command.json');assert cmd[0]==b['path'];v,axi=effective(cmd)
    log=(path/'run.log').read_text();assert 'PASS' in log and 'FATAL:' not in log
    if kind=='order':
        assert int(v['N'])==r['gaussians'];return r
    assert '+AUTO_QSU' in cmd and not any('ORACLE=' in x or 'BATCH_ROOT=' in x for x in cmd)
    assert 'error=00000000' in log and 'disjoint=1' in log
    assert r['counters']['REAL_RGB_BURST']['configured']==16 and r['counters']['REAL_ALPHA_SKIP']['enabled']==1
    raw=(path/'frame.rgb').read_bytes();assert raw==bytes(int(x,16) for x in (path/'rgb.memh').read_text().split())
    assert Image.open(path/'frame.png').tobytes()==raw and sha(path/'frame.rgb')==r['rgb_sha256']
    assert r['command_cycles']==r['counters']['REAL_END_TO_END']['command_cycles']
    wanted={'READ_LATENCY':8,'READ_GAP':2,'READY_PERIOD':4,'READY_LOW':1,'WRITE_RESPONSE_LATENCY':8} if kind=='repeat' or r['axi_profile']=='limited' else {'READ_LATENCY':0,'READ_GAP':0,'READY_PERIOD':1,'READY_LOW':0,'WRITE_RESPONSE_LATENCY':2}
    assert axi==wanted
    # Fix reporting labels from actual command, preserving the previous metadata.
    corrected=dict(r);corrected['initial_frame_mode']=int(v['FRAME_MODE']);corrected['axi_settings']=axi
    corrected['axi_profile']='limited' if wanted['READ_LATENCY'] else 'legacy_ideal'
    if kind=='repeat':corrected.update(mode=3,frame_modes=[3,0],frames=2)
    if corrected!=r:
        previous=path/'result_before_effective_labels.json'
        if not previous.exists():save(previous,r)
        save(path/'result.json',corrected)
    return corrected
def main():
    p=argparse.ArgumentParser();p.add_argument('--partial',action='store_true');a=p.parse_args()
    checks=[];allrows={};scenes=list(read(PROFILE)['scenes'])
    def check(name,fn):
        try:detail=fn();checks.append(dict(name=name,status='PASS',detail=detail))
        except Exception as e:checks.append(dict(name=name,status='MISSING' if isinstance(e,FileNotFoundError) else 'FAIL',error=repr(e)))
    check('production_source_profile',lambda:dict(files=len(frozen()),profile_sha256=sha(PROFILE)))
    def group(kind):
        paths=[BASE/'real/subset'/n/f'm{m}_{ax}' for n in scenes for m in range(4) for ax in ['ideal','limited']] if kind=='subset' else [BASE/'real'/kind/n for n in scenes]
        rows=[check_row(d,kind) for d in paths];allrows[kind]=rows
        if kind=='subset':assert len(rows)==40 and all(r['gaussians']==512 and not r['full_scene'] for r in rows)
        else:assert len(rows)==5
        if kind=='full':
            for r in rows:
                manifest=read(FULL/r['scene']/'manifest.json');assert r['gaussians']==manifest['gaussians'] and r['full_scene']
                assert r['independent_float_mae']<=5
        save(BASE/'real'/kind/'report.json',dict(status='PASS',kind=kind,source_sha256=frozen(),profile_sha256=sha(PROFILE),results=rows))
        return dict(runs=len(rows),scenes=5)
    for kind in ['subset','full','repeat','order']:check(kind,lambda kind=kind:group(kind))
    def legacy():
        r=read(BASE/'legacy_units/report.json');assert r['status']=='PASS' and r['compile_count']==84 and r['run_count']==83
        verify_sources(r['source_sha256']);return dict(compiles=84,runs=83)
    check('legacy_units',legacy)
    def selected():
        r=read(BASE/'selected_units/report.json');assert r['status']=='PASS' and len(r['groups'])==8;verify_sources(r['source_sha256'])
        for row in r['groups']:
            folder=BASE/'selected_units'/row['name'];report=folder/('native_report.json' if row['name']=='rgb_native' else 'report.json')
            assert sha(report)==row['report_sha256'];verify_sources(read(report)['source_sha256'])
        return dict(groups=8)
    check('selected_units',selected)
    def auxiliary():
        r=read(BASE/'aux/report.json');assert r['status']=='PASS';verify_sources(r['source_sha256']);return r['checks']
    check('independent_semantics_and_resource_ir',auxiliary)
    def alpha():
        r=read(BASE/'alpha_control/report.json');assert r['status']=='PASS' and len(r['results'])==5;verify_sources(r['source_sha256'])
        return {'same_condition_scenes':5,'sole_delta':r['sole_parameter_delta']}
    check('bounded_alpha_control',alpha)
    report=dict(status='PASS_MIGRATION_FUNCTIONAL_NOT_T01_SIGNOFF' if all(x['status']=='PASS' for x in checks) else 'INCOMPLETE',
      checks=checks,production_rtl_changed=False,source_sha256=frozen(),t01_signed_off=False,
      scope='WSL production migration through T06 at width128; no native/GT/30FPS, mapping, storage macro or STA signoff',results=allrows)
    save(BASE/'migration_audit.json',report)
    for c in checks:print(c['name'],c['status'],c.get('error',''),flush=True)
    if not a.partial:assert report['status'].startswith('PASS'),report['checks']
if __name__=='__main__':main()
