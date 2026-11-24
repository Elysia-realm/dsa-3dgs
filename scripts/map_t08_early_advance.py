"""Map the changed DMA block in both existing TT libraries and compare local STA."""
import argparse
import fcntl
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from asic.scripts.run_t01_wsl_synthesis import YOSYS, q, run_stage
from asic.scripts import t01_sta_netlist_adapter as adapter
from scripts.t08_common import BASE, WORK, read, run_logged, save, sha

TOP = 'axi4_t08_attribute_read_engine'
FILES = [f'rtl/dma/{TOP}.sv', 'rtl/dma/t08_attribute_decoder.sv']
OUT = BASE / 'early_advance_20261120/mapping'
LIBRARIES = [
    ('nangate45', 'tmp/toolchains/freepdk45_google_954b16e2/Front_End/Liberty/NLDM/NangateOpenCellLibrary_typical.lib', 'BUF_X4', 3.899, 3.899),
    ('icsprout55', 'tmp/toolchains/icsprout55/rvt-v1.10.102/liberty/ics55_LLSC_H7CR_typ_tt_1p2_25_nldm.lib', 'BUFX1H7R', 3.539972, 0.003539972),
]


def map_case(spec, enabled, sources, reuse_finished):
    pdk, lib, driver, abc_load, sta_load = spec
    lib = ROOT / lib
    d = OUT / pdk / str(enabled)
    d.mkdir(parents=True, exist_ok=True)
    net = d / 'mapped.v'
    abc_constr = d / 'abc.constr'
    abc_constr.write_text(f'set_driving_cell {driver}\nset_load {abc_load}\n')
    commands = ['read_verilog -sv -DSYNTHESIS ' + ' '.join(q(ROOT / f) for f in FILES),
                f'chparam -set EARLY_ADVANCE {enabled} {TOP}', f'synth -top {TOP} -flatten -noabc',
                f'read_liberty -lib {q(lib)}', f'dfflibmap -liberty {q(lib)}',
                f'abc -liberty {q(lib)} -constr {q(abc_constr)} -D 5000', 'clean', 'delete t:$scopeinfo',
                'check -assert', f'tee -o {q(d / "stat.json")} stat -json -liberty {q(lib)}',
                f'write_verilog -noattr -noexpr -nodec {q(net)}']
    mapping_marker = d / 'mapping.execution.json'
    if reuse_finished and mapping_marker.exists() and read(mapping_marker)['exit_code'] == 0:
        mapping = read(mapping_marker)
        assert mapping['log_sha256'] == sha(d / 'mapping.log')
        assert (d / 'mapping.ys').read_text() == '\n'.join(commands) + '\n'
    else:
        mapping = run_stage('mapping', commands, d)
    stats = read(d / 'stat.json')['design']
    library = set(re.findall(r'cell\s*\(\s*([^\s)]+)', lib.read_text()))
    assert not (set(stats['num_cells_by_type']) - library)
    adapted = adapter.adapt(net, lib, TOP)
    sta_tool = Path.home() / 'eda/opt/opensta/bin/sta'
    sta_script = ROOT / 'asic/scripts/run_t01_wsl_sta.tcl'
    env = os.environ.copy()
    env.update(T01_TOP=TOP, T01_LIBERTY=str(lib), T01_NETLIST=str(adapted), T01_DRIVER_CELL=driver,
               T01_LOAD=str(sta_load), T01_OUT_SDC=str(d / 'applied.sdc'))
    sta = run_logged([str(sta_tool), '-no_init', '-exit', str(sta_script)], d / 'sta.log', env=env)
    log = (d / 'sta.log').read_text()
    assert 'T01_COVERAGE_OK=1' in log and 'T01_STA_REPORT_END_REQUIRES_AUDIT' in log
    slacks = dict(re.findall(r'^worst slack (max|min) (-?[\d.]+)$', log, re.MULTILINE))
    setup, hold = (float(slacks[k]) for k in ('max', 'min'))
    row = dict(pdk=pdk, early_advance=enabled, area_mm2=stats['area'] / 1e6, cells=stats['num_cells'],
               setup_wns_ns=setup, hold_wns_ns=hold, source_sha256=sources, liberty_sha256=sha(lib),
               netlist_sha256=sha(net), yosys_sha256=sha(YOSYS), sta_sha256=sha(sta_tool), sta_script_sha256=sha(sta_script),
               mapping=mapping, sta=sta, signed_off=False)
    save(d / 'result.json', row)
    print(pdk, enabled, row['area_mm2'], setup, hold, flush=True)
    return row


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--reuse-finished', action='store_true')
    args = parser.parse_args()
    adapter.WORK = WORK / 'early_advance_20261120/mapping'
    adapter.WORK.mkdir(parents=True, exist_ok=True)
    with (adapter.WORK / 'mapping.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        sources = {f: sha(ROOT / f) for f in FILES}
        rows = [map_case(spec, enabled, sources, args.reuse_finished) for spec in LIBRARIES for enabled in (0, 1)]
        assert all(sha(ROOT / f) == h for f, h in sources.items())
        save(OUT / 'report.json', dict(status='LOCAL_TT_MAPPED_AND_TIMED', results=rows, signed_off=False,
                                     scope='DMA and decoder only, TT, 5ns, unplaced. Negative slack and electrical violations remain diagnostic.'))


if __name__ == '__main__':
    main()
