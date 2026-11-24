from pathlib import Path
import json,subprocess,re,hashlib,sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t05_real import OUT,NAMES
DEST=ROOT/'experiments/t05_20261009/reconfiguration'
VVP=r'D:\IcarusVerilog\iverilog\bin\vvp.exe'
def main():
    DEST.mkdir(parents=True,exist_ok=True)
    original=json.loads((OUT/'build/bsu8_icarus_command.json').read_text())
    cmd=original.copy();cmd[cmd.index('-s')+1]='tb_t05_reconfiguration';cmd[cmd.index('-o')+1]=str(DEST/'model.vvp')
    cmd.append('verification/rtl/tb_t05_reconfiguration.sv')
    c=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)
    (DEST/'compile.log').write_text(c.stdout+c.stderr);(DEST/'compile_command.json').write_text(json.dumps(cmd,indent=2))
    if c.returncode:raise RuntimeError(c.stderr[-2000:])
    results=[]
    for name in NAMES:
        src=OUT/name/'rtl_batch_0000';dest=DEST/name;dest.mkdir(exist_ok=True)
        cmd=[VVP,str(DEST/'model.vvp'),f'+MEAN={src.as_posix()}/mean.memh',f'+ATTR={src.as_posix()}/attribute_sparse.memh',
          f'+GLOBAL_GIDS={src.as_posix()}/global_gid.memh',f'+CAMERA={src.as_posix()}/camera.memh',
          f'+FRAME={dest.as_posix()}/state.memh',f'+RGB={dest.as_posix()}/rgb.memh',
          '+FRAME_MODE=3','+AUTO_MODE','+AUTO_REPEAT_FRAMES=2','+READ_LATENCY=8','+READ_GAP=2','+READY_PERIOD=4','+READY_LOW=1','+WRITE_RESPONSE_LATENCY=8','+MAX_TIMEOUT=1000000']
        c=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)
        (dest/'run.log').write_text(c.stdout+c.stderr);(dest/'command.json').write_text(json.dumps(cmd,indent=2))
        if c.returncode:raise RuntimeError(c.stdout[-2000:])
        probe=re.search(r'T05_RESOURCE_PROBE changes=(\d+) GP=(\d+) PR=(\d+) GR=(\d+)',c.stdout)
        if not probe or int(probe[1])<2:raise RuntimeError('no next-epoch automatic mode change')
        if 'image_mismatches=0' not in c.stdout or 'epoch=2 error=00000000' not in c.stdout:raise RuntimeError('repeat image/error mismatch')
        results.append({'scene':name,'status':'PASS','frames':2,'mode_changes':int(probe[1]),'GP':int(probe[2]),'PR':int(probe[3]),'GR':int(probe[4]),
                        'transitions':[s for s in c.stdout.splitlines() if s.startswith(('T05_MODE_CHANGE','REAL_AUTO ','REAL_RGB '))]})
        print('PASS repeat/epoch '+name,flush=True)
    (DEST/'report.json').write_text(json.dumps({'status':'PASS','results':results},indent=2))
if __name__=='__main__':main()
