"""Five-scene same-condition alpha-off control for the T01 mapped comparison."""
import sys
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,WORK,OLD,read,save,sha,initialize,frozen,run_logged
from scripts.run_t01_wsl_real import blocks,validate_input
from scripts.read_rgb888_frame import decode_rgb888
def main():
    initialize();production=read(BASE/'build/subset/binary.json');build=WORK/'build/alpha_control';build.mkdir(parents=True,exist_ok=True)
    dest=BASE/'alpha_control';dest.mkdir(parents=True,exist_ok=True)
    cmd=production['command'].copy();assert cmd.count('-DTB_ENABLE_ALPHA_ZERO_SKIP=1')==1
    cmd[cmd.index('-DTB_ENABLE_ALPHA_ZERO_SKIP=1')]='-DTB_ENABLE_ALPHA_ZERO_SKIP=0'
    cmd[cmd.index('--Mdir')+1]=str(build);exe=build/'simulation';marker=dest/'binary.json'
    if not marker.exists():
        run_logged(cmd,dest/'build.log');assert exe.read_bytes()[:4]==b'\x7fELF'
        save(marker,dict(binary_sha256=sha(exe),command=cmd,source_sha256=frozen(),sole_parameter_delta={'ENABLE_ALPHA_ZERO_SKIP':[1,0]}))
    info=read(marker);assert info['command']==cmd and info['binary_sha256']==sha(exe)
    rows=[]
    for n in ['bonsai','counter','room','train','truck']:
        d=dest/n;d.mkdir(exist_ok=True);inputs=OLD/'subset'/n;m=validate_input(inputs)
        prod=BASE/'real/subset'/n/'m0_ideal';ref=read(prod/'result.json')
        run=read(prod/'run.command.json');run[0]=str(exe)
        outputs={'FRAME':'state.memh','RGB':'rgb.memh','SORTED_TRACE':'sorted.txt'}
        for i,arg in enumerate(run):
            key=arg[1:].split('=',1)[0] if arg.startswith('+') else ''
            if key in outputs:run[i]='+'+key+'='+str(d/outputs[key])
        execution=run_logged(run,d/'run.log');text=(d/'run.log').read_text();c=blocks(text)
        assert 'PASS: tb_t06_rgb_workload' in text and 'error=00000000' in text and 'disjoint=1' in text
        assert c['REAL_ALPHA_SKIP']['enabled']==0
        raw=bytes(int(v,16) for v in (d/'rgb.memh').read_text().split());assert raw==(prod/'frame.rgb').read_bytes()==(inputs/'oracle/frame.rgb').read_bytes()
        assert (d/'sorted.txt').read_bytes().replace(b'\r\n',b'\n')==(inputs/'expected_sorted.txt').read_bytes().replace(b'\r\n',b'\n')
        (d/'frame.rgb').write_bytes(raw);Image.fromarray(decode_rgb888(raw,m['width'],m['height'])).save(d/'frame.png')
        off=c['REAL_END_TO_END']['command_cycles'];on=ref['command_cycles']
        row=dict(scene=n,camera_index=m['camera_index'],status='PASS',gaussians=512,full_scene=False,width=m['width'],height=m['height'],mode='G',axi='legacy_ideal',
          alpha_off_cycles=off,production_alpha_on_cycles=on,saved_cycles=off-on,saved_percent=100*(off-on)/off,
          rgb_sha256=sha(d/'frame.rgb'),counters=c,production_counters=ref['counters'],input_sha256=m['input_sha256'],binary_sha256=sha(exe),execution=execution)
        save(d/'result.json',row);rows.append(row);print('PASS alpha control',n,off,on,flush=True)
    save(dest/'report.json',dict(status='PASS',source_sha256=frozen(),sole_parameter_delta={'ENABLE_ALPHA_ZERO_SKIP':[1,0]},scope='Five real 512-record G/legacy-ideal matched control; not full-model or native-resolution performance signoff',results=rows))
if __name__=='__main__':main()
