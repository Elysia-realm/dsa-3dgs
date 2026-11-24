"""Re-run six control/fault/camera/epoch cases with candidate 4+4 dual bypass."""
import json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t06_real import sha
OUT=ROOT/'experiments/t06_local_20261019/recovery'
def main():
    OUT.mkdir(parents=True,exist_ok=True);tb='verification/rtl/tb_t06_local_recovery.sv';binary=OUT/'recovery.vvp'
    files=(ROOT/'verification/rtl/system_top_sources.f').read_text().splitlines()+[tb,'verification/rtl/t06_frame_signals.svh','verification/rtl/t06_scratch_signals.svh']
    src={f:sha(ROOT/f) for f in files if f.strip()};cmd=[r'D:\IcarusVerilog\iverilog\bin\iverilog.exe','-g2012','-DSYNTHESIS','-Irtl/raster','-s','tb_t06_local_recovery','-o',str(binary),'-f','verification/rtl/system_top_sources.f',tb]
    r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(OUT/'build.log').write_text(r.stdout+r.stderr);(OUT/'build_command.json').write_text(json.dumps(cmd,indent=2));assert r.returncode==0,r.stderr
    rows=[]
    for fault in [0,1,2,4,5,6]:
        cmd=[r'D:\IcarusVerilog\iverilog\bin\vvp.exe',str(binary),f'+FAULT={fault}'];r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)
        (OUT/f'fault{fault}.log').write_text(r.stdout+r.stderr);assert r.returncode==0 and 'PASS T06' in r.stdout,r.stdout+r.stderr
        rows.append(dict(fault=fault,status='PASS',command=cmd));print('PASS recovery',fault,flush=True)
    assert all(sha(ROOT/f)==h for f,h in src.items())
    (OUT/'report.json').write_text(json.dumps(dict(status='PASS',results=rows,source_sha256=src,
       scope='4+4 dual bypass with LOCAL_RECORDS=256; FAULT=2 targets local-cache load RRESP; control/fault/recovery vectors use zero opacity, nonzero pixel correctness is separately covered by shared-window unit and real matrix'),indent=2))
if __name__=='__main__':main()
