from pathlib import Path
import json,sys,subprocess,re
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t05_parallel_real import OUT,NAMES
DEST=ROOT/'experiments/t05_parallel_20261011/reconfiguration'
VVP=r'D:\IcarusVerilog\iverilog\bin\vvp.exe'
def run(case):
    k,name=case;src=OUT/name/f'g{k}'/'rtl_batch_0000';dest=DEST/f'k{k}'/name;dest.mkdir(parents=True,exist_ok=True)
    cmd=[VVP,str(DEST/f'k{k}.vvp'),f'+MEAN={src.as_posix()}/mean.memh',f'+ATTR={src.as_posix()}/attribute_sparse.memh',
         f'+GLOBAL_GIDS={src.as_posix()}/global_gid.memh',f'+CAMERA={src.as_posix()}/camera.memh',
         f'+FRAME={dest.as_posix()}/state.memh',f'+RGB={dest.as_posix()}/rgb.memh',
         '+FRAME_MODE=3','+AUTO_MODE','+AUTO_REPEAT_FRAMES=2','+READ_LATENCY=8','+READ_GAP=2','+READY_PERIOD=4','+READY_LOW=1','+WRITE_RESPONSE_LATENCY=8','+MAX_TIMEOUT=2000000']
    c=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)
    (dest/'run.log').write_text(c.stdout+c.stderr);(dest/'command.json').write_text(json.dumps(cmd,indent=2))
    if c.returncode:raise RuntimeError(c.stdout[-2500:])
    probe=re.search(r'T05_RESOURCE_PROBE changes=(\d+) GP=(\d+) PR=(\d+) GR=(\d+)',c.stdout)
    assert probe and int(probe[1])>=2,'missing mode transition'
    assert 'image_mismatches=0' in c.stdout and 'epoch=2 error=00000000' in c.stdout
    row={'k':k,'scene':name,'status':'PASS','frames':2,'changes':int(probe[1]),'GP':int(probe[2]),'PR':int(probe[3]),'GR':int(probe[4]),
         'transitions':[line for line in c.stdout.splitlines() if line.startswith(('T05_MODE_CHANGE','REAL_AUTO ','REAL_RGB '))]}
    (dest/'result.json').write_text(json.dumps(row,indent=2));print('PASS repeat',k,name,flush=True);return row
def main():
    DEST.mkdir(parents=True,exist_ok=True)
    for k in (8,16):
        cmd=json.loads((OUT/'build'/f'pipe{k}_icarus_command.json').read_text())
        cmd[cmd.index('-s')+1]='tb_t05_reconfiguration';cmd[cmd.index('-o')+1]=str(DEST/f'k{k}.vvp')
        cmd.append('verification/rtl/tb_t05_reconfiguration.sv')
        c=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(DEST/f'k{k}_compile.log').write_text(c.stdout+c.stderr)
        if c.returncode:raise RuntimeError(c.stderr[-2000:])
    with ThreadPoolExecutor(max_workers=4) as pool:rows=list(pool.map(run,[(k,n) for k in (8,16) for n in NAMES]))
    (DEST/'report.json').write_text(json.dumps({'status':'PASS','results':rows},indent=2))
if __name__=='__main__':main()
