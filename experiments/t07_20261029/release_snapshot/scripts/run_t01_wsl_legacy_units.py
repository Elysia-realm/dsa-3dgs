"""Replay only Icarus compile/run statements from the existing release unit list."""
import re,shlex,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,WORK,initialize,frozen,read,save,sha,run_logged

def main():
    initialize();dest=BASE/'legacy_units';out=WORK/'legacy_units';out.mkdir(parents=True,exist_ok=True)
    source=ROOT/'verification/rtl/run_iverilog.cmd';text=source.read_text().replace('^\n',' ')
    source_hashes={p.relative_to(ROOT).as_posix():sha(p) for root in [ROOT/'rtl',ROOT/'verification/rtl'] for p in root.rglob('*') if p.suffix in ('.sv','.svh','.f','.cmd')}
    commands=[]
    for line in text.splitlines():
        line=line.strip()
        if not line.startswith(('"%IVERILOG%"','"%VVP%"')):continue
        line=line.replace('%IVERILOG%','/usr/bin/iverilog').replace('%VVP%','/usr/bin/vvp').replace('%REPO_ROOT%',str(ROOT)).replace('%OUT_DIR%',str(out)).replace('%~dp0',str(ROOT/'verification/rtl')+'/').replace('\\','/')
        args=shlex.split(line)
        args=[str(out/x.removeprefix('tmp/iverilog/')) if x.startswith('tmp/iverilog/') else x for x in args]
        assert args[0] in ('/usr/bin/iverilog','/usr/bin/vvp')
        commands.append(args)
    save(dest/'commands.json',commands);save(dest/'sources.json',source_hashes)
    save(dest/'status.json',dict(status='RUNNING',commands=len(commands)))
    results=[]
    for i,cmd in enumerate(commands):
        log=dest/f'{i:03d}.log';attempt=1
        while log.with_suffix('.execution.json').exists():
            prior=read(log.with_suffix('.execution.json'))
            if prior['exit_code']==0 and read(log.with_suffix('.command.json'))==cmd:
                assert prior['log_sha256']==sha(log);break
            attempt+=1;log=dest/f'{i:03d}_attempt{attempt}.log'
        else:run_logged(cmd,log)
        if cmd[0].endswith('/vvp'):
            result=log.read_text();assert 'PASS' in result and 'FATAL:' not in result,(i,cmd,result[-1500:])
        results.append(dict(index=i,status='PASS',command=cmd,log_sha256=sha(log)))
        save(dest/'status.json',dict(status='RUNNING',completed=i+1,total=len(commands)))
        print('UNIT',i+1,'/',len(commands),flush=True)
    assert all(sha(ROOT/f)==h for f,h in source_hashes.items())
    save(dest/'report.json',dict(status='PASS',source_sha256=source_hashes,compile_count=sum(c[0].endswith('/iverilog') for c in commands),run_count=sum(c[0].endswith('/vvp') for c in commands),results=results))
    save(dest/'status.json',dict(status='PASS',completed=len(commands)))
if __name__=='__main__':main()
