"""Force alternating raw escapes and precomputed records in real production frames."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,SCENES,read,save,sha
from model.io.t08_attribute_codec import encode_record,RAW_HEADER
import scripts.run_t08_integrated as runner

def main():
    info=read(BASE/'integration_20261107/build/binary.json')
    runner.OUT=BASE/'mixed_20261107';rows=[]
    for name in SCENES:
        source=ROOT/'experiments/t06_release_20261022/subset'/name/'attribute.memh'
        words=[int(x,16) for x in source.read_text().split()];packed=[];beats=0;pre=0
        for i in range(512):
            raw=sum(words[9*i+j]<<(128*j) for j in range(9))
            enc=encode_record(raw) if i%2 else dict(record=(raw<<16)|RAW_HEADER,beats=9,precomputed=False)
            beats+=enc['beats'];pre+=enc['precomputed']
            packed.extend(f'{(enc["record"]>>(128*j))&((1<<128)-1):032x}\n' for j in range(9))
        d=runner.OUT/'inputs'/name;d.mkdir(parents=True,exist_ok=True);p=d/'attribute.memh'
        content=''.join(packed)
        if p.exists():assert p.read_text()==content
        else:p.write_text(content)
        save(d/'manifest.json',dict(scene=name,records=512,useful_beats=beats,precomputed=pre,source_sha256=sha(source),encoded_sha256=sha(p)))
        row=runner.case(info,name,0,'limited',1)
        assert 0<row['counters']['REAL_T08']['precomputed']==pre<512
        rows.append(row)
    save(runner.OUT/'report.json',dict(status='PASS_MIXED_REAL_SUBSETS',results=rows,signed_off=False,scope='Five 512-record width128 G/limited frames with alternating raw escape and precomputed covariance'))

if __name__=='__main__':main()
