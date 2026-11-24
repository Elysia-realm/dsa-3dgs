"""Paths and provenance for the bounded 2026-10-25 WSL T01 recovery."""
import hashlib,json,os,shlex,shutil,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'experiments/t01_resume_20261025'
WORK=Path.home()/'work/t01_resume_20261025'
PROFILE=ROOT/'verification/t06_release_profile.json'
OLD=ROOT/'experiments/t06_release_20261022'
FULL=ROOT/'experiments/t06_full_precount_mem_20261022'
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def save(p,x):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True)
    temp=p.with_name(p.name+'.tmp');temp.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');temp.replace(p)
def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest().upper()
def frozen():
    cfg=read(PROFILE);m=read(ROOT/cfg['frozen_source_manifest'])
    for f,h in m.items():assert sha(ROOT/f)==h.upper(),('source drift',f)
    return m
def run_logged(cmd,log,cwd=ROOT,timeout=None,env=None):
    log=Path(log);log.parent.mkdir(parents=True,exist_ok=True)
    if log.exists():
        attempt=1
        while log.with_name(log.stem+f'.attempt{attempt}'+log.suffix).exists():attempt+=1
        for suffix in [log.suffix,'.command.json','.execution.json']:
            old=log.with_suffix(suffix)
            if old.exists():shutil.copy2(old,old.with_name(log.stem+f'.attempt{attempt}'+suffix))
    save(log.with_suffix('.command.json'),cmd)
    started=time.monotonic()
    with log.open('w') as out:
        r=subprocess.run(['/usr/bin/time','-v',*map(str,cmd)],cwd=cwd,stdout=out,stderr=subprocess.STDOUT,timeout=timeout,env=env)
    result=dict(exit_code=r.returncode,wall_seconds=time.monotonic()-started,log_sha256=sha(log))
    save(log.with_suffix('.execution.json'),result)
    assert r.returncode==0,(cmd,str(log),log.read_text(errors='replace')[-2500:])
    return result
def initialize():
    assert os.name=='posix' and ROOT.as_posix()=='/mnt/d/3DGS','Run with WSL native Python at authoritative project root'
    BASE.mkdir(parents=True,exist_ok=True);WORK.mkdir(parents=True,exist_ok=True)
    m=frozen()
    out=BASE/'frozen_source_manifest.json'
    if out.exists():assert read(out)==m
    else:save(out,m)
    config=BASE/'production_profile.json'
    if config.exists():assert read(config)==read(PROFILE)
    else:save(config,read(PROFILE))
    return m
