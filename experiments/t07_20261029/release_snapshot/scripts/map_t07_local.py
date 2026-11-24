"""Dual-TT local cost/timing diagnostic, explicitly not full-chip PPA."""
import sys,os,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t07_common import BASE,WORK,read,save,sha,run_logged
from asic.scripts.run_t01_wsl_synthesis import YOSYS,q,run_stage
from asic.scripts import t01_sta_netlist_adapter as adapter
adapter.WORK=WORK
adapt=adapter.adapt
TOP='t07_termination_cost_top'
FILES=['rtl/common/rv_reg_slice.sv','rtl/raster/block_termination_bank.sv','rtl/raster/block_termination_table.sv',
 'rtl/raster/raster_termination_filter.sv','rtl/raster/pixel_termination_mask.sv','rtl/raster/raster_pixel_termination_filter.sv',
 'verification/rtl/t07_termination_cost_top.sv']

def main():
    sources={f:sha(ROOT/f) for f in FILES};rows=[]
    for pixel in [0,1]:
        for pdk,lib,driver,load in [
          ('nangate45',ROOT/'tmp/toolchains/freepdk45_google_954b16e2/Front_End/Liberty/NLDM/NangateOpenCellLibrary_typical.lib','BUF_X4',3.899),
          ('icsprout55',ROOT/'tmp/toolchains/icsprout55/rvt-v1.10.102/liberty/ics55_LLSC_H7CR_typ_tt_1p2_25_nldm.lib','BUFX1H7R',0.003539972)]:
            d=BASE/'mapping'/f'pixel{pixel}'/pdk;d.mkdir(parents=True,exist_ok=True);marker=d/'result.json'
            if marker.exists():
                r=read(marker);assert r['source_sha256']==sources;rows.append(r);continue
            net=d/'mapped.v';abc=d/'abc.script';constr=d/'abc.constr'
            abc.write_text('strash\ndc2\nmap\ncleanup\nbuffer\nupsize -D 5000\ndnsize -D 5000\nstime -p\n')
            constr.write_text(f'set_driving_cell {driver}\nset_load {load if pdk=="nangate45" else load*1000}\n')
            commands=['read_verilog -sv -DSYNTHESIS '+' '.join(q(ROOT/f) for f in FILES),
                f'chparam -set PIXEL_SKIP {pixel} {TOP}',f'synth -top {TOP} -flatten -noabc',
                f'read_liberty -lib {q(lib)}',f'dfflibmap -liberty {q(lib)}',
                f'abc -script {q(abc)} -liberty {q(lib)} -constr {q(constr)} -D 5000','clean',
                'delete t:$scopeinfo','check -assert',
                f'tee -o {q(d/"stat.json")} stat -json -liberty {q(lib)}',
                f'write_verilog -noattr -noexpr -nodec {q(net)}']
            mapping=run_stage('mapping',commands,d)
            stats=read(d/'stat.json');design=stats.get('design') or stats['modules']['\\'+TOP]
            libcells=set(re.findall(r'cell\s*\(\s*([^\s)]+)',lib.read_text()))
            unknown=set(design['num_cells_by_type'])-libcells;assert not unknown,unknown
            adapted=adapt(net,lib,TOP)
            env=os.environ.copy();env.update(T01_TOP=TOP,T01_LIBERTY=str(lib),T01_NETLIST=str(adapted),
                T01_DRIVER_CELL=driver,T01_LOAD=str(load),T01_OUT_SDC=str(d/'applied.sdc'))
            sta=run_logged([str(Path.home()/'eda/opt/opensta/bin/sta'),'-no_init','-exit',str(ROOT/'asic/scripts/run_t01_wsl_sta.tcl')],d/'sta.log',env=env)
            log=(d/'sta.log').read_text();assert 'T01_COVERAGE_OK=1' in log and 'T01_STA_REPORT_END_REQUIRES_AUDIT' in log
            slacks=re.findall(r'worst slack (-?[\d.]+)',log)
            r=dict(status='PASS_LOCAL_REPORT_GENERATION',pixel_skip=pixel,pdk=pdk,area_mm2=design['area']/1e6,
              cells=design['num_cells'],cell_types=design['num_cells_by_type'],unknown_cells=list(unknown),
              worst_slack_reports=slacks,source_sha256=sources,liberty_sha256=sha(lib),netlist_sha256=sha(net),
              mapping=mapping,sta=sta,sta_log_sha256=sha(d/'sta.log'),
              scope='Local termination filter only, 292-bit production payload, TT/5ns; register-expanded arrays. Negative slack/electrical violations are not waived, no top-level frequency/PPA pass claimed.')
            save(marker,r);rows.append(r);print('LOCAL',pixel,pdk,r['area_mm2'],slacks,flush=True)
    assert sources=={f:sha(ROOT/f) for f in FILES}
    save(BASE/'mapping/report.json',dict(status='PASS_LOCAL_REPORT_GENERATION',results=rows,full_chip_ppa_pass=False))
if __name__=='__main__':main()
