"""Map the tested eight-beat attribute DMA against the previously mapped dual DMA."""
import fcntl
import os
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from asic.scripts.run_t01_wsl_synthesis import q,run_stage,YOSYS
from asic.scripts import t01_sta_netlist_adapter as adapter
from scripts.map_t08_dual_dma import OUT as OLD,BUILD as ORIGINAL,LIBRARIES,TOP
from scripts.run_t08_eight_beat_header import OUT as CANDIDATE
from scripts.run_t08_precision_rgb import freeze
from scripts.t08_common import WORK,read,save,sha,run_logged

OUT=CANDIDATE/'mapping'


def measure(spec):
    pdk,rel,driver,abc_load,load=spec
    ref=OLD/pdk
    prior=read(ref/'result.json')
    src=ORIGINAL/(TOP+'.sv')
    rtl=CANDIDATE/'build'/src.name
    assert sha(rtl)==read(CANDIDATE/'protocol/report.json')['results'][0]['rtl_sha256']
    assert read(CANDIDATE/'build/binary.json')['sources'][str(rtl)]==sha(rtl)
    lib=ROOT/rel
    sta=Path.home()/'eda/opt/opensta/bin/sta'
    tcl=ROOT/'asic/scripts/run_t01_wsl_sta.tcl'
    for p in (lib,sta,tcl,YOSYS,ref/'mapped.v'):
        assert sha(p)==prior['hashes'][str(p)]
    old_launch=read(ref/'launch.json')
    assert all(sha(ROOT/f)==h for f,h in old_launch['sources'].items())
    old_script=(ref/'mapping.ys').read_text()
    assert old_script==old_launch['command_script'] and old_script.count(q(src))==1
    d=OUT/pdk
    d.mkdir(parents=True,exist_ok=True)
    cfg=(ref/'abc.constr').read_text()
    assert cfg==f'set_driving_cell {driver}\nset_load {abc_load}\n'
    freeze(d/'abc.constr',cfg)
    script=old_script.replace(str(ref)+'/',str(d)+'/').replace(q(src),q(rtl))
    contract=dict(script=script,rtl_sha256=sha(rtl),before_sha256=sha(ref/'result.json'),lib_sha256=sha(lib))
    marker=d/'launch.json'
    if marker.exists():assert read(marker)==contract
    else:save(marker,contract)
    ex=d/'mapping.execution.json'
    if ex.exists() and read(ex)['exit_code']==0:
        assert sha(d/'mapping.log')==read(ex)['log_sha256'] and (d/'mapping.ys').read_text()==script
    else:
        run_stage('mapping',script.splitlines(),d)
    net=d/'mapped.v'
    stats=read(d/'stat.json')['design']
    cells=set(re.findall(r'cell\s*\(\s*([^\s)]+)',lib.read_text()))
    assert not(set(stats['num_cells_by_type'])-cells)
    adapted=adapter.adapt(net,lib,TOP)
    env=dict(os.environ,T01_TOP=TOP,T01_LIBERTY=str(lib),T01_NETLIST=str(adapted),T01_DRIVER_CELL=driver,
             T01_LOAD=str(load),T01_OUT_SDC=str(d/'applied.sdc'))
    timed=run_logged([str(sta),'-no_init','-exit',str(tcl)],d/'sta.log',env=env)
    log=(d/'sta.log').read_text()
    assert 'T01_COVERAGE_OK=1' in log and 'T01_STA_REPORT_END_REQUIRES_AUDIT' in log
    slack=dict(re.findall(r'^worst slack (max|min) (-?[\d.]+)$',log,re.M))
    after=dict(area_mm2=stats['area']/1e6,cells=stats['num_cells'],setup_wns_ns=float(slack['max']),hold_wns_ns=float(slack['min']))
    row=dict(pdk=pdk,before=prior['after'],after=after,mapping=read(ex),sta=timed,
             hashes={str(p):sha(p) for p in [rtl,lib,YOSYS,sta,tcl,net,adapted,d/'applied.sdc']},signed_off=False)
    save(d/'result.json',row)
    return row


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    adapter.WORK=WORK/CANDIDATE.name/'sta_adapter'
    adapter.WORK.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            rows=[]
            for spec in LIBRARIES:
                save(OUT/'status.json',dict(status='MAPPING_OR_STA',pdk=spec[0],pid=os.getpid(),signed_off=False))
                rows.append(measure(spec))
            save(OUT/'report.json',dict(results=rows,script_sha256=sha(__file__),scope='Local dual DMA/decoder, TT 5 ns, unplaced.',signed_off=False))
            save(OUT/'status.json',dict(status='LOCAL_TT_COMPARED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise
