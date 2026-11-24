"""Reuse verified native adapters in a new T07 evidence directory."""
import argparse,importlib,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t07_common import BASE,WORK,PROFILE,initialize,source_manifest,read,save,sha,run_logged

def main():
    p=argparse.ArgumentParser();p.add_argument('group',choices=['legacy','selected','aux','recovery']);a=p.parse_args()
    if a.group in ['legacy','selected','aux']:
        module={'legacy':'run_t01_wsl_legacy_units','selected':'run_t01_wsl_selected_units','aux':'run_t01_wsl_aux'}[a.group]
        m=importlib.import_module('scripts.'+module)
        m.BASE=BASE;m.WORK=WORK;m.initialize=initialize;m.frozen=source_manifest
        if a.group=='aux':
            cfg=read(PROFILE);cfg['parameters'].update(ENABLE_SHAPE_BLOCK_REJECT=1,ENABLE_PIXEL_TERMINATION_SKIP=1)
            target=BASE/'candidate_profile.json';save(target,cfg);m.PROFILE=target
        m.main()
        return
    out=BASE/'candidate_recovery';out.mkdir(exist_ok=True);w=WORK/'candidate_recovery';w.mkdir(parents=True,exist_ok=True)
    original=ROOT/'verification/rtl/tb_t06_precount_recovery.sv';tb=out/'tb_t07_system_recovery.sv'
    text=original.read_text().replace('tb_t06_precount_recovery','tb_t07_system_recovery')
    text=text.replace('.ENABLE_ALPHA_ZERO_SKIP(1)', '.ENABLE_SHAPE_BLOCK_REJECT(1),.ENABLE_PIXEL_TERMINATION_SKIP(1),.ENABLE_ALPHA_ZERO_SKIP(1)')
    tb.write_text(text);source=source_manifest();source[str(tb.relative_to(ROOT))]=sha(tb)
    binary=w/'simulation.vvp'
    run_logged(['/usr/bin/iverilog','-g2012','-DSYNTHESIS','-Irtl/raster','-s','tb_t07_system_recovery','-o',str(binary),
                '-f','verification/rtl/system_top_sources.f',str(tb)],out/'build.log')
    rows=[]
    for fault in range(10):
        execution=run_logged(['/usr/bin/vvp',str(binary),f'+FAULT={fault}'],out/f'fault{fault}.log')
        assert 'PASS T06' in (out/f'fault{fault}.log').read_text()
        rows.append(dict(fault=fault,status='PASS',execution=execution));print('PASS candidate recovery',fault,flush=True)
    assert all(sha(ROOT/f)==h for f,h in source.items())
    save(out/'report.json',dict(status='PASS',source_sha256=source,original_tb_sha256=sha(original),results=rows,
      candidate_parameters={'ENABLE_SHAPE_BLOCK_REJECT':1,'ENABLE_PIXEL_TERMINATION_SKIP':1},
      scope='Ten existing camera/control/AXI fault recovery cases with selected switches enabled; zero-opacity control frames, not proof of nonzero termination work. Real matrices and full models establish actual path use separately.'))
if __name__=='__main__':main()
