"""Cross-check one identical complete workload on Icarus and Verilator."""
from pathlib import Path
import json,subprocess,re,hashlib
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'experiments/t05_20261009/real/bonsai/bsu8_m0_ideal'
DEST=ROOT/'experiments/t05_20261009/simulator_equivalence'
def main():
    DEST.mkdir(parents=True,exist_ok=True)
    original=json.loads((SOURCE/'command.json').read_text())
    args=[x for x in original if x.startswith('+')]
    args=[f'+{x[1:].split("=",1)[0]}={(DEST/name).as_posix()}' if x.startswith(prefix) else x
          for x in args for prefix,name in [next(((p,n) for p,n in [('+FRAME=','state.memh'),('+RGB=','rgb.memh'),('+SORTED_TRACE=','sorted.txt')] if x.startswith(p)),('!','unused'))]]
    cmd=[r'D:\IcarusVerilog\iverilog\bin\vvp.exe',str(ROOT/'experiments/t05_20261009/real/build/bsu8.vvp')]+args
    c=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)
    (DEST/'run.log').write_text(c.stdout+c.stderr);(DEST/'command.json').write_text(json.dumps(cmd,indent=2))
    if c.returncode:raise RuntimeError(c.stdout[-1500:])
    data=bytes(int(x,16) for x in (DEST/'rgb.memh').read_text().split())
    assert data==(SOURCE/'frame.rgb').read_bytes()
    assert (DEST/'sorted.txt').read_text()==(SOURCE/'sorted.txt').read_text()
    assert (DEST/'state.memh').read_text()==(SOURCE/'state.memh').read_text()
    expected=json.loads((SOURCE/'result.json').read_text())
    cycles=int(re.search(r'REAL_PERF cycles=(\d+)',c.stdout)[1]);assert cycles==expected['cycles']
    (DEST/'report.json').write_text(json.dumps({'status':'PASS','cycles':cycles,'state_equal':True,'sorted_stream_equal':True,'rgb_equal':True,
        'rgb_sha256':hashlib.sha256(data).hexdigest(),'reference':str(SOURCE)},indent=2))
    print('PASS: Icarus/Verilator cycles, full state, sorted stream and RGB identical',flush=True)
if __name__=='__main__':main()
