"""Current legacy/error compatibility and independent input-field audit."""
import json,subprocess,sys,traceback
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t06_release_common import BASE,profile
from scripts.run_t06_perf_optimization import save,sha

def main():
    from scripts import run_t06_protocol_tests as protocol
    protocol.OUT=BASE/'protocol';protocol.main()
    from scripts import run_t06_image_release as encoding
    encoding.BASE=BASE;encoding.FULL=ROOT/'experiments/t06_full_precount_mem_20261022'
    encoding.SUB=BASE/'subset';encoding.NAMES=list(profile()['scenes']);encoding.verify_encoding()
    cmd=[sys.executable,'-m','unittest','verification.test_t06_projection_reference','verification.test_scene_io','verification.test_t05_parallel_evidence','verification.test_implementation_status','-v']
    save(BASE/'aux_command.json',cmd)
    with (BASE/'aux_python.log').open('w') as log:r=subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    assert r.returncode==0,(BASE/'aux_python.log').read_text()[-2500:]
    save(BASE/'aux_report.json',dict(status='PASS',source_sha256={f:sha(ROOT/f) for f in ['scripts/run_t06_image_release.py','model/io/scene.py','model/reference/math3d.py','verification/test_t06_projection_reference.py','verification/test_scene_io.py']},
      protocol_report='protocol/report.json',encoding_report='input_encoding_report.json',python_log_sha256=sha(BASE/'aux_python.log')))
if __name__=='__main__':
    BASE.mkdir(parents=True,exist_ok=True)
    with (BASE/'aux_worker.log').open('a',encoding='utf-8',buffering=1) as log:
        sys.stdout=log;sys.stderr=log
        try:main()
        except BaseException:traceback.print_exc();raise
