"""Scalar/burst RTL output-stage comparison with byte-exact and fault checks."""
import argparse,json,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.collect_t06_performance_baseline import sha
OUT=ROOT/'experiments/t06_rgb_burst_20261022/units'
def main(native=False):
    OUT.mkdir(parents=True,exist_ok=True);rows=[]
    files=['rtl/dma/axi4_final_rgb_frame_dma.sv','verification/rtl/tb_t06_rgb_burst.sv']
    source={f:sha(ROOT/f) for f in files}
    for burst in [1,16]:
        binary=OUT/f'b{burst}.vvp';cmd=[r'D:\IcarusVerilog\iverilog\bin\iverilog.exe','-g2012','-DSYNTHESIS',f'-DTB_RGB_BURST={burst}','-s','tb_t06_rgb_burst','-o',str(binary),*files]
        r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(OUT/f'b{burst}_build.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stderr
        (OUT/f'b{burst}_build_command.json').write_text(json.dumps(cmd))
        cases=[(w,h,p,0) for w,h in [(1,1),(5,3),(79,2),(80,2),(81,2),(83,2),(128,84)] for p in [0,1]]
        cases += [(83,2,1,f) for f in range(1,8) if f!=3 or burst>1]
        if native:cases=[(1920,1080,0,0)]
        for w,h,p,f in cases:
            name=f'b{burst}_{w}x{h}_p{p}_f{f}';cmd=[r'D:\IcarusVerilog\iverilog\bin\vvp.exe',str(binary),f'+WIDTH={w}',f'+HEIGHT={h}',f'+PROFILE={p}',f'+FAULT={f}']
            r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(OUT/f'{name}.log').write_text(r.stdout+r.stderr);(OUT/f'{name}_command.json').write_text(json.dumps(cmd))
            assert r.returncode==0 and 'PASS RGB_BURST' in r.stdout,r.stdout+r.stderr
            stats=[{k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)} for line in r.stdout.splitlines() if line.startswith('PASS RGB_BURST')]
            rows.append(dict(name=name,status='PASS',frames=stats,log=f'{name}.log'));print(name,stats,flush=True)
    assert all(sha(ROOT/f)==h for f,h in source.items())
    (OUT/('native_report.json' if native else 'report.json')).write_text(json.dumps(dict(status='PASS',results=rows,source_sha256=source,
      scope='RGB output stage only; synthetic state values; not whole-renderer real-data or 30FPS signoff'),indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--native',action='store_true');main(p.parse_args().native)
