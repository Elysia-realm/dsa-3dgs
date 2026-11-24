"""Serial, resumable physical-flow queue. Generates evidence, never signoff."""
import argparse,json,os,subprocess,sys,time,traceback
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,read,save,sha,frozen
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--wait-current-alpha1-nangate',action='store_true');args=ap.parse_args()
    logdir=BASE/'physical_queue';logdir.mkdir(parents=True,exist_ok=True)
    def status(stage,**kw):save(logdir/'status.json',dict(stage=stage,pid=os.getpid(),signed_off=False,**kw))
    def call(label,cmd):
        frozen();status(label,state='RUNNING');print('START',label,flush=True)
        save(logdir/f'{label}.command.json',cmd)
        with (logdir/f'{label}.log').open('a') as log:r=subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
        assert r.returncode==0,(label,r.returncode,str(logdir/f'{label}.log'))
        frozen();print('DONE',label,flush=True)
    if args.wait_current_alpha1_nangate:
        marker=BASE/'synthesis/alpha1/nangate45/mapping.json';status('WAIT_CURRENT_ALPHA1_NANGATE',state='WAITING')
        while not marker.exists():
            active=False
            for p in Path('/proc').glob('[0-9]*/cmdline'):
                try:cmd=p.read_bytes().decode().split('\0')
                except (OSError,UnicodeError):continue
                if any(x.endswith('run_t01_wsl_synthesis.py') for x in cmd) and 'map' in cmd and 'nangate45' in cmd:active=True
            if not active:raise RuntimeError('Current mapping process ended without a completed mapping marker')
            time.sleep(5)
    for alpha in [1,0]:
        base=BASE/'synthesis'/f'alpha{alpha}';premap=base/'premap.json'
        if premap.exists():
            m=read(premap);assert sha(m['artifact'])==m['artifact_sha256']
        else:call(f'alpha{alpha}_premap',[sys.executable,'asic/scripts/run_t01_wsl_synthesis.py','premap','--alpha',str(alpha)])
        for pdk in ['nangate45','icsprout55']:
            d=base/pdk;label=f'alpha{alpha}_{pdk}'
            if (d/'mapping.json').exists():
                m=read(d/'mapping.json');assert sha(d/'gs_accel_system_top_mapped.v')==m['netlist_sha256']
            else:call(label+'_map',[sys.executable,'asic/scripts/run_t01_wsl_synthesis.py','map','--alpha',str(alpha),'--pdk',pdk])
            call(label+'_area_audit',[sys.executable,'asic/scripts/audit_t01_wsl_mapping.py','--alpha',str(alpha),'--pdk',pdk])
            call(label+'_sta',[sys.executable,'asic/scripts/run_t01_wsl_sta.py','--alpha',str(alpha),'--pdk',pdk])
            sta=read(d/'sta_result.json');assert sta['coverage_ok'],(label,'STA coverage incomplete',sta['coverage_output'])
    status('ALL_FOUR_REPORTS_READY_FOR_REVIEW',state='COMPLETE_PENDING_REVIEW')
if __name__=='__main__':
    try:main()
    except BaseException as e:
        save(BASE/'physical_queue/status.json',dict(state='FAILED',error=repr(e),signed_off=False,pid=os.getpid()))
        traceback.print_exc();raise
