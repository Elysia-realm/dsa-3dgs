"""Nonempty repeat and complete-model comparisons on the candidate integration."""
import argparse,difflib,re,sys,shutil,os
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,WORK,T07,SCENES,read,save,sha,run_logged,production_sources
from scripts.run_t01_wsl_real import blocks
from scripts.run_t07_real import state_values
from scripts.read_rgb888_frame import decode_rgb888
from model.io.t08_batch_encoder import encode_records
from model.io.t08_attribute_codec import encode_record
from PIL import Image
OUT=BASE/'extended_20261107'

def prepare_bench(kind):
    if kind=='full':return 'verification/rtl/tb_t08_integrated.sv'
    old=(ROOT/'verification/rtl/tb_t07_workload.sv').read_text().replace('tb_t07_workload','BASE_MODULE').splitlines(keepends=True)
    new=(ROOT/'verification/rtl/tb_t08_integrated.sv').read_text().replace('tb_t08_integrated','BASE_MODULE').splitlines(keepends=True)
    target=(ROOT/'verification/rtl/tb_t07_repeat.sv').read_text().replace('tb_t07_repeat','BASE_MODULE')
    for tag,i,j,a,b in difflib.SequenceMatcher(None,old,new,autojunk=False).get_opcodes():
        if tag=='equal':continue
        before=''.join(old[i:j]);after=''.join(new[a:b])
        if 'attr_beats!=(qsu_requested?' in before:
            before=before.replace('dut.qsu_stats[31:0]','dut.qsu_stats[31:0]*auto_repeat_frames')
        if not before:
            for context in range(1,21):
                before=''.join(old[i:i+context])
                if before and target.count(before)==1:break
            after=after+before
        assert target.count(before)==1,(tag,before[:120],target.count(before))
        target=target.replace(before,after,1)
    target=target.replace('BASE_MODULE','tb_t08_repeat')
    # Restore the requested shadow format before the second START. The first
    # frame already checks in-flight mutation to an unsupported shadow format.
    needle="apb_write(12'h000,32'h4);apb_write(12'h000,32'h1);"
    assert target.count(needle)==1
    target=target.replace(needle,"apb_write(12'h0f0,t08_format);"+needle)
    name='verification/rtl/tb_t08_repeat.sv';p=ROOT/name
    if p.exists():assert p.read_text()==target
    else:p.write_text(target)
    return name

def sources(bench):
    m=production_sources();pending=[bench]
    while pending:
        f=pending.pop()
        if f in m:continue
        m[f]=sha(ROOT/f)
        pending.extend(re.findall(r'`include\s+"([^"]+)"',(ROOT/f).read_text()))
    return m

def build(kind):
    bench=prepare_bench(kind);old=read(T07/'build'/('repeat' if kind=='repeat' else 'full')/'C/binary.json')
    name=Path(bench).stem;oldtop=old['command'][old['command'].index('--top-module')+1]
    cmd=[x.replace(oldtop,name) for x in old['command']];w=WORK/'extended_20261107'/kind;w.mkdir(parents=True,exist_ok=True)
    cmd[cmd.index('--Mdir')+1]=str(w);d=OUT/'build'/kind;marker=d/'binary.json';m=sources(bench)
    if marker.exists():
        info=read(marker);assert info['source_sha256']==m and info['command']==cmd and sha(Path(info['path']))==info['binary_sha256'];return info
    for f,h in m.items():
        p=d/'source_snapshot'/f;p.parent.mkdir(parents=True,exist_ok=True)
        if p.exists():assert sha(p)==h
        else:shutil.copy2(ROOT/f,p)
    save(d/'source_snapshot/manifest.json',m);run_logged(cmd,d/'build.log')
    info=dict(path=str(w/'simulation'),command=cmd,source_sha256=m,binary_sha256=sha(w/'simulation'),bench=bench,
              parameters={**old['parameters'],'ENABLE_COMPRESSED_ATTRIBUTES':1});save(marker,info);return info

def encode_scene(kind,name):
    d=OUT/'inputs'/kind/name;d.mkdir(parents=True,exist_ok=True)
    source=ROOT/('experiments/t06_release_20261022/subset' if kind=='repeat' else 'experiments/t06_full_precount_mem_20261022')/name/'attribute.memh'
    marker=d/'manifest.json';target=d/'attribute.memh'
    code={f:sha(ROOT/f) for f in ['model/io/t08_batch_encoder.py','model/io/t08_attribute_codec.py','model/io/t08_precompute.py']}
    if marker.exists():
        m=read(marker);assert m['source_sha256']==sha(source) and m['encoded_sha256']==sha(target) and m['encoder_source']==code;return target
    partial=target.with_suffix('.partial')
    archived=d/'interrupted_before_resume.partial'
    if partial.exists():
        assert not archived.exists(),'another interrupted attempt exists; preserve separately before retry'
        assert partial.resolve().is_relative_to(OUT.resolve()) and archived.resolve().is_relative_to(OUT.resolve())
        prior_hash=sha(partial);prior_size=partial.stat().st_size
        partial.rename(archived)
        save(d/'interruption.json',dict(bytes=prior_size,sha256=prior_hash,archive=str(archived),
             reason='No live prior encoder; preserve original bytes and validate regenerated prefix before accepting output'))
    source_before=sha(source)
    if kind=='full':
        assert source_before==read(BASE/'inputs/native'/name/'manifest.json')['input_sha256']['ATTR']
    save(d/'encoding_status.json',dict(status='ENCODING',pid=os.getpid(),source_sha256=source_before,encoder_source=code))
    count=0;useful=0;pre=0;scalar_checks=0
    with source.open() as incoming,partial.open('w') as output:
        done=False
        while not done:
            records=[]
            for i in range(4096):
                first=incoming.readline()
                if not first:done=True;break
                words=[first]+[incoming.readline() for _ in range(8)];assert all(words)
                records.append(sum(int(word,16)<<(128*j) for j,word in enumerate(words)))
            encoded=encode_records(records)
            # Every chunk has scalar cross-checks; all 512 subset records are
            # checked, and boundaries are checked for every full-model chunk.
            indices=range(len(records)) if kind=='repeat' else sorted(set([0,len(records)-1])) if records else []
            for i in indices:assert encoded[i]==encode_record(records[i]);scalar_checks+=1
            for enc in encoded:
                output.write(''.join(f'{(enc["record"]>>(128*j))&((1<<128)-1):032x}\n' for j in range(9)))
                useful+=enc['beats'];pre+=int(enc['precomputed'])
            count+=len(records)
            if count and count%262144==0:print('ENCODE',kind,name,count,flush=True)
    assert sources_current_encoder(code)
    assert sha(source)==source_before
    if archived.exists():
        prior=read(d/'interruption.json');assert sha(archived)==prior['sha256']
        compared=0
        with archived.open('rb') as original,partial.open('rb') as regenerated:
            while True:
                chunk=original.read(1<<20)
                if not chunk:break
                assert regenerated.read(len(chunk))==chunk,('interrupted prefix differs',name,compared)
                compared+=len(chunk)
        assert compared==prior['bytes']
        save(d/'prefix_validation.json',dict(status='PASS',bytes_compared=compared,original_sha256=prior['sha256']))
    partial.rename(target)
    expected=512 if kind=='repeat' else read(BASE/'inputs/native'/name/'manifest.json')['gaussians'];assert count==expected
    save(marker,dict(scene=name,records=count,slot_bytes=144,useful_beats=useful,precomputed_records=pre,
       source_sha256=sha(source),encoded_sha256=sha(target),encoder_source=code,scalar_crosschecks=scalar_checks))
    save(d/'encoding_status.json',dict(status='COMPLETE',records=count,manifest_sha256=sha(marker)))
    print('ENCODED',kind,name,count,flush=True);return target

def sources_current_encoder(code):return all(sha(ROOT/f)==h for f,h in code.items())

def run_case(kind,name,fmt,info):
    attr=encode_scene(kind,name)
    old=T07/'real'/kind/'C'/name;ref=read(old/'result.json');cmd=read(old/'run.command.json');cmd[0]=info['path']
    d=OUT/'real'/kind/name/f'f{fmt}';d.mkdir(parents=True,exist_ok=True);marker=d/'result.json'
    if marker.exists():
        prior=read(marker);assert prior['binary_sha256']==info['binary_sha256'] and all(sha(d/f)==h for f,h in prior['evidence_sha256'].items());return prior
    assert not (d/'launch.json').exists(),'unfinished case requires inspection'
    for i,x in enumerate(cmd):
        if not x.startswith('+'):continue
        key=x[1:].split('=',1)[0]
        if key in {'FRAME','RGB','SORTED_TRACE'}:cmd[i]='+'+key+'='+str(d/{'FRAME':'state.memh','RGB':'rgb.memh','SORTED_TRACE':'sorted.txt'}[key])
        if key=='ATTR' and fmt:cmd[i]='+ATTR='+str(attr)
    cmd+=['+ATTR_FORMAT='+str(fmt),'+MUTATE_FORMAT']
    hashes={x.split('=',1)[0][1:]:sha(Path(x.split('=',1)[1])) for x in cmd if x.startswith(('+MEAN=','+CAMERA=','+ATTR='))}
    assert sources(info['bench'])==info['source_sha256']
    save(d/'launch.json',dict(command=cmd,source_sha256=info['source_sha256'],binary_sha256=info['binary_sha256'],input_sha256=hashes,driver_sha256=sha(Path(__file__))))
    execution=run_logged(cmd,d/'run.log');log=(d/'run.log').read_text();c=blocks(log)
    assert 'PASS: '+Path(info['bench']).stem in log and 'error=00000000' in log
    raw=bytes(int(x,16) for x in (d/'rgb.memh').read_text().split());assert raw==(old/'frame.rgb').read_bytes()
    assert (d/'sorted.txt').read_bytes().replace(b'\r\n',b'\n')==(old/'sorted.txt').read_bytes().replace(b'\r\n',b'\n')
    epoch=2 if kind=='repeat' else 1
    state=state_values(d/'state.memh',epoch);previous=state_values(old/'state.memh',epoch)
    assert len(state)==len(previous) and all(rgb==rgb0 and (t==t0 or t<=7 and t0<=7) for (rgb,t),(rgb0,t0) in zip(state,previous))
    assert sources(info['bench'])==info['source_sha256']
    (d/'frame.rgb').write_bytes(raw);pixels=decode_rgb888(raw,ref['width'],ref['height']);Image.fromarray(pixels).save(d/'frame.png')
    assert Image.open(d/'frame.png').tobytes()==pixels.tobytes()
    row=dict(status='PASS_SCOPED_NOT_SIGNED_OFF',kind=kind,scene=name,format=fmt,gaussians=ref['gaussians'],full_scene=kind=='full',
       width=ref['width'],height=ref['height'],camera=SCENES[name],counters=c,command_cycles=c['REAL_END_TO_END']['command_cycles'],
       parameters=info['parameters'],source_sha256=info['source_sha256'],input_sha256=hashes,binary_sha256=info['binary_sha256'],execution=execution,
       signed_off=False,GT_pass=False)
    row['evidence_sha256']={p.name:sha(p) for p in d.iterdir() if p.is_file() and p.name!='result.json'};save(marker,row)
    print('PASS',kind,name,fmt,row['command_cycles'],flush=True);return row

def main():
    p=argparse.ArgumentParser();p.add_argument('kind',choices=['repeat','full']);a=p.parse_args();info=build(a.kind)
    # Each scene owns its encoder; two format runs are sequential within it.
    def scene(name):return [run_case(a.kind,name,fmt,info) for fmt in [0,1]]
    save(OUT/(a.kind+'_status.json'),dict(status='RUNNING',pid=os.getpid(),signed_off=False))
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:rows=[r for batch in pool.map(scene,SCENES) for r in batch]
        save(OUT/(a.kind+'_report.json'),dict(status='PASS_SCOPED_NOT_SIGNED_OFF',results=rows,signed_off=False))
        save(OUT/(a.kind+'_status.json'),dict(status='PASS_SCOPED_NOT_SIGNED_OFF',signed_off=False))
    except BaseException:
        save(OUT/(a.kind+'_status.json'),dict(status='FAILED_OR_INTERRUPTED',signed_off=False));raise

if __name__=='__main__':main()
