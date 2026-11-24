import json,os,re,subprocess
from pathlib import Path
ROOT=Path('/mnt/d/3DGS');BASE=ROOT/'experiments/environment_setup_20261024'
sta=Path.home()/'eda/opt/opensta/bin/sta'
old=json.loads((ROOT/'asic/reports/t01/toolchain_manifest.json').read_text())['libraries']
new=json.loads((BASE/'nangate_compatibility_audit.json').read_text())['libraries']
rows=[]
for i,lib in enumerate(old+new):
    env=os.environ.copy();env['GS_LIB_AUDIT_PATH']=str(ROOT/lib['path'])
    cmd=[str(sta),'-no_init','-exit',str(BASE/'library_read.tcl')]
    result=subprocess.run(cmd,env=env,capture_output=True,text=True)
    log=result.stdout+result.stderr
    logpath=BASE/f'logs/library-read-{i}.log';logpath.write_text(log)
    match=re.search(r'LIBRARY_READ_PASS cells=(\d+)',log)
    status='PASS' if result.returncode==0 and match and not re.search(r'^Error:',log,re.M) else 'FAIL'
    rows.append(dict(path=lib['path'],corner=lib['corner'],status=status,cells=int(match[1]) if match else None,exit_code=result.returncode,log=logpath.relative_to(ROOT).as_posix(),warnings=[line for line in log.splitlines() if 'Warning:' in line]))
(BASE/'library_read_report.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps(rows,indent=2))
assert all(r['status']=='PASS' for r in rows)
