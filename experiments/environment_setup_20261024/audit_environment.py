"""Audit saved environment evidence; does not sign off accelerator behavior."""
import hashlib,json,math,re,subprocess
from pathlib import Path
BASE=Path('/mnt/d/3DGS/experiments/environment_setup_20261024');ROOT=BASE.parents[1]
def read(p):return (BASE/p).read_text(encoding='utf-8-sig')
def data(p):return json.loads(read(p))
log=read('smoke-v2/sta-smoke.log')
ann=int(re.search(r'Annotated (\d+) pin activities',log)[1])
assert ann>0 and 'Startpoint:' in log and 'Path Type: max' in log and 'Path Type: min' in log
assert not re.search(r'^Error:',log,re.M)
slacks={k:float(re.search(r'worst slack '+k+r'\s+([-\d.]+)',log)[1]) for k in ['max','min']}
for k in ['iverilog','verilator']:assert 'ENV_SIM_PASS' in read(f'smoke-v2/{k}-run.log')
assert '# TOTAL: 30' in read('logs/cudd-check.log') and '# PASS:  30' in read('logs/cudd-check.log')
libs=data('library_read_report.json');assert len(libs)==7 and all(r['status']=='PASS' and not r['warnings'] for r in libs)
assert data('nangate_compatibility_audit.json')['status']=='PASS'
cacti=data('cacti_diagnostic_report.json');assert cacti['status']=='PASS_SRAM_TOOL_DIAGNOSTIC_ONLY'
assert 'Invalid -tflight_value' in read('logs/cacti-invalid-config.log')
stats=read('logs/ramulator-lpddr4.stats')
ram={}
for k in ['dram_cycles','incoming_requests','read_requests','write_requests']:
    ram[k]=int(re.search(r'^\s*ramulator\.'+k+r'\s+(\d+)',stats,re.M)[1])
assert ram['dram_cycles']>0 and ram['incoming_requests']==5 and ram['read_requests']==3 and ram['write_requests']==2
ram['read_bytes']=sum(map(int,re.findall(r'^\s*ramulator\.read_transaction_bytes_\d+\s+(\d+)',stats,re.M)))
ram['write_bytes']=sum(map(int,re.findall(r'^\s*ramulator\.write_transaction_bytes_\d+\s+(\d+)',stats,re.M)))
assert ram['read_bytes']==192 and ram['write_bytes']==128
resource={}
for key,cmd in [('memory',['free','-h']),('cpus',['nproc']),('kernel',['uname','-r'])]:
    result=subprocess.run(cmd,capture_output=True,text=True);assert result.returncode==0;resource[key]=result.stdout.strip()
assert resource['cpus']=='10'
backup=data('wsl_backup_manifest.json');backup_check=data('wsl_backup_verification.json')
assert backup['export_exit_code']==0 and backup_check['status']=='PASS_TAR_STRUCTURE_AND_CRITICAL_PAYLOAD_HASHES'
assert len(backup_check['verified_payloads'])==12
events=data('windows_code_integrity_events.json');assert any(e['Id']==3077 for e in events)
report=dict(date='2026-10-24',status='LINUX_TOOLCHAIN_READY_WINDOWS_EXECUTION_POLICY_BLOCKED',
 checks=dict(wsl2_ubuntu24=True,linux_dependencies=True,python_venv=True,cudd_tests_30_of_30=True,iverilog_smoke=True,verilator_smoke=True,opensta_liberty_timing_activity_smoke=True,all_seven_libraries_read=True,nangate_three_corner_compatibility=True,cacti_sram_diagnostic_and_invalid_config_rejection=True,ramulator_lpddr4_example=True),
 sta_smoke=dict(annotated_pins=ann,slack_ns=slacks,fixture_has_hold_violations=True,meaning='STA engine/constraint/report diagnostic only; fixture has no hold delay insertion. Not accelerator timing signoff.'),
 ramulator=ram,cacti=cacti,resources=resource,backup=dict(path=backup['path'],sha256=backup['sha256'],bytes=backup['bytes'],verified_payloads=12,boot_restore_test_executed=False),
 windows=dict(python_package_installed=True,execution_verified=False,blocker='Windows application control blocks MSYS2 cygpath and Python execution; no policy changes or bypass attempted'),
 not_executed=['production-top STA','current production RTL remapping','cache/SRAM timing boundary model','AXI-Ramulator closed-loop integration','real-scene/native-resolution/GT/30FPS acceptance','production activity-power/whole-chip PPA'],
 historical_failures_preserved=['WSL GitHub clone transport failure; official HTTPS archives used','Windows application-control block','Ramulator clang++ absent, then GCC missing transitive cstdint; explicit compiler/header flags resolve','initial VCD scope annotated 0; Icarus/Verilator traces now separated, 11 activities annotated','upstream CACTI missing IO configuration parsing; local parser repair and explicit DDR3 diagnostic config resolve; LPDDR2 MemCAD assertion attempt retained'],
 production_rtl_changed=False,t01_signed_off=False)
(BASE/'environment_audit.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
hashes={}
for p in sorted(BASE.rglob('*')):
    if p.is_file() and p.name!='evidence_sha256.json':hashes[p.relative_to(BASE).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
(BASE/'evidence_sha256.json').write_text(json.dumps(hashes,indent=2)+'\n')
print(json.dumps(report,indent=2,ensure_ascii=False))
