"""Five real attribute sets through candidate AXI DMA; module-level scope."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,WORK,SCENES,read,save,sha,run_logged
from model.io.t08_attribute_codec import encode_record,decode_record

OUT=BASE/'dma_20261107'

def main():
    OUT.mkdir(parents=True,exist_ok=True);work=WORK/'dma_20261107';work.mkdir(parents=True,exist_ok=True)
    inputs=[];expected=[];rows=[];input_hashes={}
    def add(fmt,packet,beats,legacy,cov,degree,pre):
        inputs.append(f'{(fmt<<1156)|(beats<<1152)|packet:0290x}\n')
        packed_cov=0
        for value in cov:packed_cov=(packed_cov<<41)|(int(value)&((1<<41)-1))
        result=(int(pre)<<1366)|(degree<<1364)|(legacy<<246)|packed_cov
        expected.append(f'{result:0342x}\n')
    for name in SCENES:
        p=ROOT/'experiments/t06_release_20261022/subset'/name/'attribute.memh'
        input_hashes[str(p)]=sha(p);words=[int(s,16) for s in p.read_text().split()];assert len(words)==512*9
        oldbytes=0;newbytes=0
        for i in range(512):
            original=sum(words[i*9+j]<<(128*j) for j in range(9))
            add(0,original,9,original,[0]*6,3,False);oldbytes+=144
            enc=encode_record(original);dec=decode_record(enc['record'],enc['beats'])
            add(1,enc['record'],enc['beats'],dec['legacy'],dec['covariance'] or [0]*6,dec['degree'],enc['precomputed']);newbytes+=enc['beats']*16
        rows.append(dict(scene=name,gaussians=512,legacy_bytes=oldbytes,compressed_bytes=newbytes))
    # Include all 1024 synthetic edge records from the checked codec vectors.
    unit=read(BASE/'codec_units_20261101/report.json')
    for f,h in unit['source_sha256'].items():assert sha(ROOT/f)==h
    ins=(BASE/'codec_units_20261101/input.memh').read_text().splitlines()
    outs=(BASE/'codec_units_20261101/expected.memh').read_text().splitlines()
    for i in range(2560,3584):
        inputs.append(f'{(1<<1156)|int(ins[i],16):0290x}\n');expected.append(outs[i]+'\n')
    (OUT/'input.memh').write_text(''.join(inputs));(OUT/'expected.memh').write_text(''.join(expected))
    files=['rtl/dma/t08_attribute_decoder.sv','rtl/dma/axi4_t08_attribute_read_engine.sv','verification/rtl/tb_t08_attribute_dma.sv']
    v=read(BASE/'build/native/binary.json')['command'][0]
    cmd=[v,'--binary','--build','-j','2','--timing','--assert','-Wno-fatal','--top-module','tb_t08_attribute_dma',
         '--Mdir',str(work),'-o','simulation',*files]
    run_logged(cmd,OUT/'build.log');run_logged([str(work/'simulation'),f'+N={len(inputs)}','+INPUT='+str(OUT/'input.memh'),'+EXPECTED='+str(OUT/'expected.memh')],OUT/'run.log')
    log=(OUT/'run.log').read_text();assert f'PASS T08 attribute DMA data_records={len(inputs)} control_cases=9' in log
    total_beats=sum((int(x,16)>>1152)&15 for x in inputs)
    assert f'beats={total_beats} ' in log
    save(OUT/'report.json',dict(status='PASS_DMA_MODULE_ONLY',records=len(inputs),control_cases=9,axi_data_beats=total_beats,
         real_attribute_sets=rows,input_sha256=input_hashes,
         source_sha256={f:sha(ROOT/f) for f in files+['model/io/t08_attribute_codec.py','model/io/t08_precompute.py','scripts/check_t08_dma.py']},
         vectors_sha256=sha(OUT/'input.memh'),expected_sha256=sha(OUT/'expected.memh'),binary_sha256=sha(work/'simulation'),
         signed_off=False,production_render_pass=False))
    print('PASS DMA',len(inputs),'records',total_beats,'beats; 9 control/error cases')

if __name__=='__main__':main()
