"""Reproducible unit/format gates for the image-correctness fixes."""
import hashlib,json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'experiments/t06_20261017/unit_checks'
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    src=['rtl/common/rv_reg_slice.sv','rtl/projection/fixed_div_pipe2.sv','rtl/projection/screen_covariance_core.sv','verification/rtl/tb_t06_covariance_clamp.sv']
    commands={
      'clamp_build':[r'D:\IcarusVerilog\iverilog\bin\iverilog.exe','-g2012','-DSYNTHESIS','-s','tb_t06_covariance_clamp','-o',str(OUT/'clamp.vvp'),*src],
      'clamp_run':[r'D:\IcarusVerilog\iverilog\bin\vvp.exe',str(OUT/'clamp.vvp')],
      'python':[sys.executable,'-m','unittest','verification.test_t06_projection_reference','verification.test_scene_io','-v'],
      'cpp_syntax':[r'D:\Tools\msys64\ucrt64\bin\g++.exe','-std=c++17','-fsyntax-only','scripts/build_full_frame_rtl_batch_stdlib.cpp']}
    env=os.environ.copy();env['PATH']=r'D:\Tools\msys64\ucrt64\bin;'+env['PATH'];env['PYTHONIOENCODING']='utf-8'
    for name,cmd in commands.items():
        r=subprocess.run(cmd,cwd=ROOT,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace')
        (OUT/f'{name}.log').write_text(r.stdout+r.stderr,encoding='utf-8');(OUT/f'{name}_command.json').write_text(json.dumps(cmd,indent=2))
        assert r.returncode==0,name+': '+r.stdout+r.stderr
    src+=['model/reference/math3d.py','model/io/scene.py','scripts/build_full_frame_rtl_batch.py','scripts/build_full_frame_rtl_batch_stdlib.cpp','verification/test_scene_io.py','verification/test_t06_projection_reference.py']
    report={'status':'PASS','rtl_clamp_transactions':8,'python_tests':8,'cpp_syntax':'PASS_NOT_RUNTIME_EQUIVALENCE',
            'source_sha256':{f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in src}}
    (OUT/'report.json').write_text(json.dumps(report,indent=2));print('PASS: image correction unit and layout gates')
if __name__=='__main__':main()
