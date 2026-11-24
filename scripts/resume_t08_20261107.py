"""Read-only native evidence audit and pre-integration source snapshot."""
import shutil,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,SCENES,read,save,sha

def main():
    out=BASE/'recovery_20261107';out.mkdir(parents=True,exist_ok=True)
    info=read(BASE/'build/native/binary.json')
    assert sha(Path(info['path']))==info['binary_sha256']
    snapshot=out/'production_before'
    for f,h in info['source_sha256'].items():
        assert sha(ROOT/f)==h,('baseline drift before integration',f)
        p=snapshot/f;p.parent.mkdir(parents=True,exist_ok=True)
        if p.exists():assert sha(p)==h
        else:shutil.copy2(ROOT/f,p)
    save(snapshot/'manifest.json',info['source_sha256'])
    rows=[]
    for s in SCENES:
        d=BASE/'diagnostic/native'/s;launch=read(d/'launch.json');execution=read(d/'run.execution.json')
        assert launch['source_sha256']==info['source_sha256'] and launch['binary_sha256']==info['binary_sha256']
        assert execution['log_sha256']==sha(d/'run.log')
        row=dict(scene=s,status=read(d/'status.json')['status'],log_sha256=sha(d/'run.log'),execution=execution)
        if (d/'result.json').exists():
            result=read(d/'result.json')
            assert all(sha(d/f)==h for f,h in result['evidence_sha256'].items())
            row.update(command_cycles=result['command_cycles'],assumed_200MHz_FPS=200000000/result['command_cycles'],
                       independent_reference_pass=False,GT_pass=False)
        else:
            assert execution['exit_code']!=0 and 'real workload timed out' in (d/'run.log').read_text()
            row.update(status='TIMEOUT_2_BILLION_CYCLES',complete_frame=False)
        rows.append(row);print(s,row['status'],row.get('command_cycles'),flush=True)
    save(out/'native_audit.json',dict(status='EVIDENCE_AUDITED_NOT_ACCEPTED',results=rows,signed_off=False,
         source_manifest_sha256=sha(snapshot/'manifest.json')))
    for f in ['verification/implementation_status.json','verification/physical_risk_register.json']:
        p=out/'context_before'/f;p.parent.mkdir(parents=True,exist_ok=True)
        if not p.exists():shutil.copy2(ROOT/f,p)

if __name__=='__main__':main()
