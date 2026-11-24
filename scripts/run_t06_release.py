"""Fresh forty-case release run from the explicit selected production profile."""
import os,shutil,sys,traceback
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t06_release_common import BASE,OLD,PROFILE,configure,assert_command_profile,check_frozen_sources
from scripts.run_t06_perf_optimization import save

def main():
    p=configure();src=check_frozen_sources();cfg_hash=p.sha(PROFILE)
    p.save(BASE/'status.json',dict(status='BUILDING_RELEASE',pid=os.getpid(),signed_off=False))
    for n in p.SCENES:
        dest=p.DATA/n;dest.mkdir(parents=True,exist_ok=True)
        for f in ['manifest.json','camera.memh','mean.memh','attribute.memh','expected_sorted.txt','oracle/result.json','oracle/frame.rgb','oracle/frame.png']:
            target=dest/f;target.parent.mkdir(parents=True,exist_ok=True)
            if not target.exists():shutil.copy2(OLD/'subset'/n/f,target)
            assert p.sha(target)==p.sha(OLD/'subset'/n/f)
    p.build('H');config=assert_command_profile(p.read(BASE/'build/H/command.json'))
    assert_command_profile(p.read(OLD/'build/H/command.json'))
    p.save(BASE/'status.json',dict(status='RUNNING_RELEASE_40',pid=os.getpid(),signed_off=False))
    p.run(('H','bonsai',0,'ideal'))
    cases=[('H',n,m,a) for n in p.SCENES for m in range(4) for a in ['ideal','limited']]
    with ThreadPoolExecutor(max_workers=4) as pool:rows=list(pool.map(p.run,cases))
    for r in rows:
        n,m,a=r['scene'],r['mode'],r['profile'];old=p.read(OLD/'subset'/n/f'H_m{m}_{a}/result.json')
        assert r['command_cycles']==old['command_cycles'] and r['rgb_sha256']==old['rgb_sha256']
        assert r['counters']['REAL_QSU']['reads']==old['counters']['REAL_QSU']['reads']
    assert check_frozen_sources()==src and p.sha(PROFILE)==cfg_hash
    p.save(BASE/'real_report.json',dict(status='PASS',results=rows,profile_sha256=cfg_hash,
      effective_parameters=config,source_sha256=src,scope='40 fresh selected-profile production runs; complete-model evidence reused only with identical RTL/configuration and separately audited inputs'))
    p.save(BASE/'status.json',dict(status='RELEASE_REAL_PASS_PENDING_FINAL_GATE',signed_off=False))
if __name__=='__main__':
    BASE.mkdir(parents=True,exist_ok=True)
    with (BASE/'worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main()
        except BaseException as e:save(BASE/'status.json',dict(status='FAILED',error=repr(e),signed_off=False));traceback.print_exc();raise
