"""Current-source default-compatible regressions in new WSL evidence paths."""
import sys,importlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,WORK,production_sources,save,read,sha,run_logged,PROFILE

def main():
    compare_dma='--early-advance' in sys.argv
    folder='regressions_early_advance_20261120' if compare_dma else 'regressions_20261107'
    dest=BASE/folder;work=WORK/folder
    dest.mkdir(parents=True,exist_ok=True);work.mkdir(parents=True,exist_ok=True)
    m=importlib.import_module('scripts.run_t01_wsl_legacy_units')
    m.BASE=dest;m.WORK=work;m.initialize=lambda:None;m.frozen=production_sources;m.main()
    cfg=read(PROFILE)
    v=read(BASE/'build/native/binary.json')['command'][0]
    for enabled,early in ([(0,0),(1,0),(1,1)] if compare_dma else [(0,0),(1,0)]):
        parameters={**cfg['parameters'],'ENABLE_COMPRESSED_ATTRIBUTES':enabled}
        if compare_dma:parameters['ATTR_DMA_EARLY_ADVANCE']=early
        cmd=[v,'--lint-only','--sv','--timing','-DSYNTHESIS','-Wno-fatal','-Irtl/raster','--top-module','gs_accel_system_top',
             *[f'-G{k}={x}' for k,x in parameters.items()],'-f','verification/rtl/system_top_sources.f']
        log=dest/(f'production_{enabled}_early{early}.log' if compare_dma else f'production_{enabled}.log');run_logged(cmd,log)
        assert not any(x in log.read_text() for x in ['%Error','%Warning-LATCH','%Warning-UNOPTFLAT','%Warning-MULTIDRIVEN'])
    save(dest/'report.json',dict(status='PASS_DEFAULT_REGRESSIONS_AND_PRODUCTION_LINT' if compare_dma else 'PASS_DEFAULT_REGRESSIONS_AND_BOTH_LINTS',signed_off=False,
        source_sha256=production_sources(),legacy_report_sha256=sha(dest/'legacy_units/report.json')))

if __name__=='__main__':main()
