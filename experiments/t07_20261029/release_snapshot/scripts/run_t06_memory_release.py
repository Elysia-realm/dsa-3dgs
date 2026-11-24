"""Resume T06 acceptance using disjoint, asserted physical DMA regions.

Inputs and independent references are reused byte-for-byte, never relabeled
as newly executed RTL. Each new RTL case has a fresh command/build/result.
"""
import argparse,json,os,shutil,sys,traceback
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t06_image_release as release
OLD=ROOT/'experiments/t06_20261017'
BASE=ROOT/'experiments/t06_20261018'
JOB=BASE/'jobs/memory_release'

def configure():
    release.BASE=BASE;release.FULL=BASE/'full_render';release.SUB=BASE/'subset'
    release.common.BENCH_TOP='tb_t06_memory_workload'
    release.common.SCRATCH_HEADER='verification/rtl/t06_memory_scratch.svh'
    release.common.EXTRA_SOURCES=['verification/rtl/t06_memory_layout.svh']
    release.production.EXECUTABLE=ROOT/'tmp/verilator_t06_pipe1_n7000000/t06_real.exe'
    release.production.PASS_MARKER='PASS: tb_t06_memory_workload'
    release.oracle.ORACLE_TOP='tb_t06_memory_oracle'
    release.oracle.PRODUCTION_MDIR='tmp/verilator_t06_pipe1_n7000000'
    release.oracle.ORACLE_MDIR='tmp/verilator_t06_memory_oracle'

def status(phase,**kw):
    JOB.mkdir(parents=True,exist_ok=True)
    p=JOB/'status.json';tmp=p.with_suffix('.pending')
    tmp.write_text(json.dumps(dict(status=phase,pid=os.getpid(),signed_off=False,**kw),indent=2),encoding='utf-8');tmp.replace(p)

def prepare():
    provenance={}
    for kind in ['full_render','subset']:
        for name in release.NAMES:
            src=OLD/kind/name;dest=BASE/kind/name;dest.mkdir(parents=True,exist_ok=True)
            for filename in ['manifest.json','mean.memh','attribute.memh','camera.memh','expected_sorted.txt']:
                a=src/filename;b=dest/filename
                if not b.exists():
                    if filename.endswith('.memh'):os.link(a,b) # immutable encoded input, no regeneration
                    else:shutil.copy2(a,b)
                assert release.common.sha(a)==release.common.sha(b)
                provenance[b.relative_to(BASE).as_posix()]={'from':a.relative_to(ROOT).as_posix(),'sha256':release.common.sha(a)}
    # Dependency-matched non-RTL references and units; new RTL cases are NOT copied.
    for kind in ['unit_checks','protocol','float_subset','float_full']:
        for a in (OLD/kind).rglob('*'):
            if a.is_file():
                b=BASE/a.relative_to(OLD);b.parent.mkdir(parents=True,exist_ok=True)
                if not b.exists():shutil.copy2(a,b)
                assert release.common.sha(a)==release.common.sha(b)
    release.save(BASE/'reused_input_provenance.json',provenance)
    release.verify_encoding()

def build():
    release.common.OUT=release.FULL
    release.common.build('verilator',1,7000000,16384)
    release.oracle.OUT=release.FULL;release.oracle.build()
    for kind in ['build','oracle_build']:
        (release.SUB/kind).mkdir(parents=True,exist_ok=True)
        for a in (release.FULL/kind).glob('*.json'):shutil.copy2(a,release.SUB/kind/a.name)

def check_layout_results(kind):
    report=release.read(BASE/kind/'report.json')
    for row in report['results']:
        n=row['scene'];subdir='production_v2' if kind=='full_render' else f'm{row["mode"]}_{row["profile"]}'
        p=BASE/kind/n/subdir
        assert 'disjoint=1' in (p/'run.log').read_text()
        assert (p/'frame.rgb').read_bytes()==(OLD/kind/n/subdir/'frame.rgb').read_bytes(),('address relocation changed image',n,subdir)
        assert 'disjoint=1' in (BASE/kind/n/'oracle/run.log').read_text()
    release.save(BASE/kind/'memory_layout_report.json',dict(status='PASS',cases=len(report['results']),
        address_ranges_disjoint=True,relocation_rgb_unchanged=True,source_sha256=release.common.sources()))

def main(action):
    configure()
    if action=='prepare':prepare();return
    if action=='build':build();return
    if action=='subset':release.subset();check_layout_results('subset');return
    if action=='full':release.full(4);check_layout_results('full_render');return
    status('PREPARING_IMMUTABLE_INPUTS');prepare()
    status('BUILDING_DISJOINT_ADDRESS_TESTS');build()
    status('RUNNING_SUBSET_MATRIX');release.subset();check_layout_results('subset')
    status('RUNNING_FULL_MODELS',subset_runs_passed=40)
    release.full(4);check_layout_results('full_render')
    status('TESTS_FINISHED_REVIEW_REQUIRED',subset_runs_passed=40,full_scenes_passed=5,
           next='Inspect actual RTL images; run source-bound gate and final audit. No automatic signoff.')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['prepare','build','subset','full','all']);a=p.parse_args()
    JOB.mkdir(parents=True,exist_ok=True)
    with (JOB/'worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main(a.action)
        except BaseException as e:
            status('FAILED_REVIEW_REQUIRED',error=repr(e),traceback=traceback.format_exc());traceback.print_exc();raise
