"""Time the tested combinational bbox proof in a single local 5 ns stage."""
import os
from pathlib import Path
import re
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,WORK,read,save,sha,run_logged
from asic.scripts.run_t01_wsl_synthesis import q,run_stage,YOSYS
from asic.scripts import t01_sta_netlist_adapter as adapter
from scripts.map_t08_early_advance import LIBRARIES

TOP='t08_bbox_cost_top'
FILES=['rtl/projection/gaussian_bbox_axis0_reject.sv','verification/rtl/t08_bbox_cost_top.sv']
OUT=BASE/'bbox_cost_20261122'

def main():
    global TOP,FILES,OUT
    serial=sys.argv[1:]==['--serial']
    if serial:
        TOP='t08_bbox_serial_cost_top'
        FILES=['rtl/projection/gaussian_bbox_axis0_serial.sv',f'verification/rtl/{TOP}.sv']
        OUT=BASE/'bbox_serial_cost_20261122'
    elif sys.argv[1:]:raise SystemExit('expected --serial or no arguments')
    sources={f:sha(ROOT/f) for f in FILES}
    if serial:
        assert read(BASE/'bbox_serial_units_20261122/report.json')['source_sha256'][FILES[0]]==sources[FILES[0]]
    else:
        candidate=read(BASE/'bbox_pair_native_20261122/build/1/binary.json')
        assert candidate['sources'][FILES[0]]==sources[FILES[0]]
    adapter.WORK=WORK/OUT.name
    rows=[]
    for pdk,rel,driver,abc_load,load in LIBRARIES:
        lib=ROOT/rel;d=OUT/pdk;d.mkdir(parents=True,exist_ok=True)
        abc=d/'abc.constr';abc.write_text(f'set_driving_cell {driver}\nset_load {abc_load}\n')
        net=d/'mapped.v'
        run_stage('mapping',['read_verilog -sv -DSYNTHESIS '+' '.join(q(ROOT/f) for f in FILES),
            f'synth -top {TOP} -flatten -noabc',f'read_liberty -lib {q(lib)}',f'dfflibmap -liberty {q(lib)}',
            f'abc -liberty {q(lib)} -constr {q(abc)} -D 5000','clean','delete t:$scopeinfo','check -assert',
            f'tee -o {q(d/"stat.json")} stat -json -liberty {q(lib)}',f'write_verilog -noattr -noexpr -nodec {q(net)}'],d)
        stats=read(d/'stat.json')['design']
        libcells=set(re.findall(r'cell\s*\(\s*([^\s)]+)',lib.read_text()))
        assert not(set(stats['num_cells_by_type'])-libcells)
        adapted=adapter.adapt(net,lib,TOP)
        env=dict(os.environ,T01_TOP=TOP,T01_LIBERTY=str(lib),T01_NETLIST=str(adapted),T01_DRIVER_CELL=driver,
                 T01_LOAD=str(load),T01_OUT_SDC=str(d/'applied.sdc'))
        sta=Path.home()/'eda/opt/opensta/bin/sta'
        run_logged([str(sta),'-no_init','-exit',str(ROOT/'asic/scripts/run_t01_wsl_sta.tcl')],d/'sta.log',env=env)
        log=(d/'sta.log').read_text()
        assert 'T01_COVERAGE_OK=1' in log and 'T01_STA_REPORT_END_REQUIRES_AUDIT' in log
        delays=dict(re.findall(r'^worst slack (max|min) (-?[\d.]+)$',log,re.M))
        rows.append(dict(pdk=pdk,area_mm2_including_fixture=stats['area']/1e6,cell_types=stats['num_cells_by_type'],
            setup_slack_ns=float(delays['max']),min_slack_ns=float(delays['min']),source_sha256=sources,
            sha256={p.name:sha(p) for p in (lib,net,adapted,sta,YOSYS,d/'sta.log',d/'mapping.log',d/'applied.sdc')}))
        print(pdk,rows[-1]['area_mm2_including_fixture'],delays,flush=True)
    save(OUT/'report.json',dict(status='LOCAL_COST_MEASURED',results=rows,signed_off=False,
        scope='One registered predicate per mapped fixture; launch/capture cells included. No integration, wire parasitics or final PPA claims.'))

if __name__=='__main__':main()
