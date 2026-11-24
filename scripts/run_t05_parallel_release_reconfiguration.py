import sys,json,subprocess
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import run_t05_parallel_reconfiguration as probe
from scripts.run_t05_parallel_real import sources
def main():
    probe.OUT=ROOT/'experiments/t05_parallel_20261011/release'
    probe.DEST=probe.OUT/'reconfiguration';probe.DEST.mkdir(parents=True,exist_ok=True)
    cmd=json.loads((probe.OUT/'build/production16_icarus_command.json').read_text())
    cmd[cmd.index('-s')+1]='tb_t05_reconfiguration';cmd[cmd.index('-o')+1]=str(probe.DEST/'k16.vvp')
    cmd.append('verification/rtl/tb_t05_reconfiguration.sv')
    c=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)
    (probe.DEST/'compile.log').write_text(c.stdout+c.stderr);(probe.DEST/'compile_command.json').write_text(json.dumps(cmd,indent=2))
    if c.returncode:raise RuntimeError(c.stderr[-3000:])
    with ThreadPoolExecutor(max_workers=4) as pool:rows=list(pool.map(probe.run,[(16,n) for n in probe.NAMES]))
    (probe.DEST/'report.json').write_text(json.dumps({'status':'PASS','results':rows,'source_sha256':sources()},indent=2))
if __name__=='__main__':main()
