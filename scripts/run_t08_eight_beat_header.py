"""Trade bounded v2 slot padding for one shared-memory round trip on common records."""
from concurrent.futures import ThreadPoolExecutor
import fcntl
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_attribute_line_header import OUT as LINE,replay
from scripts.run_t08_dual_precision import OUT as DUAL
from scripts.run_t08_q24_compact import freeze,edit
from scripts.t08_common import BASE,WORK,SCENES,read,save,sha,run_logged

OUT=BASE/'attribute_eight_beat_20261123'
LOCAL=WORK/OUT.name


def prepare():
    prior=read(LINE/'build/binary.json')
    assert all(sha(ROOT/p)==h for p,h in prior['sources'].items())
    d=OUT/'build'
    d.mkdir(parents=True,exist_ok=True)
    src=LINE/'build/axi4_t08_attribute_read_engine.sv'
    rtl=d/src.name
    text=edit(src.read_text(),"""// Only v2 uses a line-bounded header burst. The record starts at a 16-byte slot
  // beat; the first request ends at a 64-byte boundary within the 144-byte slot.""",
              "// Fetch the first eight v2 slot beats together, stopping at the 4 KiB boundary.")
    text=edit(text,"(4'd4-{2'b0,address_q[5:4]})","(boundary_beats<8?boundary_beats[3:0]:4'd8)")
    text=edit(text,'// A short record may occupy three valid beats in a four-beat',
              '// A short record can end before the final physical beat of the')
    freeze(rtl,text)
    return rtl,prior


def check_decks(rtl,early):
    srcdir=LINE/'protocol'/str(early)
    old=srcdir/'tb_t08_attribute_dma.sv'
    assert sha(old)==read(srcdir/'report.json')['sources'][str(old)]
    d=OUT/'protocol'/str(early)
    w=LOCAL/'protocol'/str(early)
    d.mkdir(parents=True,exist_ok=True)
    w.mkdir(parents=True,exist_ok=True)
    text=edit(old.read_text(),"addr=64'hfc0+16*((i/4)%4);",
              "addr=((i/32)%2==0)?(64'h1000-16*(1+(i/4)%8)):(64'h2000+16*((i/4)%8));")
    text=edit(text,"? 4-int'(addr[5:4]) :","? 8 :")
    text=edit(text,'send_r(packet[(offset+j)*128+:128],j==burst-1,0,0);',
              "send_r(offset+j>=beats ? {128{1'b1}} : packet[(offset+j)*128+:128],j==burst-1,0,0);")
    text=text.replace("accept_ar(64'h2000,4);","accept_ar(64'h2000,8);")
    text=text.replace('k<3;k++)begin if(rsp_valid_o||req_ready_o)$fatal;send_r(0,k==2','k<7;k++)begin if(rsp_valid_o||req_ready_o)$fatal;send_r(0,k==6')
    text=edit(text,'send_r(0,fault!=3,fault==2?2:0,0);','repeat(4)send_r(0,0,0,0);send_r(0,fault!=3,fault==2?2:0,0);')
    bench=d/old.name
    freeze(bench,text)
    cmd=read(srcdir/'build.command.json')
    cmd[cmd.index('--Mdir')+1]=str(w)
    cmd[cmd.index(str(LINE/'build'/rtl.name))]=str(rtl)
    cmd[cmd.index(str(old))]=str(bench)
    run_logged(cmd,d/'build.log')
    rows=[]
    for v in (0,1):
        ref=next(r for r in read(DUAL/'protocol/report.json')['results'] if r['enabled'] and r['variant']==v)
        deck=DUAL/'protocol/enabled'/str(v)/'input.memh'
        expected=BASE/'dma_20261107/expected.memh'
        assert sha(deck)==ref['inputs_sha256'] and sha(expected)==ref['expected_sha256']
        total=0
        for i,line in enumerate(deck.read_text().splitlines()):
            x=int(line,16)
            n=(x>>1152)&15
            first=(1+(i//4)%8) if (i//32)%2==0 else 8
            total+=max(n,first) if x>>1156==2 else n
        vd=d/str(v)
        ex=run_logged([str(w/'simulation'),'+N=6144',f'+INPUT={deck}',f'+EXPECTED={expected}'],vd/'run.log')
        log=(vd/'run.log').read_text()
        assert 'PASS T08 attribute DMA data_records=6144 control_cases=18' in log and f'beats={total} ' in log
        rows.append(dict(early=early,variant=v,physical_beats=total,padding=total-ref['beats'],records=6144,controls=18,
                         execution=ex,binary_sha256=sha(w/'simulation'),bench_sha256=sha(bench),rtl_sha256=sha(rtl),
                         inputs_sha256=sha(deck),expected_sha256=sha(expected)))
    return rows


def build(rtl,prior):
    d=OUT/'build'
    old=LINE/'build/tb_t08_line_header.sv'
    bench=d/'tb_t08_eight_beat_header.sv'
    text=old.read_text().replace(old.stem,bench.stem)
    text=edit(text,"first_count=4-int'((ATTR_BASE/16+64'(dut.attr_req_gid)*9)%4);",
              "first_count=256-int'((ATTR_BASE/16+64'(dut.attr_req_gid)*9)%256);\n        if(first_count>8)first_count=8;")
    freeze(bench,text)
    cmd=prior['command'].copy()
    i=cmd.index('-f')+1
    files=Path(cmd[i]).read_text().splitlines()
    assert files.count(str(LINE/'build'/rtl.name))==1
    files[files.index(str(LINE/'build'/rtl.name))]=str(rtl)
    listing=d/'sources.f'
    freeze(listing,'\n'.join(files)+'\n')
    cmd[i]=str(listing)
    cmd[cmd.index(str(old))]=str(bench)
    cmd[cmd.index('--top-module')+1]=bench.stem
    cmd[cmd.index('--Mdir')+1]=str(LOCAL)
    sources={**prior['sources'],**{str(p):sha(p) for p in (rtl,listing,bench)}}
    marker=d/'binary.json'
    exe=LOCAL/'simulation'
    if marker.exists():
        info=read(marker)
        assert info['command']==cmd and info['sources']==sources and info['elf_sha256']==sha(exe)
    else:
        run_logged(cmd,d/'build.log')
        info=dict(exe=str(exe),elf_sha256=sha(exe),command=cmd,sources=sources)
        save(marker,info)
    return info


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            save(OUT/'status.json',dict(status='UNITS_AND_BUILD',pid=os.getpid(),signed_off=False))
            rtl,prior=prepare()
            units=[r for early in (0,1) for r in check_decks(rtl,early)]
            save(OUT/'protocol/report.json',dict(results=units,signed_off=False))
            info=build(rtl,prior)
            for kind in ('subset','full128'):
                save(OUT/'status.json',dict(status='RUNNING_'+kind.upper(),pid=os.getpid(),signed_off=False))
                with ThreadPoolExecutor(max_workers=3) as pool:
                    rows=list(pool.map(lambda s:replay(kind,s,info,OUT),SCENES))
                save(OUT/(kind+'_report.json'),dict(results=rows,signed_off=False))
            assert all(sha(ROOT/p)==h for p,h in info['sources'].items())
            save(OUT/'status.json',dict(status='EIGHT_BEAT_COMPARED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise
