"""Clock the state-line RTL against Ramulator admission and read callbacks on captured arrivals."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.check_t08_state_lines import OUT as CHECKED,RTL,BENCH,source_rows
from scripts.run_t08_ddr_windows import OUT as WINDOWS,RAM,CFG
from scripts.run_t08_q24_compact import edit,freeze
from scripts.t08_common import BASE,WORK,SCENES,read,save,sha,run_logged

OUT=BASE/'state_lines_timed_20261123'
LOCAL=WORK/OUT.name


def build():
    name='tb_t08_state_line_timed'
    bench=OUT/(name+'.sv')
    text=BENCH.read_text().replace(BENCH.stem,name)
    text=edit(text,'    assign ready=!pending&&!ret&&(tick%7!=1)&&(tick%7!=2);','''
    import "DPI-C" function void t08_mem_init(input string cfg,input string output_stats);
    import "DPI-C" function void t08_mem_tick();
    import "DPI-C" function int t08_mem_send(input longint unsigned addr,input int write_op);
    import "DPI-C" function int t08_mem_take();
    import "DPI-C" function longint unsigned t08_mem_finish();
    string cfg,stats,schedule_path;
    integer release_tick,schedule_fd;
    longint unsigned dram_ticks;
    always @(negedge clk)begin
        ready<=0;
        if(rst)begin
            t08_mem_tick();
            if(!pending&&!ret&&cmd)ready<=t08_mem_send(ma,int'(mwrite))!=0;
        end
    end''')
    text=edit(text,'if(wait_count==0)begin','if(t08_mem_take()!=0)begin')
    text=edit(text,'else wait_count<=wait_count-1;','')
    text=edit(text,'@(negedge clk);while(!sr)@(negedge clk);','while(!sr)@(negedge clk);')
    a=text.index('        held_response=out_data;')
    b=text.index('        if(!want_err && wr)',a)
    text=text[:a]+'        @(negedge clk);\n'+text[b:]
    text=edit(text,'repeat(4)@(negedge clk);rst=1;','''if(!$value$plusargs("CFG=%s",cfg)||!$value$plusargs("STATS=%s",stats)||!$value$plusargs("SCHEDULE=%s",schedule_path))$fatal;
        schedule_fd=$fopen(schedule_path,"r");if(!schedule_fd)$fatal;
        t08_mem_init(cfg,stats);mr=1;
        repeat(4)@(negedge clk);rst=1;''')
    text=edit(text,'if(scanned==4)issue(op,input_addr,input_data,input_mask);','''if(scanned==4)begin
                if($fscanf(schedule_fd,"%d\\n",release_tick)!=1)$fatal;
                while(tick<release_tick)@(negedge clk);
                issue(op,input_addr,input_data,input_mask);
            end''')
    text=edit(text,'$fclose(trace_fd);','$fclose(schedule_fd);dram_ticks=t08_mem_finish();\n        $display("TIMED_DRAIN dram_ticks=%0d rtl_ticks=%0d",dram_ticks,tick);$fclose(trace_fd);')
    freeze(bench,text)
    cpp=ROOT/'verification/rtl/t08_lpddr_timing.cpp'
    objects=sorted((RAM/'obj').glob('*.o'))
    assert objects
    ver=read(WINDOWS/'build/binary.json')['command'][0]
    cmd=[ver,'--binary','--build','-j','2','--timing','--assert','-Wno-fatal','--top-module',name,
         '--Mdir',str(LOCAL),'-o','simulation','-CFLAGS',f'-I{RAM}/src -DRAMULATOR',
         '-LDFLAGS',' '.join(map(str,objects)),str(RTL),str(bench),str(cpp)]
    sources={str(p):sha(p) for p in [RTL,BENCH,bench,cpp,Path(ver),CFG,*objects,*sorted((RAM/'src').glob('*.h'))]}
    LOCAL.mkdir(parents=True,exist_ok=True)
    marker=OUT/'binary.json'
    exe=LOCAL/'simulation'
    if marker.exists():
        info=read(marker)
        assert info['sources']==sources and info['command']==cmd and info['elf_sha256']==sha(exe)
    else:
        run_logged(cmd,OUT/'build.log')
        save(marker,dict(sources=sources,command=cmd,elf_sha256=sha(exe)))
    return exe


def run_scene(scene,exe):
    info,windows=source_rows(scene)
    results=[]
    for i in (2,3):
        d=OUT/scene/f'w{i}'
        d.mkdir(parents=True,exist_ok=True)
        prior=CHECKED/scene/f'w{i}'
        ref=read(prior/'result.json')
        deck=prior/'stimulus.txt'
        assert sha(deck)==ref['bench']['stimulus_sha256']
        schedule=d/'schedule.txt'
        start=info['results'][i]['first_tick']
        freeze(schedule,''.join(f'{t-start}\n' for t,*_ in windows[i]))
        trace=d/'buffer.trace'
        stats=d/'model.stats'
        cmd=[str(exe),f'+CFG={CFG}',f'+STATS={stats}',f'+DECK={deck}',f'+TRACE={trace}',f'+SCHEDULE={schedule}']
        ex=run_logged(cmd,d/'run.log',timeout=120)
        log=(d/'run.log').read_text()
        assert 'PASS T08 state line buffer' in log and sha(trace)==ref['bench']['trace_sha256']
        m=re.search(r'TIMED_DRAIN dram_ticks=(\d+) rtl_ticks=(\d+)',log)
        dram,rtl=map(int,m.groups())
        assert int(re.search(r'ramulator\.dram_cycles\s+(\d+)',stats.read_text())[1])==dram
        assert int(re.search(r'ramulator\.incoming_requests\s+(\d+)',stats.read_text())[1])==ref['verified_rtl_line_requests']
        row=dict(scene=scene,window=i,offered_span_cycles=8192,controller_cycles_including_flush=rtl,
                 dram_cycles_including_drain=dram,service_to_window_ratio=dram/(8192*6),
                 useful_GBps_with_feedback=ref['axi_bytes']*1.2/dram,
                 source_result_sha256=sha(prior/'result.json'),schedule_sha256=sha(schedule),
                 trace_sha256=sha(trace),stats_sha256=sha(stats),execution=ex)
        save(d/'result.json',row)
        results.append(row)
    return results


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    exe=build()
    with ThreadPoolExecutor(max_workers=2) as pool:
        groups=list(pool.map(lambda scene:run_scene(scene,exe),SCENES))
    save(OUT/'report.json',dict(results=sum(groups,[]),binary_sha256=sha(exe),script_sha256=sha(__file__),
         scope='Standalone serial state controller at assumed 200MHz, live LPDDR4 controller at 1200MHz. Address offers follow frozen relative arrivals subject to requester backpressure. CPU response always ready. Includes dirty flush and memory drain, synthetic checked data. No feedback to renderer or other AXI ports.',signed_off=False))
