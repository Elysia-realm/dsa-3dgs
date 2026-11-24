"""Run top-level STA with frozen explicit IO budgets and unit conversion."""
import argparse,math,os,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,PROFILE,read,save,sha,frozen,run_logged
STA=Path.home()/'eda/opt/opensta/bin/sta'
def main():
    p=argparse.ArgumentParser();p.add_argument('--alpha',type=int,choices=[0,1],required=True);p.add_argument('--pdk',choices=['nangate45','icsprout55'],required=True);p.add_argument('--liberty',type=Path,help='Relocate the exact mapped Liberty');a=p.parse_args()
    dest=BASE/'synthesis'/f'alpha{a.alpha}'/a.pdk
    mapping=read(dest/'mapping.json');net=dest/'gs_accel_system_top_mapped.v';lib=Path(mapping['liberty'])
    if a.liberty:lib=a.liberty.resolve()
    assert sha(net)==mapping['netlist_sha256'] and sha(lib)==mapping['liberty_sha256']
    from asic.scripts.t01_sta_netlist_adapter import adapt
    sta_net=adapt(net,lib)
    for f,h in mapping['source_sha256'].items():assert sha(ROOT/f)==h.upper()
    driver,load,capunit=('BUF_X4',3.899,'fF') if a.pdk=='nangate45' else ('BUFX1H7R',0.003539972,'pF')
    constraints=dict(clock_period_ns=5,uncertainty_ns=0.25,clock_and_driver_source_slew_ns=0.05,input_max_ns=0.5,input_min_ns=0,output_max_ns=0.5,output_min_ns=0,driver_cell=driver,output_load=load,capacitance_unit=capunit,reset_false_path=False,interconnect='ideal, no extracted parasitics',storage='register-expanded original RTL; not SRAM macro timing')
    save(dest/'sta_constraints_budget.json',constraints)
    env=os.environ.copy();env.update(T01_TOP='gs_accel_system_top',T01_LIBERTY=str(lib),T01_NETLIST=str(sta_net),T01_DRIVER_CELL=driver,T01_LOAD=str(load),T01_OUT_SDC=str(dest/'applied.sdc'))
    script=ROOT/'asic/scripts/run_t01_wsl_sta.tcl'
    result=run_logged([str(STA),'-no_init','-exit',str(script)],dest/'sta.log',env=env)
    log=(dest/'sta.log').read_text();assert 'T01_STA_REPORT_END_REQUIRES_AUDIT' in log
    assert 'T01_LINKED_TOP=gs_accel_system_top' in log
    assert not re.search(r'^Error:',log,re.M)
    values={k:float(re.search(r'worst slack '+k+r'\s+([-+\d.eE]+)',log)[1]) for k in ['max','min']}
    assert all(math.isfinite(v) for v in values.values())
    coverage=log.split('T01_BEGIN_COVERAGE\n',1)[1].split('T01_BEGIN_SETUP',1)[0]
    coverage_ok='T01_COVERAGE_OK=1' in coverage
    warnings=[line for line in log.splitlines() if 'Warning:' in line]
    save(dest/'sta_result.json',dict(status='REPORT_GENERATED_PENDING_COVERAGE_REVIEW',coverage_ok=coverage_ok,slack_ns=values,coverage_output=coverage,warnings=warnings,constraints=constraints,execution=result,
      netlist_sha256=sha(net),sta_netlist_sha256=sha(sta_net),liberty_sha256=sha(lib),sta_binary_sha256=sha(STA),sta_script_sha256=sha(script),sdc_sha256=sha(dest/'applied.sdc'),production_source_sha256=frozen(),signed_off=False))
    print(a.pdk,a.alpha,values,flush=True)
if __name__=='__main__':main()
