"""Bound the initial v2 read by its 64-byte line and compare the production LPDDR4 paths."""
from concurrent.futures import ThreadPoolExecutor
import fcntl
import os
from pathlib import Path
import re
import sys
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_shared_ddr import OUT as BASELINE,CFG
from scripts.run_t08_dual_precision import OUT as DUAL
from scripts.run_t08_q24_compact import edit,freeze
from scripts.run_t08_dual_full import compare_states
from scripts.run_t01_wsl_real import blocks
from scripts.t08_common import BASE,WORK,SCENES,read,save,sha,run_logged
from scripts.read_rgb888_frame import decode_rgb888

OUT=BASE/'attribute_line_header_20261123'
LOCAL=WORK/OUT.name


def prepare():
    prior=read(BASELINE/'build/binary.json')
    assert all(sha(ROOT/p)==h for p,h in prior['sources'].items())
    d=OUT/'build'
    d.mkdir(parents=True,exist_ok=True)
    orig=DUAL/'build/axi4_t08_attribute_read_engine.sv'
    rtl=d/orig.name
    text=edit(orig.read_text(),'assign planned=boundary_beats<remaining_q?boundary_beats[3:0]:remaining_q;',"""// Only v2 uses a line-bounded header burst. The record starts at a 16-byte slot
  // beat; the first request ends at a 64-byte boundary within the 144-byte slot.
  assign planned=(version2_q&&header_q)?(4'd4-{2'b0,address_q[5:4]}):
                 (boundary_beats<remaining_q?boundary_beats[3:0]:remaining_q);""")
    old="""header_q<=0;record_beats_q<=header_beats;remaining_q<=header_beats-1'b1;total_q<=1;
            if(header_bad)begin error_q<=1;error_status_o[1]<=1;state_q<=S_RSP;end
            else state_q<=EARLY_ADVANCE?S_AR:S_NEXT;"""
    new="""header_q<=0;record_beats_q<=header_beats;total_q<=1;index_q<=1;
            // A short record may occupy three valid beats in a four-beat
            // header burst. Retire the padding beat before decode or response.
            remaining_q<=((header_beats<burst_q)?burst_q:header_beats)-1'b1;
            if(header_bad)begin
              error_q<=1;error_status_o[1]<=1;state_q<=m_axi_rlast_i?S_RSP:S_ERROR_DRAIN;
            end else if(expected_last)state_q<=EARLY_ADVANCE?S_AR:S_NEXT;
            else state_q<=S_R;"""
    freeze(rtl,edit(text,old,new))
    return rtl,prior


def protocol(rtl,early):
    saved=DUAL/'protocol/enabled'
    tb=saved/'tb_t08_attribute_dma.sv'
    d=OUT/'protocol'/str(early)
    w=LOCAL/'protocol'/str(early)
    d.mkdir(parents=True,exist_ok=True)
    w.mkdir(parents=True,exist_ok=True)
    text=edit(tb.read_text(),".EARLY_ADVANCE(1'b1)",f".EARLY_ADVANCE(1'b{early})")
    text=edit(text,"case(i%4) 0:addr=64'h1000;1:addr=64'hf80;2:addr=64'hff0;3:addr=64'hfc0;endcase",
              "addr=64'hfc0+16*((i/4)%4);")  # cover all four offsets independently of format
    text=edit(text,'burst=((formats==1||formats==2)&&offset==0)?1:beats-offset;',
              "burst=offset==0&&formats==2 ? 4-int'(addr[5:4]) : (offset==0&&formats==1?1:beats-offset);")
    # The output must remain unavailable until all beats of an invalid v2 header burst drain.
    needle="request(64'h2000,0,2);accept_ar(64'h2000,1);send_r("
    pattern=re.escape(needle)+r"([^,]+),1,0,0\);finish_response"
    def replace(m):
        return ("request(64'h2000,0,2);accept_ar(64'h2000,4);send_r("+m[1]+",0,0,0);"
                "for(int k=0;k<3;k++)begin if(rsp_valid_o||req_ready_o)$fatal;"
                "send_r(0,k==2,0,0);end finish_response")
    text,n=re.subn(pattern,replace,text)
    assert n>=3
    anchor='// Early RLAST'
    text=edit(text,anchor,"""// Faults on a partially consumed v2 burst, including the padding beat.
    for(int fault=0;fault<4;fault++)begin
      request(64'h2000,0,2);accept_ar(64'h2000,4);
      send_r(128'h02c8,0,0,0);
      if(fault==0)send_r(0,1,0,0);
      else begin
        send_r(0,0,0,fault==1?1:0);send_r(0,0,0,0);
        send_r(0,fault!=3,fault==2?2:0,0);
        if(fault==3)begin if(rsp_valid_o||req_ready_o)$fatal;send_r(0,1,0,0);end
      end
      finish_response(1,'0);if(!error_status_o[0])$fatal;clear_error();
    end
    """+anchor)
    bench=d/tb.name
    freeze(bench,text)
    decoder=DUAL/'build/t08_attribute_decoder.sv'
    ver=read(BASELINE/'build/binary.json')['command'][0]
    cmd=[ver,'--binary','--build','-j','2','--timing','--assert','-Wno-fatal','--top-module',bench.stem,
         '--Mdir',str(w),'-o','simulation',str(rtl),str(decoder),str(bench)]
    run_logged(cmd,d/'build.log')
    rows=[]
    for v in (0,1):
        vd=d/str(v)
        path=saved/str(v)/'input.memh'
        exp=BASE/'dma_20261107/expected.memh'
        ref=next(r for r in read(DUAL/'protocol/report.json')['results'] if r['enabled'] and r['variant']==v)
        assert sha(path)==ref['inputs_sha256'] and sha(exp)==ref['expected_sha256']
        words=[int(s,16) for s in path.read_text().splitlines()]
        physical=0
        padding=0
        for i,val in enumerate(words):
            n=(val>>1152)&15
            first=4-(i//4)%4
            extra=max(0,first-n) if val>>1156==2 else 0
            padding+=extra
            physical+=n+extra
        ex=run_logged([str(w/'simulation'),f'+N={len(words)}',f'+INPUT={path}',f'+EXPECTED={exp}'],vd/'run.log')
        log=(vd/'run.log').read_text()
        assert 'PASS T08 attribute DMA data_records=6144 control_cases=18' in log and f'beats={physical} ' in log
        assert padding>0
        rows.append(dict(early=early,variant=v,records=len(words),controls=18,physical_beats=physical,
                         padding=padding,execution=ex,input_sha256=sha(path),expected_sha256=sha(exp)))
    save(d/'report.json',dict(results=rows,sources={str(p):sha(p) for p in (bench,rtl,decoder)},elf_sha256=sha(w/'simulation')))
    return rows


def build(rtl,prior):
    d=OUT/'build'
    cmd=prior['command'].copy()
    old=BASELINE/'build/tb_t08_shared_ddr.sv'
    files=Path(cmd[cmd.index('-f')+1]).read_text().splitlines()
    index,=[i for i,f in enumerate(files) if Path(f).name==rtl.name]
    files[index]=str(rtl)
    listing=d/'sources.f'
    freeze(listing,'\n'.join(files)+'\n')
    bench=d/'tb_t08_line_header.sv'
    body=old.read_text().replace(old.stem,bench.stem)
    needle='t08_expected_beats<=t08_expected_beats+((t08_format==0||t08_format==3)?9:t08_record_beats(attr_mem[dut.attr_req_gid*9][15:0]));'
    body=edit(body,needle,"""begin
        integer useful,first_count;
        useful=(t08_format==0||t08_format==3)?9:t08_record_beats(attr_mem[dut.attr_req_gid*9][15:0]);
        first_count=4-int'((ATTR_BASE/16+64'(dut.attr_req_gid)*9)%4);
        t08_expected_beats<=t08_expected_beats+((t08_format==2&&first_count>useful)?first_count:useful);
      end""")
    freeze(bench,body)
    cmd[cmd.index('-f')+1]=str(listing)
    cmd[cmd.index(str(old))]=str(bench)
    cmd[cmd.index('--top-module')+1]=bench.stem
    cmd[cmd.index('--Mdir')+1]=str(LOCAL)
    sources={**prior['sources'],**{str(p):sha(p) for p in (bench,rtl,listing)}}
    marker=d/'binary.json'
    exe=LOCAL/'simulation'
    if marker.exists():
        info=read(marker)
        assert info['sources']==sources and info['command']==cmd and info['elf_sha256']==sha(exe)
    else:
        run_logged(cmd,d/'build.log')
        info=dict(exe=str(exe),sources=sources,command=cmd,elf_sha256=sha(exe))
        save(marker,info)
    return info


def replay(kind,scene,info,out=OUT):
    origin=BASELINE/kind/scene/'f2_t1'
    ref=read(origin/'result.json')
    raw=read(origin.parent/'f3_t1/result.json')
    assert sha(origin/'launch.json')==ref['hashes']['launch.json']
    launch=read(origin/'launch.json')
    d=out/kind/scene
    d.mkdir(parents=True,exist_ok=True)
    cmd=launch['command'].copy()
    cmd[0]=info['exe']
    paths=dict(FRAME='state.memh',RGB='rgb.memh',SORTED_TRACE='sorted.txt',MODEL_STATS='model.stats')
    cmd=['+'+k+'='+str(d/paths[k]) if (k:=a.partition('=')[0][1:]) in paths else a for a in cmd]
    inputs={k:sha(a.partition('=')[2]) for a in cmd if (k:=a.partition('=')[0][1:]) in ('MEAN','ATTR','CAMERA')}
    assert inputs==launch['input_sha256']
    cfg=dict(command=cmd,elf_sha256=info['elf_sha256'],inputs=inputs,ref_sha256=sha(origin/'result.json'))
    marker=d/'launch.json'
    if marker.exists():assert read(marker)==cfg
    else:save(marker,cfg)
    ex=d/'run.execution.json'
    if ex.exists() and read(ex)['exit_code']==0:assert sha(d/'run.log')==read(ex)['log_sha256']
    else:run_logged(cmd,d/'run.log')
    log=(d/'run.log').read_text()
    top=info['command'][info['command'].index('--top-module')+1]
    assert f'PASS: {top}' in log and 'error=00000000' in log
    c=blocks(log)
    assert c['REAL_T08']['requests']==ref['counters']['REAL_T08']['requests'] and c['REAL_T08']['world_precomputed']==ref['counters']['REAL_T08']['world_precomputed']>0
    assert c['REAL_LPDDR']['lines']==int(re.search(r'ramulator\.incoming_requests\s+(\d+)',(d/'model.stats').read_text())[1])
    for f in ('rgb.memh','sorted.txt'):
        assert sha(d/f)==ref['hashes'][f],(scene,kind,f)
    cam=Path(next(a[8:] for a in cmd if a.startswith('+CAMERA=')))
    w,h=[int(cam.read_text().split()[i],16) for i in (25,26)]
    rgb=decode_rgb888(bytes.fromhex((d/'rgb.memh').read_text()),w,h)
    Image.fromarray(rgb).save(d/'frame.png')
    assert sha(d/'frame.png')==ref['hashes']['frame.png'] and Image.open(d/'frame.png').tobytes()==rgb.tobytes()
    assert sha(origin/'state.memh')==ref['hashes']['state.memh']
    diff=compare_states(d/'state.memh',origin/'state.memh')
    cycles=c['REAL_END_TO_END']['command_cycles']
    row=dict(scene=scene,kind=kind,counters=c,cycles=cycles,baseline_cycles=ref['cycles'],raw_cycles=raw['cycles'],
             terminal_t_differences=diff,attr_bytes=16*c['REAL_DMA_COUNTS']['attribute_beats'],
             old_attr_bytes=16*ref['counters']['REAL_DMA_COUNTS']['attribute_beats'],execution=read(ex),
             hashes={f:sha(d/f) for f in ('rgb.memh','sorted.txt','state.memh','frame.png','model.stats','launch.json')})
    assert row['attr_bytes']<16*raw['counters']['REAL_DMA_COUNTS']['attribute_beats']
    save(d/'result.json',row)
    return row


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            save(OUT/'status.json',dict(status='UNITS_AND_BUILD',pid=os.getpid(),signed_off=False))
            rtl,prior=prepare()
            units=[r for early in (0,1) for r in protocol(rtl,early)]
            save(OUT/'protocol/report.json',dict(results=units,signed_off=False))
            info=build(rtl,prior)
            for kind in ('subset','full128'):
                save(OUT/'status.json',dict(status='RUNNING_'+kind.upper(),pid=os.getpid(),signed_off=False))
                with ThreadPoolExecutor(max_workers=3) as pool:rows=list(pool.map(lambda s:replay(kind,s,info),SCENES))
                save(OUT/(kind+'_report.json'),dict(results=rows,signed_off=False))
            assert all(sha(ROOT/p)==h for p,h in info['sources'].items())
            save(OUT/'status.json',dict(status='SHARED_LINE_HEADER_COMPARED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise
