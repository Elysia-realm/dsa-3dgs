"""Reuse existing self-checking test logic with explicit native-Linux subprocess adapters."""
import importlib,os,resource,subprocess,sys,time,types
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,WORK,initialize,frozen,read,save,sha

def main():
    initialize();groups=[('qsu','check_t06_qsu_precount',()),('faults','check_t06_precount_faults',()),
      ('recovery','check_t06_precount_recovery',()),('rgb','check_t06_rgb_burst',()),
      ('rgb_native','check_t06_rgb_burst',(True,)),('protocol','run_t06_protocol_tests',()),
      ('addresses','check_t06_memory_layout',()),('dot3','check_t06_dot3_adapters',())]
    total=[]
    for name,module,args in groups:
        folder=BASE/'selected_units'/name;folder.mkdir(parents=True,exist_ok=True)
        if (folder/'linux_runner_report.json').exists():
            prior=read(folder/'linux_runner_report.json')
            assert prior['status']=='PASS' and prior['driver_sha256']==sha(ROOT/f'scripts/{module}.py')
            total.append(prior);continue
        records=[];m=importlib.import_module('scripts.'+module);m.OUT=folder
        for key,tool in [('IVER','/usr/bin/iverilog'),('VVP','/usr/bin/vvp')]:
            if hasattr(m,key):setattr(m,key,tool)
        def native_run(cmd,**kw):
            cmd=[str(x) for x in cmd]
            if cmd[0].replace('\\','/').endswith('/iverilog.exe'):cmd[0]='/usr/bin/iverilog'
            elif cmd[0].replace('\\','/').endswith('/vvp.exe'):cmd[0]='/usr/bin/vvp'
            assert cmd[0] in ('/usr/bin/iverilog','/usr/bin/vvp'),cmd
            cmd=[x.replace('\\','/').replace('D:/3DGS','/mnt/d/3DGS') for x in cmd]
            before=resource.getrusage(resource.RUSAGE_CHILDREN);start=time.monotonic()
            result=subprocess.run(cmd,**kw)
            after=resource.getrusage(resource.RUSAGE_CHILDREN)
            records.append(dict(command=cmd,exit_code=result.returncode,wall_seconds=time.monotonic()-start,
              child_cpu_seconds=(after.ru_utime+after.ru_stime)-(before.ru_utime+before.ru_stime),
              binary_sha256=sha(cmd[1]) if cmd[0].endswith('/vvp') else None,
              vector_sha256={x.split('=',1)[1]:sha(x.split('=',1)[1]) for x in cmd if x.startswith(('+INPUT=','+EXPECTED='))}))
            save(folder/'linux_commands.json',records)
            return result
        m.subprocess=types.SimpleNamespace(run=native_run)
        save(BASE/'selected_units/status.json',dict(status='RUNNING',group=name))
        m.main(*args)
        row=dict(name=name,status='PASS',driver_sha256=sha(ROOT/f'scripts/{module}.py'),calls=len(records),
          report_sha256=sha(folder/('native_report.json' if name=='rgb_native' else 'report.json')))
        save(folder/'linux_runner_report.json',row);total.append(row);frozen()
    save(BASE/'selected_units/report.json',dict(status='PASS',source_sha256=frozen(),groups=total))
    save(BASE/'selected_units/status.json',dict(status='PASS',groups=len(total)))
if __name__=='__main__':main()
