"""Cost the register-bounded rounding logic of one projection lane in both TT libraries."""
import fcntl
import os
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_dual_precision import BUILD, OUT as DUAL
from scripts.run_t08_precision_rgb import freeze
from scripts.map_t08_early_advance import LIBRARIES
from scripts.t08_common import BASE, WORK, read, save, sha, run_logged
from asic.scripts.run_t01_wsl_synthesis import YOSYS, q, run_stage
from asic.scripts import t01_sta_netlist_adapter as adapter

OUT=BASE/'dual_rounding_cost_20261122'
TOP='t08_rounding_cost'


def functions(text,names):
    code=[]
    for name in names:
        pattern=r'^[ \t]*function automatic [^\n]*\b'+name+r'\([^;]*;.*?endfunction'
        match,=re.findall(pattern,text,re.M|re.S)
        code.append(match)
    return '\n'.join(code)


def fixture():
    world=BUILD/'quaternion_scale_covariance_core.sv'
    screen=BUILD/'screen_covariance_core.sv'
    binary=read(DUAL/'build/binary.json')
    for p in [world,screen]:
        assert sha(p)==binary['sources'][str(p.relative_to(ROOT))]
    w=functions(world.read_text(),['round_cov_value_q20','round_cov_value_q24','round_cov_value','cov_q40_to_q16','cov_ov'])
    s=functions(screen.read_text(),['round_cov_to_q8_q20','round_cov_to_q8_q24','round_cov_to_q8','unsigned_overflow',
                                    'signed_overflow','saturate_unsigned','saturate_signed'])
    path=OUT/(TOP+'.sv')
    freeze(path,"""module t08_rounding_cost #(parameter bit ENABLE_Q24=0)(
      input logic clk_i,mode_i,input logic [6*58-1:0] world_i,input logic [3*111-1:0] screen_i,
      input logic [34:0] regularizer_i,output logic [6*41-1:0] world_o,
      output logic [3*35-1:0] screen_o,output logic world_overflow_o,screen_overflow_o);
      localparam CACC_W=58,COV_W=41,COV_SHIFT=20,COV_ACC_W=111,COV2_W=35,COV_TO_Q8_SHIFT=44;
      logic cfg_cov_q24_i;
      logic [6*58-1:0] world_q;
      logic [3*111-1:0] screen_q;
      logic [34:0] reg_q;
      logic [5:0] world_ov;
      logic [2:0] screen_ov;
      always_ff @(posedge clk_i) begin
        cfg_cov_q24_i<=ENABLE_Q24 && mode_i;
        world_q<=world_i;screen_q<=screen_i;reg_q<=regularizer_i;
        world_overflow_o<=|world_ov;screen_overflow_o<=|screen_ov;
      end
""" +w+'\n'+s+"""
      for(genvar i=0;i<6;i++)begin:g_world
        wire signed [CACC_W-1:0] value=world_q[i*CACC_W+:CACC_W];
        assign world_ov[i]=cov_ov(value);
        always_ff @(posedge clk_i)world_o[i*COV_W+:COV_W]<=cov_q40_to_q16(value);
      end
      for(genvar i=0;i<3;i++)begin:g_screen
        wire signed [COV_ACC_W-1:0] rounded=round_cov_to_q8($signed(screen_q[i*COV_ACC_W+:COV_ACC_W]));
        if(i==1)begin
          assign screen_ov[i]=signed_overflow(rounded);
          always_ff @(posedge clk_i)screen_o[i*COV2_W+:COV2_W]<=saturate_signed(rounded);
        end else begin
          wire signed [COV_ACC_W-1:0] regularized=rounded+$signed({{(COV_ACC_W-COV2_W){1'b0}},reg_q});
          assign screen_ov[i]=unsigned_overflow(regularized);
          always_ff @(posedge clk_i)screen_o[i*COV2_W+:COV2_W]<=saturate_unsigned(regularized);
        end
      end
    endmodule
""")
    return path,{str(p.relative_to(ROOT)):sha(p) for p in [world,screen,path]}


def measure(spec,mode,fixture_path):
    pdk,rel,driver,abc_load,load=spec
    d=OUT/pdk/str(mode)
    d.mkdir(parents=True,exist_ok=True)
    lib=ROOT/rel
    abc=d/'abc.constr'
    freeze(abc,f'set_driving_cell {driver}\nset_load {abc_load}\n')
    net=d/'mapped.v'
    commands=[f'read_verilog -sv {q(fixture_path)}',f'chparam -set ENABLE_Q24 {mode} {TOP}',
              f'synth -top {TOP} -flatten -noabc',f'read_liberty -lib {q(lib)}',f'dfflibmap -liberty {q(lib)}',
              f'abc -liberty {q(lib)} -constr {q(abc)} -D 5000','clean','delete t:$scopeinfo','check -assert',
              f'tee -o {q(d/"stat.json")} stat -json -liberty {q(lib)}',f'write_verilog -noattr -noexpr -nodec {q(net)}']
    execution=d/'mapping.execution.json'
    if execution.exists() and read(execution)['exit_code']==0:
        assert sha(d/'mapping.log')==read(execution)['log_sha256'] and (d/'mapping.ys').read_text()=='\n'.join(commands)+'\n'
    else:
        run_stage('mapping',commands,d)
    stats=read(d/'stat.json')['design']
    cells=set(re.findall(r'cell\s*\(\s*([^\s)]+)',lib.read_text()))
    assert not(set(stats['num_cells_by_type'])-cells)
    adapted=adapter.adapt(net,lib,TOP)
    tcl=ROOT/'asic/scripts/run_t01_wsl_sta.tcl'
    sta=Path.home()/'eda/opt/opensta/bin/sta'
    env=dict(os.environ,T01_TOP=TOP,T01_LIBERTY=str(lib),T01_NETLIST=str(adapted),T01_DRIVER_CELL=driver,
             T01_LOAD=str(load),T01_OUT_SDC=str(d/'applied.sdc'))
    checked=run_logged([str(sta),'-no_init','-exit',str(tcl)],d/'sta.log',env=env)
    log=(d/'sta.log').read_text()
    assert 'T01_COVERAGE_OK=1' in log and 'T01_STA_REPORT_END_REQUIRES_AUDIT' in log
    slack=dict(re.findall(r'^worst slack (max|min) (-?[\d.]+)$',log,re.M))
    row=dict(pdk=pdk,dual_precision=mode,area_mm2=stats['area']/1e6,cells=stats['num_cells'],
             setup_ns=float(slack['max']),min_ns=float(slack['min']),mapping=read(execution),sta=checked,
             hashes={str(p):sha(p) for p in [net,adapted,lib,YOSYS,sta,tcl,d/'applied.sdc']})
    save(d/'result.json',row)
    return row


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    adapter.WORK=WORK/OUT.name
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            path,sources=fixture()
            rows=[]
            for spec in LIBRARIES:
                for mode in (0,1):
                    save(OUT/'status.json',dict(status='MAPPING_OR_STA',pdk=spec[0],mode=mode,pid=os.getpid(),signed_off=False))
                    rows.append(measure(spec,mode,path))
            assert all(sha(ROOT/p)==h for p,h in sources.items())
            save(OUT/'report.json',dict(results=rows,sources=sources,script_sha256=sha(__file__),signed_off=False,
                 scope='Registered fixture for six world and three screen covariance rounding paths in one lane. Includes saturation, regularizer, overflow and fixture registers. Excludes multipliers, division, routing and full-top STA.'))
            save(OUT/'status.json',dict(status='ROUNDING_FIXTURES_MEASURED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise
