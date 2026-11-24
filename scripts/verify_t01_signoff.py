"""Verify the frozen T01 acceptance index and prevent conflating it with PPA pass."""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.t01_resume_common import BASE, read, save, sha, frozen

def main():
    signed = read(BASE / 'signoff.json')
    state = read(ROOT / 'verification/implementation_status.json')
    assert signed['signed_off'] and state['t01_signed_off']
    assert signed['status'] == state['t01_status'] == 'COMPLETE'
    assert state['next_execution_task'] == state['next_functional_task'] == signed['next_task'] == 'T07'
    assert state['execution_resume_plan']['status'] == 'COMPLETE'
    assert not state['t01_blockers']
    before = read(BASE / 'closure_before/verification/implementation_status.json')
    allowed = {'planning_updated_at', 'next_execution_task', 'next_functional_task',
               'execution_resume_plan', 'development_environment_policy',
               'alpha_zero_skip_candidate_mapped_area_report'}
    for key, value in before.items():
        if not key.startswith('t01_') and key not in allowed:
            assert state[key] == value, ('unrelated status changed', key)
    for key in ['timing_200MHz_pass', 'electrical_closure', 'final_area_storage_power_pass', 'formal_GT_30FPS_pass']:
        assert signed[key] is False
    for key in ['ppa_signed_off', 'ground_truth_quality_signed_off', 't06_30fps_verified',
                't01_200mhz_verified', 't01_final_ppa_pass', 't01_electrical_closure']:
        assert state[key] is False
    issues = read(BASE / 'open_design_issues.json')['issues']
    assert len(issues) == 5 and all(i['status'] == 'OPEN' for i in issues)
    assert len(frozen()) == 89
    index = read(BASE / 'accepted_artifacts.json')
    failed = []
    for name, expected in index['files'].items():
        path = Path(name)
        if not path.is_file() or sha(path) != expected.upper():
            failed.append(name)
    assert not failed, ('accepted evidence mismatch', failed)
    for directory in ['source_snapshot', 'closure_snapshot']:
        for name, expected in read(BASE / directory / 'manifest.json').items():
            assert sha(BASE / directory / name) == expected.upper()
    assert sha(ROOT / signed['report']) == signed['report_sha256']
    assert sha(BASE / 'final_audit.json') == signed['final_audit_sha256']
    assert sha(BASE / 'fresh_float/audit.json') == signed['independent_reference_audit_sha256']
    # Mutable work documents must agree with this handoff at the moment of signoff verification.
    for name, expected in read(BASE / 'closure_snapshot/manifest.json').items():
        assert sha(ROOT / name) == expected.upper(), ('working file differs at handoff', name)
    report = dict(status='PASS', task='T01', signed_off=True, accepted_files=len(index['files']),
                  accepted_index_sha256=sha(BASE / 'accepted_artifacts.json'),
                  final_ppa_pass=False, open_design_issues=len(issues), next_task='T07',
                  verifier_sha256=sha(Path(__file__)), scope='Integrity and state consistency at handoff; not additional hardware validation')
    save(BASE / 'signoff_verification.json', report)
    print(report)

if __name__ == '__main__':
    main()
