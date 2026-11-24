"""One-shot, independent local test supervisor. Never signs off or schedules AI.

Launch with PowerShell Start-Process -WindowStyle Hidden so terminal/chat
interruption does not own this worker's normal lifetime. It runs only missing
T06 full-model tests, preserves logs, and leaves final review to the assistant.
"""
import ctypes,datetime,json,os,shutil,subprocess,sys,time,traceback
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t06_real as base
BASE=ROOT/'experiments/t06_20261014';OUT=BASE/'jobs/background_20261016'
SCENES=base.SCENES
def stamp():return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
def save(name,data):
    p=OUT/name;temp=p.with_suffix('.pending');temp.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8');temp.replace(p)
def open_process(pid):
    # Holding a process HANDLE, not periodically resolving its PID, avoids PID
    # reuse mistakes. Read-only query access; this supervisor never kills jobs.
    api=ctypes.windll.kernel32
    api.OpenProcess.restype=ctypes.c_void_p
    return api.OpenProcess(0x1000,False,int(pid))
def alive(handle):
    if not handle:return False
    code=ctypes.c_ulong()
    ok=ctypes.windll.kernel32.GetExitCodeProcess(ctypes.c_void_p(handle),ctypes.byref(code))
    return bool(ok and code.value==259)
def close(handle):
    if handle:ctypes.windll.kernel32.CloseHandle(ctypes.c_void_p(handle))
def run_job(case):
    kind,scene=case;script='run_t06_full_render.py' if kind=='production' else 'run_t06_oracle_render.py'
    command=[sys.executable,str(ROOT/'scripts'/script),'run','--scenes',scene,'--workers','1']
    label=f'{kind}_{scene}';status={'status':'RUNNING','kind':kind,'scene':scene,'command':command,'started_at':stamp()}
    result_folder=BASE/'full_render'/scene/('production_v2' if kind=='production' else 'oracle')
    adopt=json.loads((OUT/'adopt.json').read_text()).get(label,[]) if (OUT/'adopt.json').exists() else []
    handles=[open_process(pid) for pid in adopt]
    if any(alive(h) for h in handles):
        status.update(status='ADOPTED_RUNNING',adopted_pids=adopt);save(f'{label}.json',status)
        while any(alive(h) for h in handles) and not (result_folder/'result.json').exists():time.sleep(15)
    for handle in handles:close(handle)
    if (result_folder/'result.json').exists():
        status.update(status='PASS_EXISTING_RESULT',returncode=0,finished_at=stamp());save(f'{label}.json',status);return status
    prior_log=(result_folder/'run.log').read_text(errors='replace') if (result_folder/'run.log').exists() else ''
    marker='PASS: tb_real_dma_workload' if kind=='production' else 'PASS: tb_t06_oracle_render'
    if marker in prior_log:
        command.append('--collect-only')  # full normal validation still executes
    elif 'FATAL' in prior_log or 'Assertion failed' in prior_log:
        raise RuntimeError(label+': real test failure retained; refusing to hide it with an automatic retry')
    else:
        # Interrupted tests lack a PASS marker and must really rerun. Preserve
        # their incomplete artifacts before the ordinary runner opens outputs.
        prior=OUT/(label+'_interrupted');prior.mkdir(exist_ok=True)
        for name in ['command.json','progress.json','run.log','sorted.txt']:
            src=result_folder/name
            if src.exists():shutil.copy2(src,prior/name)
    status.update(status='RUNNING',command=command)
    with (OUT/f'{label}.log').open('w') as log:
        proc=subprocess.Popen(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
        status['pid']=proc.pid;save(f'{label}.json',status)
        rc=proc.wait()
    status.update(status='PASS_TEST_COMMAND' if rc==0 else 'FAILED_TEST_COMMAND',returncode=rc,finished_at=stamp())
    save(f'{label}.json',status);return status
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    frozen=base.sources();save('supervisor.json',{'status':'RUNNING','pid':os.getpid(),'started_at':stamp(),'source_sha256':frozen,
        'policy':'one-shot missing tests only; no automatic signoff, no recurring automation, no external messages'})
    jobs=[]
    for scene in SCENES:
        for kind,folder in [('production','production_v2'),('oracle','oracle')]:
            p=BASE/'full_render'/scene/folder/'result.json'
            if p.exists():
                r=json.loads(p.read_text());assert r['status'] in ['PASS_DATAPATH_PENDING_IMAGE_ORACLE','PASS_ORACLE','PASS'],str(p)
                if kind=='production':assert r['source_sha256']==frozen,'completed result is not current '+str(p)
            else:jobs.append((kind,scene))
    save('planned_jobs.json',{'jobs':jobs,'source_sha256':frozen,'started_at':stamp()})
    with ThreadPoolExecutor(max_workers=4) as pool:results=list(pool.map(run_job,jobs))
    if any(r['returncode']!=0 for r in results):raise RuntimeError('A full-model test failed; inspect per-job logs')
    assert base.sources()==frozen,'RTL/TB changed while background tests ran; final evidence must be reviewed'
    command=[sys.executable,str(ROOT/'scripts/audit_t06.py')]
    with (OUT/'audit.log').open('w') as log:r=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    assert r.returncode==0,'audit validation failed'
    audit=json.loads((BASE/'audit.json').read_text(encoding='utf-8'))
    assert audit['full_model_autonomous_frames']==5 and audit['full_model_rgb_oracle_matches']==5
    save('supervisor.json',{'status':'TESTS_FINISHED_REVIEW_REQUIRED','pid':os.getpid(),'finished_at':stamp(),
        'full_model_autonomous_frames':5,'full_model_rgb_oracle_matches':5,'signed_off':False,
        'next':'View all five current PNGs, run verification/run_t06.ps1 -EvidenceOnly, complete audit/archive and signoff only if all gates pass'})
if __name__=='__main__':
    try:main()
    except BaseException as e:
        OUT.mkdir(parents=True,exist_ok=True);save('supervisor.json',{'status':'FAILED_REVIEW_REQUIRED','pid':os.getpid(),'finished_at':stamp(),'error':repr(e),'traceback':traceback.format_exc(),'signed_off':False});raise
