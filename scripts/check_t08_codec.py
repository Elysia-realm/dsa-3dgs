"""Candidate codec/decoder parity against original real and extreme vectors."""
import sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,WORK,SCENES,read,save,sha,run_logged
from model.io.t08_attribute_codec import encode_record,decode_record,unpack_legacy
from model.io.t08_precompute import world_covariance_q20


def main():
    out=BASE/'codec_units_20261101';out.mkdir(parents=True,exist_ok=True)
    work=WORK/'codec_units_20261101';work.mkdir(parents=True,exist_ok=True)
    vectors=[];oracles=[];rows=[];source_inputs={}
    def add(packet,beats,expected):
        vectors.append(f'{(beats<<1152)|packet:0289x}\n')
        oracles.append(f'{expected:0342x}\n')
    def accept(record):
        encoded=encode_record(record);decoded=decode_record(encoded['record'],encoded['beats'])
        sh,q,scale=unpack_legacy(record)
        covariance=0
        if encoded['precomputed']:
            cs,ov=world_covariance_q20([q],[scale]);assert not ov[0]
            for code in cs[0]:covariance=(covariance<<41)|(int(code)&((1<<41)-1))
            legacy=record&(((1<<877)-1)|(((1<<81)-1)<<1037))
            assert decoded['covariance']==cs[0].tolist()
        else:legacy=record
        assert decoded['legacy']==legacy
        expected=(int(encoded['precomputed'])<<1366)|(encoded['degree']<<1364)|(legacy<<246)|covariance
        add(encoded['record'],encoded['beats'],expected)
        return encoded
    for name in SCENES:
        path=ROOT/'experiments/t06_release_20261022/subset'/name/'attribute.memh'
        source_inputs[str(path)]=sha(path)
        words=[int(s,16) for s in path.read_text().split()];assert len(words)==512*9
        total=0;compact=0
        for i in range(512):
            record=sum(words[i*9+k]<<(k*128) for k in range(9))
            e=accept(record);total+=e['beats']*16;compact+=e['precomputed']
        rows.append(dict(scene=name,records=512,precomputed_records=compact,encoded_payload_bytes=total,legacy_bytes=512*144))
    rng=np.random.default_rng(20261101)
    # Construct independently from the legacy bit layout, including SH 16-bit
    # limits, all degrees and covariance raw escapes. No floating PLY packer.
    for i in range(1024):
        degree=i%4;wide=(i//4)%2;record=0
        for c in range(3):
            for k in range((degree+1)**2):
                value=int(rng.integers(-(1<<17) if wide else -(1<<15),(1<<17) if wide else (1<<15)))
                record|=(value&((1<<18)-1))<<(18*(c*16+k))
        record|=int(rng.integers(0,8192))<<864
        for k in range(3):record|=int((1<<24)-1 if i%9==0 else rng.integers(0,1<<20))<<(877+k*24)
        record|=(1<<20)<<(949+3*22)
        for k in range(3):record|=int(rng.integers(0,1<<27))<<(1037+k*27)
        accept(record)
    clean=encode_record((1<<20)<<(949+3*22))
    malformed=[(clean['record']^1,clean['beats']), (clean['record']^(1<<8),clean['beats']),
               (clean['record']|(1<<14),clean['beats']), (clean['record'],0),
               (clean['record'],clean['beats']+1), (clean['record']|(1<<10),9)]
    for packet,beats in malformed:
        try:decode_record(packet,beats)
        except ValueError:pass
        else:raise AssertionError('invalid format accepted by host')
        add(packet,beats,1<<1367)
    (out/'input.memh').write_text(''.join(vectors));(out/'expected.memh').write_text(''.join(oracles))
    files=['rtl/dma/t08_attribute_decoder.sv','verification/rtl/tb_t08_attribute_decoder.sv']
    verilator=read(BASE/'build/native/binary.json')['command'][0]
    cmd=[verilator,'--binary','--build','-j','2','--timing','--assert','-Wno-fatal',
         '--top-module','tb_t08_attribute_decoder','--Mdir',str(work),'-o','simulation',*files]
    run_logged(cmd,out/'build.log')
    run_logged([str(work/'simulation'),f'+N={len(vectors)}','+INPUT='+str(out/'input.memh'),'+EXPECTED='+str(out/'expected.memh')],out/'run.log')
    assert f'PASS T08 attribute decoder vectors={len(vectors)}' in (out/'run.log').read_text()
    save(out/'report.json',dict(status='PASS_MODULE_ONLY',vectors=len(vectors),malformed_vectors=len(malformed),real_subsets=rows,
         source_sha256={f:sha(ROOT/f) for f in files+['model/io/t08_attribute_codec.py','model/io/t08_precompute.py','scripts/check_t08_codec.py']},
         input_sha256=source_inputs,binary_sha256=sha(work/'simulation'),signed_off=False,
         scope='No compressed DMA/top/render integration yet; real attribute records only, not real end-to-end frames'))
    print('PASS T08 codec/decoder',len(vectors),'vectors; module scope only',flush=True)


if __name__=='__main__':main()
