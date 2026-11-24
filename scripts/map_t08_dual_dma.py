"""Compare dual-format DMA against the frozen early-advance TT mappings, one PDK at a time."""
import fcntl
import os
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_dual_precision import BUILD, OUT as DUAL
from scripts.map_t08_early_advance import LIBRARIES, TOP, FILES, OUT as BASELINE
from scripts.t08_common import BASE, WORK, read, save, sha, run_logged
from asic.scripts.run_t01_wsl_synthesis import q, run_stage, YOSYS
from asic.scripts import t01_sta_netlist_adapter as adapter

OUT=BASE/'dual_dma_cost_20261122'


def measure(spec,sources):
    pdk,rel,driver,abc_load,sta_load=spec
    old=BASELINE/pdk/'1'
    before=read(old/'result.json')
    lib=ROOT/rel
    sta=Path.home()/'eda/opt/opensta/bin/sta'
    tcl=ROOT/'asic/scripts/run_t01_wsl_sta.tcl'
    for path,key in [(lib,'liberty_sha256'),(sta,'sta_sha256'),(YOSYS,'yosys_sha256'),
                     (tcl,'sta_script_sha256'),(old/'mapped.v','netlist_sha256')]:
        assert sha(path)==before[key]
    for name in ('mapping','sta'):
        assert sha(old/(name+'.log'))==before[name]['log_sha256'] and before[name]['exit_code']==0
    d=OUT/pdk
    d.mkdir(exist_ok=True)
    net=d/'mapped.v'
    config=(old/'abc.constr').read_text()
    assert config==f'set_driving_cell {driver}\nset_load {abc_load}\n'
    (d/'abc.constr').write_text(config)
    mapping=(old/'mapping.ys').read_text().replace(str(old)+'/',str(d)+'/')
    for path in FILES:
        assert mapping.count(q(ROOT/path))==1
        mapping=mapping.replace(q(ROOT/path),q(BUILD/Path(path).name))
    assert mapping.count('chparam -set EARLY_ADVANCE 1 ')==1
    mapping=mapping.replace('chparam -set EARLY_ADVANCE 1 ','chparam -set EARLY_ADVANCE 1 -set ENABLE_Q24 1 ')
    contract=dict(sources=sources,liberty_sha256=sha(lib),command_script=mapping,old_report_sha256=sha(old/'result.json'))
    marker=d/'launch.json'
    if marker.exists():
        assert read(marker)==contract
    else:
        save(marker,contract)
    execution=d/'mapping.execution.json'
    if execution.exists() and read(execution)['exit_code']==0:
        assert read(execution)['log_sha256']==sha(d/'mapping.log') and (d/'mapping.ys').read_text()==mapping
    else:
        run_stage('mapping',mapping.splitlines(),d)
    stats=read(d/'stat.json')['design']
    cells=set(re.findall(r'cell\s*\(\s*([^\s)]+)',lib.read_text()))
    assert not(set(stats['num_cells_by_type'])-cells)
    adapted=adapter.adapt(net,lib,TOP)
    env=dict(os.environ,T01_TOP=TOP,T01_LIBERTY=str(lib),T01_NETLIST=str(adapted),T01_DRIVER_CELL=driver,
             T01_LOAD=str(sta_load),T01_OUT_SDC=str(d/'applied.sdc'))
    ex=run_logged([str(sta),'-no_init','-exit',str(tcl)],d/'sta.log',env=env)
    log=(d/'sta.log').read_text()
    assert 'T01_COVERAGE_OK=1' in log and 'T01_STA_REPORT_END_REQUIRES_AUDIT' in log
    slack=dict(re.findall(r'^worst slack (max|min) (-?[\d.]+)$',log,re.M))
    after=dict(area_mm2=stats['area']/1e6,cells=stats['num_cells'],setup_wns_ns=float(slack['max']),hold_wns_ns=float(slack['min']))
    row=dict(pdk=pdk,before={k:before[k] for k in after},after=after,delta={k:v-before[k] for k,v in after.items()},
             mapping=read(execution),sta=ex,hashes={str(p):sha(p) for p in [net,adapted,tcl,sta,YOSYS,lib,d/'applied.sdc']})
    save(d/'result.json',row)
    return row


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    adapter.WORK=WORK/OUT.name
    adapter.WORK.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        binary=read(DUAL/'build/binary.json')
        sources={str((BUILD/Path(p).name).relative_to(ROOT)):sha(BUILD/Path(p).name) for p in FILES}
        assert all(binary['sources'][p]==h for p,h in sources.items())
        rows=[]
        try:
            for spec in LIBRARIES:
                save(OUT/'status.json',dict(status='MAPPING_OR_STA',pdk=spec[0],pid=os.getpid(),signed_off=False))
                rows.append(measure(spec,sources))
            assert all(sha(ROOT/p)==h for p,h in sources.items())
            save(OUT/'report.json',dict(results=rows,sources=sources,script_sha256=sha(__file__),signed_off=False,
                 scope='DMA and decoder only, TT 5 ns, no placement; excludes projection precision muxes.'))
            save(OUT/'status.json',dict(status='LOCAL_DMA_MEASURED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise
