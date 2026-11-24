"""Drive nine differently ranged QSU frames without a reset and compare independent sorted keys."""
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_qsu_root_precount import OUT as CANDIDATE
from scripts.run_t08_precision_rgb import freeze
from scripts.run_t08_q24_compact import edit
from scripts.t08_common import WORK,read,save,sha,run_logged

OUT=CANDIDATE/'window_changes'


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    one=CANDIDATE/'units_verilator'
    report=read(one/'report.json')
    for p,h in report['sources'].items():
        assert sha(p)==h
    old=one/'tb_t06_qsu_bsu.sv'
    top='tb_t08_qsu_window_changes'
    bench=OUT/(top+'.sv')
    text=old.read_text().replace(old.stem,top)
    text=edit(text,'frame<2','frame<9')
    seq=[]
    sizes=[]
    for i,shift in enumerate([18,18,19,20,20,None,18,20,19]):
        data=[((((j*5)%8)<<shift)|j,j%7,96-j) for j in range(97)] if shift else []
        if i==8:
            # The last accepted record changes the true root from the forecast range.
            data.append((-(1<<25),3,400))
        seq.append(data)
        sizes.append(len(data))
        for name,records in [('input',data),('expected',sorted(data))]:
            freeze(OUT/f'{i}_{name}.memh',''.join(f'{((d&0x7ffffff)<<64)|(g<<32)|s:023x}\n' for d,g,s in records))
    load='case(frame)\n'+'\n'.join(f'{i}:n={n};' for i,n in enumerate(sizes))+'\nendcase\n'
    load+='''if(n>0)begin
            $readmemh($sformatf("%s/%0d_input.memh",input_path,frame),vectors,0,n-1);
            $readmemh($sformatf("%s/%0d_expected.memh",input_path,frame),expected,0,n-1);
        end
        '''
    text=edit(text,'received=0;@(negedge clk);start=1;',load+'received=0;@(negedge clk);start=1;')
    text=edit(text,'parallel_cycles);end','parallel_cycles);$display("WINDOW_FRAME %0d %0d",frame,hit_count);end')
    freeze(bench,text)
    orig=read(one/'build.command.json')
    cmd=orig.copy()
    work=WORK/CANDIDATE.name/'window_changes'
    work.mkdir(parents=True,exist_ok=True)
    cmd[cmd.index('--Mdir')+1]=str(work)
    cmd[cmd.index('--top-module')+1]=top
    cmd[cmd.index(str(old))]=str(bench)
    run_logged(cmd,OUT/'build.log')
    exe=work/'simulation'
    ex=run_logged([str(exe),'+N=0',f'+INPUT={OUT}',f'+EXPECTED={OUT}'],OUT/'run.log',timeout=90)
    log=(OUT/'run.log').read_text()
    got=[(int(i),int(n)) for i,n in re.findall(r'WINDOW_FRAME (\d+) (\d+)',log)]
    predicted=20
    count=0
    results=[]
    for i,data in enumerate(seq):
        keys=[((z+(1<<26))<<64)|(g<<32)|s for z,g,s in data]
        actual=(max(keys)^min(keys)).bit_length()-3-64 if keys else None
        hit=bool(keys) and actual==predicted
        count+=int(hit)
        assert got[i]==(i,count)
        results.append(dict(frame=i,records=len(data),predicted=predicted,actual_depth_shift=actual,hit=hit))
        if keys:
            predicted=actual if actual in (18,19) else 20
    assert len(got)==len(results) and log.count('PASS T06')==len(results) and count>0
    save(OUT/'report.json',dict(results=results,execution=ex,elf_sha256=sha(exe),bench_sha256=sha(bench),
         script_sha256=sha(__file__),rtl_sources=report['sources'],vectors={p.name:sha(p) for p in OUT.glob('*.memh')},signed_off=False))


if __name__=='__main__':
    main()
