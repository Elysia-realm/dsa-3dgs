"""Archive the backpressured synchronous controller/reference comparison."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,WORK,save,sha,run_logged,read

def main():
    out=BASE/'bbox_serial_units_20261122';w=WORK/out.name;w.mkdir(parents=True,exist_ok=True)
    files=['rtl/projection/gaussian_bbox_axis0_reject.sv','rtl/projection/gaussian_bbox_axis0_serial.sv','verification/rtl/tb_t08_bbox_serial.sv']
    v=read(BASE/'build/native/binary.json')['command'][0]
    run_logged([v,'--binary','--timing','--assert','-j','2','-Wno-fatal','--top-module','tb_t08_bbox_serial',
        '--Mdir',str(w),'-o','simulation',*files],out/'build.log')
    ex=run_logged([str(w/'simulation')],out/'run.log')
    assert 'PASS SERIAL transactions=8214' in (out/'run.log').read_text()
    save(out/'report.json',dict(status='PASS_SERIAL_MODULE',source_sha256={f:sha(ROOT/f) for f in files},
        binary_sha256=sha(w/'simulation'),execution=ex,signed_off=False))

if __name__=='__main__':main()
