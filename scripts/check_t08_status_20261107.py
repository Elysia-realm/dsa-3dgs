"""Verify completed integration evidence and record an observed interrupted batch."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,read,save,sha

def main():
    reports=['integration_20261107/matrix_report.json','extended_20261107/repeat_report.json','mixed_20261107/report.json']
    checked=0
    for name in reports:
        report=read(BASE/name)
        for row in report['results']:
            if name.startswith('integration'):
                d=BASE/'integration_20261107/real'/row['scene']/f"m{row['mode']}_{row['axi']}_f{row['format']}"
            elif name.startswith('extended'):
                d=BASE/'extended_20261107/real/repeat'/row['scene']/f"f{row['format']}"
            else:d=BASE/'mixed_20261107/real'/row['scene']/f"m{row['mode']}_{row['axi']}_f{row['format']}"
            assert all(sha(ROOT/f)==h for f,h in row['source_sha256'].items())
            assert all(sha(d/f)==h for f,h in row['evidence_sha256'].items())
            checked+=1
    assert checked==95
    old=read(BASE/'extended_20261107/full_status.json')
    observation=BASE/'recovery_20261107/full_interruption_observation.json'
    if not observation.exists():
        save(observation,dict(previous_status=old,observation='No simulation or encoder process found; WSL instance newly started during status inspection. Two .partial encodings exist; no full-model result.json.',
             cause='not established',signed_off=False))
    save(BASE/'extended_20261107/full_status.json',dict(status='INTERRUPTED_DURING_INPUT_ENCODING',signed_off=False,
         observation=str(observation.relative_to(ROOT)),next_action='Verify and preserve partial files, then resume or regenerate encoded inputs; do not label RUNNING without a live process.'))
    save(BASE/'recovery_20261107/status_audit.json',dict(status='COMPLETED_EVIDENCE_VERIFIED',real_runs=checked,signed_off=False,
         reports={n:sha(BASE/n) for n in reports},full_model_status='INTERRUPTED_DURING_INPUT_ENCODING'))
    print('Verified 95 completed real subset/repeat/mixed runs; complete-model encoding interrupted')

if __name__=='__main__':main()
