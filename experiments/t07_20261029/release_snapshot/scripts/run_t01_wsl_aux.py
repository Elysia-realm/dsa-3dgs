"""Independent semantics, metadata, production lint and resource IR checks in WSL."""
import importlib,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,PROFILE,read,save,sha,frozen,initialize,run_logged
SUITE=Path.home()/'eda/opt/oss-cad-suite-20260706/oss-cad-suite'
def main():
    initialize();out=BASE/'aux';out.mkdir(parents=True,exist_ok=True);cfg=read(PROFILE)
    cmd=[sys.executable,'-m','unittest','verification.test_t06_projection_reference','verification.test_scene_io',
      'verification.test_t05_parallel_evidence','verification.test_implementation_status','-v']
    run_logged(cmd,out/'python_checks.log')
    lint=[str(SUITE/'bin/verilator'),'--lint-only','--sv','--timing','-DSYNTHESIS','-Wno-fatal','-Irtl/raster',
      '--top-module','gs_accel_system_top',*[f'-G{k}={v}' for k,v in cfg['parameters'].items()],'-f','verification/rtl/system_top_sources.f']
    run_logged(lint,out/'production_lint.log')
    text=(out/'production_lint.log').read_text()
    assert not any(x in text for x in ['%Error','%Warning-LATCH','%Warning-UNOPTFLAT','%Warning-MULTIDRIVEN'])
    for name in ['check_t06_precount_synthesis','check_t06_dot3_resources']:
        m=importlib.import_module('scripts.'+name);m.OUT=out/name;m.YOSYS=SUITE/'bin/yosys';m.main()
    sources={f:sha(ROOT/f) for f in ['model/io/scene.py','model/reference/math3d.py','scripts/run_t01_wsl_aux.py',
      'verification/test_t06_projection_reference.py','verification/test_scene_io.py','verification/test_implementation_status.py']}
    save(out/'report.json',dict(status='PASS',source_sha256=sources,production_source_sha256=frozen(),profile_sha256=sha(PROFILE),
      checks=['independent_projection_and_scene_fields','historical_evidence_and_current_status','production_profile_lint','qsu_histogram_memory_ports','dot3_resource_widths']))
if __name__=='__main__':main()
