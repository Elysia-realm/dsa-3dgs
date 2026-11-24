"""Audit finished failures and live progress separately; never signs off T08."""
import re
import sys
from datetime import datetime,timezone,timedelta
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,T07,SCENES,read,save,sha


def fields(line):
    return {k:int(v) for k,v in re.findall(r'(\w+)=([0-9]+)',line)}


def main():
    binary=read(BASE/'build/native/binary.json')
    for f,digest in binary['source_sha256'].items():assert sha(ROOT/f)==digest
    assert sha(Path(binary['path']))==binary['binary_sha256']
    rows=[]
    for scene in SCENES:
        d=BASE/'diagnostic/native'/scene
        status=read(d/'status.json') if (d/'status.json').exists() else dict(status='NOT_STARTED')
        row=dict(scene=scene,status=status['status'],signed_off=False)
        if (d/'launch.json').exists():
            launch=read(d/'launch.json')
            assert launch['source_sha256']==binary['source_sha256'] and launch['binary_sha256']==binary['binary_sha256']
            row.update(width=launch['width'],height=launch['height'],launch_sha256=sha(d/'launch.json'))
        if (d/'run.log').exists():
            text=(d/'run.log').read_text(errors='replace')
            progress=[fields(line) for line in text.splitlines() if line.startswith('T08_PROGRESS ')]
            row['last_observed_progress']=progress[-1] if progress else None
            row['progress_observation_only_not_frame_result']=True
            if status['status']=='FAILED':
                execution=read(d/'run.execution.json')
                assert execution['log_sha256']==sha(d/'run.log') and execution['exit_code']!=0
                timed=[fields(line) for line in text.splitlines() if line.startswith('TIMEOUT perf ')]
                assert len(timed)==1 and 'real workload timed out' in text and progress[-1]['cycles']==2000000000
                assert len(progress)>=2 and progress[-1]['attribute_beats']>progress[-2]['attribute_beats']
                row['failure_class']='FRAME_INCOMPLETE_AT_CYCLE_LIMIT'
                row['not_evidence_of_deadlock']='progress continued through final observation; no claim of complete correctness'
                row['timeout_counters']=timed[0]
                row['partial_state_transfer_bytes']=16*(timed[0]['reads']+timed[0]['writes'])
                row['partial_state_GBps_needed_at_30FPS']=row['partial_state_transfer_bytes']*30/1e9
                row['state_reads_per_commit']=timed[0]['reads']/timed[0]['commits']
                row['assumed_200MHz_FPS_strict_upper_bound']=0.1
                row['cycle_gap_to_30FPS_strict_lower_bound']=300
                row['frequency_verified']=False
                row['execution']=execution
                # Verify every saved ordered record. Buffered tail may be absent
                # at abort, so this establishes only a saved prefix, never all N.
                prefix=0
                with (d/'sorted.txt').open() as got,(T07/'real/full/C'/scene/'sorted.txt').open() as expected:
                    for line in got:
                        assert line==expected.readline(),('saved order prefix mismatch',scene,prefix)
                        prefix+=1
                row['saved_sorted_prefix_matches']=prefix
                row['immutable_failure_files']={p.name:sha(p) for p in d.iterdir() if p.is_file()}
        rows.append(row)
    for name in ['precompute_units_20261101','codec_units_20261101']:
        report=read(BASE/name/'report.json')
        for f,digest in report['source_sha256'].items():assert sha(ROOT/f)==digest
    report=dict(observed_at=datetime.now(timezone(timedelta(hours=8))).isoformat(),
        status='IN_PROGRESS_WITH_TWO_NATIVE_TIMEOUTS',signed_off=False,production_source_unchanged=True,
        native_results=rows,precompute=read(BASE/'precompute_units_20261101/report.json')['status'],
        decoder=read(BASE/'codec_units_20261101/report.json')['status'],
        compressed_DMA_integrated=False,compressed_production_render_validated=False,
        baseline_build_manifest_sha256=sha(BASE/'build/native/binary.json'))
    save(BASE/'recovery_20261101/checkpoint.json',report)
    for row in rows:print(row['scene'],row['status'],row.get('partial_state_GBps_needed_at_30FPS'),flush=True)


if __name__=='__main__':main()
