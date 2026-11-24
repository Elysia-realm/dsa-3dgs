"""Count a prospective root radix histogram while collecting; reuse only on exact pivot match."""
from concurrent.futures import ThreadPoolExecutor
import fcntl
import os
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_q24_compact import edit,freeze
from scripts.run_t08_dual_full import OUT as FULL,compare_states
from scripts.run_t01_wsl_real import blocks
from scripts.t08_common import BASE,WORK,SCENES,read,save,sha,run_logged

OUT=BASE/'qsu_root_precount_20261122'
LOCAL=WORK/OUT.name
BUILD=OUT/'build'
NAME='rtl/sort/autonomous_qsu.sv'


def candidate():
    prior=read(FULL/'build/binary.json')
    assert all(sha(ROOT/p)==h for p,h in prior['sources'].items())
    text=(ROOT/NAME).read_text()
    text=edit(text,'    assign input_key=',"""    // Predict only the radix position. Every count, minimum and maximum belongs to this frame.
    // Three fixed depth slices avoid a variable shifter on the incoming 91-bit record.
    logic [1:0] root_window_q;
    logic [2:0] collect_bucket;
    logic root_match;
    always_comb begin
        case(root_window_q)
          0:begin collect_bucket=3'(input_key>>(GID_W+SEQ_W+18));root_match=shift_bits==GID_W+SEQ_W+18;end
          1:begin collect_bucket=3'(input_key>>(GID_W+SEQ_W+19));root_match=shift_bits==GID_W+SEQ_W+19;end
          default:begin collect_bucket=3'(input_key>>(GID_W+SEQ_W+20));root_match=shift_bits==GID_W+SEQ_W+20;end
        endcase
    end
    assign input_key=""")
    text=edit(text,'state_q<=IDLE;capacity_q<=0;', "root_window_q<=2;state_q<=IDLE;capacity_q<=0;")
    text=edit(text,'state_q<=COLLECT;capacity_q<=capacity_i;',"""if(PRECOUNT_CHILDREN)for(integer j=0;j<8;j=j+1)begin
                        counts[j]<=0;mins[j]<='1;maxs[j]<=0;
                    end
                    state_q<=COLLECT;capacity_q<=capacity_i;""")
    text=edit(text,'if(input_key<min_q)min_q<=input_key;',"""if(PRECOUNT_CHILDREN)begin
                                counts[collect_bucket]<=counts[collect_bucket]+1;
                                if(input_key<mins[collect_bucket])mins[collect_bucket]<=input_key;
                                if(input_key>maxs[collect_bucket])maxs[collect_bucket]<=input_key;
                            end
                            if(input_key<min_q)min_q<=input_key;""")
    text=edit(text,'base_q<=0;count_q<=total_q;bank_q<=0;',"""base_q<=0;count_q<=total_q;bank_q<=0;
                    if(PRECOUNT_CHILDREN && total_q>CAPACITY && !error_o && !mem_error_i)begin
                        histogram_ready_q<=root_match;
                        if(shift_bits==GID_W+SEQ_W+18)root_window_q<=0;
                        else if(shift_bits==GID_W+SEQ_W+19)root_window_q<=1;
                        else root_window_q<=2;
                    end""")
    BUILD.mkdir(parents=True,exist_ok=True)
    path=BUILD/'autonomous_qsu.sv'
    freeze(path,text)
    return path,prior


def units(candidate_path):
    """Repeat exact-depth, shifted-depth, arbitrary keys and empty/leaf cases under backpressure."""
    out=OUT/'units_verilator'
    work=LOCAL/'units_verilator'
    work.mkdir(parents=True,exist_ok=True)
    out.mkdir(exist_ok=True)
    source=ROOT/'verification/rtl/tb_t06_qsu_bsu.sv'
    bench=out/source.name
    text=source.read_text()
    text=edit(text,'    initial begin\n        n=0;', '    integer hit_count=0;\n    always @(posedge clk) if(rst&&ending&&qsu.total_q>K&&qsu.root_match)hit_count++;\n    initial begin\n        n=0;')
    start='@(negedge clk);start=1;'
    text=edit(text,start,"for(integer frame=0;frame<2;frame++)begin\n        received=0;"+start)
    text=edit(text,'parallel_cycles);$finish;', 'parallel_cycles);end\n        $display("ROOT_HITS %0d",hit_count);$finish;')
    freeze(bench,text)
    files=[candidate_path,ROOT/'rtl/sort/bitonic_group_sorter_pipelined_shared.sv',
           ROOT/'rtl/control/shared_reconfigurable_pe_slice.sv',bench]
    exe=work/'simulation'
    verilator=read(FULL/'build/binary.json')['command'][0]
    run_logged([verilator,'--binary','--build','-j','2','--timing','--assert','-Wno-fatal','-DSYNTHESIS',
                '-DTB_QSU_PRECOUNT=1','-DT06_MAX_COUNT=512','--top-module',bench.stem,'--Mdir',str(work),
                '-o',exe.name,*map(str,files)],out/'build.log')
    cases={'empty':([],0),'leaf':([(0,i,8-i) for i in range(9)],0),
           'equal':([(0,5,1)]*39,0),'ties':([(0,i%7,68-i) for i in range(69)],0),
           'signed':([((-1 if i%2 else 1)*(i<<16),i%11,i) for i in range(65)],0)}
    for shift in (18,19,20):
        cases[f'depth{shift}']=([(((i*5)%8)<<shift | i,i%3,96-i) for i in range(97)],2 if shift==20 else 1)
    rows=[]
    for name,(values,hits) in cases.items():
        d=out/name
        d.mkdir(exist_ok=True)
        for filename,data in [('input',values),('expected',sorted(values))]:
            freeze(d/(filename+'.memh'),''.join(f'{((z&0x7ffffff)<<64)|(gid<<32)|seq:023x}\n' for z,gid,seq in data))
        execution=run_logged([str(exe),f'+N={len(values)}',f'+INPUT={d}/input.memh',f'+EXPECTED={d}/expected.memh'],d/'run.log',timeout=90)
        log=(d/'run.log').read_text()
        assert log.count('PASS T06')==2 and f'ROOT_HITS {hits}\n' in log
        reads=list(map(int,re.findall(r' reads=(\d+)',log)))
        if hits==1:
            assert reads[0]-reads[1]==len(values)
        rows.append(dict(case=name,frames=2,records=len(values),hits=hits,reads=reads,execution=execution,
                         inputs={f:sha(d/f) for f in ('input.memh','expected.memh')}))
    save(out/'report.json',dict(results=rows,sources={str(p):sha(p) for p in files},binary_sha256=sha(exe),signed_off=False))


def build(path,prior):
    cmd=prior['command'].copy()
    i=cmd.index('-f')+1
    files=Path(cmd[i]).read_text().splitlines()
    assert files.count(NAME)==1
    files[files.index(NAME)]=str(path)
    filelist=BUILD/'sources.f'
    freeze(filelist,'\n'.join(files)+'\n')
    cmd[i]=str(filelist)
    cmd[cmd.index('--Mdir')+1]=str(LOCAL)
    marker=BUILD/'binary.json'
    sources={**prior['sources'],str(path.relative_to(ROOT)):sha(path),str(filelist.relative_to(ROOT)):sha(filelist)}
    exe=LOCAL/'simulation'
    if marker.exists():
        info=read(marker)
        assert info['command']==cmd and info['sources']==sources and sha(exe)==info['elf_sha256']
    else:
        run_logged(cmd,BUILD/'build.log')
        info=dict(command=cmd,sources=sources,exe=str(exe),elf_sha256=sha(exe))
        save(marker,info)
    return info


def run_scene(scene,info):
    ref=FULL/'real'/scene/'f2'
    before=read(ref/'result.json')
    cmd=read(ref/'run.command.json')
    assert sha(ref/'launch.json')==before['hashes']['launch.json']
    launch=read(ref/'launch.json')
    assert launch['command']==cmd
    for a in cmd:
        k,_,v=a.partition('=')
        if k[1:] in ('ATTR','CAMERA','MEAN'):
            assert sha(v)==launch['input_sha256'][k[1:]]
    d=OUT/'real'/scene
    d.mkdir(parents=True,exist_ok=True)
    cmd[0]=info['exe']
    outputs=dict(FRAME='state.memh',RGB='rgb.memh',SORTED_TRACE='sorted.txt')
    cmd=['+'+k+'='+str(d/outputs[k]) if (k:=a.partition('=')[0][1:]) in outputs else a for a in cmd]
    config=dict(command=cmd,inputs=launch['input_sha256'],baseline_result_sha256=sha(ref/'result.json'),elf_sha256=info['elf_sha256'])
    marker=d/'launch.json'
    if marker.exists():
        assert read(marker)==config
    else:
        save(marker,config)
    ex=d/'run.execution.json'
    if ex.exists() and read(ex)['exit_code']==0:
        assert read(ex)['log_sha256']==sha(d/'run.log')
    else:
        run_logged(cmd,d/'run.log')
    log=(d/'run.log').read_text()
    assert 'PASS: tb_t08_dual_precision' in log and 'error=00000000' in log
    c=blocks(log)
    old=before['counters']
    for section in ('REAL_T08','REAL_QSU'):
        if section=='REAL_T08':
            assert c[section]==old[section]
        else:
            for field in ('enabled','input','partitions','leaves','writes','axi_writes','peak'):
                assert c[section][field]==old[section][field]
    trace=ref/'sorted.txt'
    assert sha(trace)==before['hashes']['sorted.txt']
    with trace.open('rb') as f:
        first=int(f.readline().split()[0]);f.seek(-min(512,trace.stat().st_size),2)
        last=int(f.read().splitlines()[-1].split()[0])
    hit=(first^last).bit_length()-3==20
    saved=old['REAL_QSU']['axi_reads']-c['REAL_QSU']['axi_reads']
    assert saved==(c['REAL_QSU']['input'] if hit else 0)
    assert c['REAL_QSU']['reads']==c['REAL_QSU']['axi_reads']
    for name in ('rgb.memh','sorted.txt'):
        assert sha(d/name)==before['hashes'][name]
    assert sha(ref/'state.memh')==before['hashes']['state.memh']
    t=compare_states(d/'state.memh',ref/'state.memh')
    # Recover the image directly from this run's RGB DMA.
    from scripts.read_rgb888_frame import decode_rgb888
    from PIL import Image
    rgb=decode_rgb888(bytes.fromhex((d/'rgb.memh').read_text()),before['width'],before['height'])
    Image.fromarray(rgb).save(d/'frame.png')
    assert sha(d/'frame.png')==before['hashes']['frame.png'] and Image.open(d/'frame.png').tobytes()==rgb.tobytes()
    result=dict(scene=scene,cold_hit=hit,saved_reads=saved,cycle_delta=c['REAL_END_TO_END']['command_cycles']-before['command_cycles'],
                terminal_t_differences=t,counters=c,execution=read(ex),reference_mae=before['internal_float_mae'],
                hashes={name:sha(d/name) for name in ('rgb.memh','sorted.txt','state.memh','frame.png','launch.json')})
    save(d/'result.json',result)
    return result


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            save(OUT/'status.json',dict(status='UNITS_AND_BUILD',pid=os.getpid(),signed_off=False))
            candidate_path,baseline=candidate()
            units(candidate_path)
            binary=build(candidate_path,baseline)
            save(OUT/'status.json',dict(status='RUNNING_FULL128_Q24',pid=os.getpid(),signed_off=False))
            with ThreadPoolExecutor(max_workers=2) as pool:
                rows=list(pool.map(lambda s:run_scene(s,binary),['train','truck',*[s for s in SCENES if s not in ('train','truck')]]))
            assert all(sha(ROOT/p)==h for p,h in binary['sources'].items())
            save(OUT/'report.json',dict(results=rows,script_sha256=sha(__file__),signed_off=False,
                 scope='Width128 complete models, Q24 compact, G/legacy-ideal, cold frames. Exact root-window validation; original fallback on mismatch.'))
            save(OUT/'status.json',dict(status='FULL128_QSU_COMPARED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise
