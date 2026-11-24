"""Dot3 adapters against independent local arithmetic, including contention."""
import json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.collect_t06_performance_baseline import sha
OUT=ROOT/'experiments/t06_dot3_20261021/units'
def main():
    OUT.mkdir(parents=True,exist_ok=True);rows=[];sources={}
    common=['rtl/common/rv_reg_slice.sv','rtl/control/shared_reconfigurable_pe_slice.sv']
    for name,top,extra,defs in [('pe','tb_t06_dot3_pe',[],[]),('depth','tb_t06_dot3_depth',['rtl/sort/gaussian_depth_prepass_core.sv','rtl/sort/gaussian_depth_prepass_shared_mac.sv'],[]),
      ('xyz','tb_t06_dot3_xyz',['rtl/projection/world_to_camera_core.sv','rtl/projection/world_to_camera_shared_mac.sv'],[]),
      ('xyz_stream','tb_t06_dot3_xyz',['rtl/projection/world_to_camera_core.sv','rtl/projection/world_to_camera_shared_mac.sv'],['-DTB_XYZ_STREAMING=1'])]:
        files=common+extra+[f'verification/rtl/{top}.sv'];sources.update({f:sha(ROOT/f) for f in files})
        cmd=[r'D:\IcarusVerilog\iverilog\bin\iverilog.exe','-g2012','-DSYNTHESIS',*defs,'-s',top,'-o',str(OUT/f'{name}.vvp'),*files]
        r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(OUT/f'{name}_build.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stderr
        run=[r'D:\IcarusVerilog\iverilog\bin\vvp.exe',str(OUT/f'{name}.vvp')];r=subprocess.run(run,cwd=ROOT,capture_output=True,text=True)
        (OUT/f'{name}.log').write_text(r.stdout+r.stderr);assert r.returncode==0 and 'PASS' in r.stdout,r.stdout+r.stderr
        rows.append(dict(name=name,status='PASS',build_command=cmd,run_command=run,result=r.stdout));print(r.stdout,flush=True)
    assert all(sha(ROOT/f)==h for f,h in sources.items())
    (OUT/'report.json').write_text(json.dumps(dict(status='PASS',results=rows,source_sha256=sources),indent=2))
if __name__=='__main__':main()
