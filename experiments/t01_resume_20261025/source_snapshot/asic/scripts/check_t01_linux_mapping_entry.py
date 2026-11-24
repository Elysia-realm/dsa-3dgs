"""Exercise Linux ABC/dfflibmap/STA integration on the real shared PE only.

This is deliberately separate from the required full-top mapping/STA evidence.
"""
import os,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,read,save,sha,run_logged
from asic.scripts.run_t01_wsl_synthesis import YOSYS,q,run_stage
from asic.scripts.t01_sta_netlist_adapter import adapt
STA=Path.home()/'eda/opt/opensta/bin/sta'
def main():
    source=ROOT/'rtl/control/shared_reconfigurable_pe_slice.sv';rows=[]
    for pdk,lib,driver,load in [
      ('nangate45',ROOT/'tmp/toolchains/freepdk45_google_954b16e2/Front_End/Liberty/NLDM/NangateOpenCellLibrary_typical.lib','BUF_X4',3.899),
      ('icsprout55',ROOT/'tmp/toolchains/icsprout55/rvt-v1.10.102/liberty/ics55_LLSC_H7CR_typ_tt_1p2_25_nldm.lib','BUFX1H7R',0.003539972)]:
        d=BASE/'mapping_entry_smoke'/pdk;d.mkdir(parents=True,exist_ok=True);net=d/'shared_pe.v'
        abc=d/'abc.script';abc.write_text('strash\ndc2\nmap\ncleanup\nbuffer\nupsize -D 5000\ndnsize -D 5000\nstime -p\n')
        constr=d/'abc.constr';constr.write_text(f'set_driving_cell {driver}\nset_load {3.899 if pdk=="nangate45" else 3.539972}\n')
        commands=[f'read_verilog -sv -DSYNTHESIS {q(source)}','chparam -set DATA_W 96 -set RESULT_W 65 -set P_DOT3 1 shared_reconfigurable_pe_slice',
          'synth -top shared_reconfigurable_pe_slice -noabc',f'read_liberty -lib {q(lib)}',f'dfflibmap -liberty {q(lib)}',
          f'abc -script {q(abc)} -liberty {q(lib)} -constr {q(constr)} -D 5000','clean','check -assert',
          f'tee -o {q(d/"stat.json")} stat -json -liberty {q(lib)}','write_verilog -noattr -noexpr -nodec '+q(net)]
        run_stage('mapping',commands,d)
        sta_net=adapt(net,lib,'shared_reconfigurable_pe_slice')
        env=os.environ.copy();env.update(T01_TOP='shared_reconfigurable_pe_slice',T01_LIBERTY=str(lib),T01_NETLIST=str(sta_net),T01_DRIVER_CELL=driver,T01_LOAD=str(load),T01_OUT_SDC=str(d/'applied.sdc'))
        run_logged([str(STA),'-no_init','-exit',str(ROOT/'asic/scripts/run_t01_wsl_sta.tcl')],d/'sta.log',env=env)
        text=(d/'sta.log').read_text();assert 'T01_STA_REPORT_END_REQUIRES_AUDIT' in text and 'T01_COVERAGE_OK=1' in text,text[-1800:]
        rows.append(dict(pdk=pdk,status='PASS_TOOL_INTEGRATION',top='shared_reconfigurable_pe_slice',netlist_sha256=sha(net),library_sha256=sha(lib),source_sha256=sha(source),sta_log_sha256=sha(d/'sta.log')))
        print('PASS mapped PE / STA tool integration',pdk,flush=True)
    save(BASE/'mapping_entry_smoke/report.json',dict(status='PASS',scope='Real shared PE module only; not production-top or whole-chip acceptance',results=rows))
if __name__=='__main__':main()
