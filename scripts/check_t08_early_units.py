"""Same-source off/on DMA protocol and service-cycle comparison."""
import sys,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,WORK,read,save,sha,run_logged
def main():
    out=BASE/'early_advance_20261107/units';out.mkdir(parents=True,exist_ok=True)
    s=(ROOT/'verification/rtl/tb_t08_attribute_dma.sv').read_text()
    s=s.replace('module tb_t08_attribute_dma;','module tb_t08_attribute_dma;\n parameter EARLY=0;longint unsigned cycles=0;always @(posedge clk_i)if(rst_ni)cycles<=cycles+1;')
    s=s.replace('axi4_t08_attribute_read_engine dut(.*);','axi4_t08_attribute_read_engine #(.EARLY_ADVANCE(EARLY))dut(.*);')
    s=s.replace('$display("T08_DMA_DATA records=', '$display("T08_DMA_SERVICE cycles=%0d",cycles);\n    $display("T08_DMA_DATA records=')
    tb=out/'tb_t08_attribute_dma.sv';tb.write_text(s)
    old=BASE/'dma_20261107';v=read(BASE/'build/native/binary.json')['command'][0];rows=[]
    for enabled in [0,1]:
        d=out/str(enabled);w=WORK/'early_advance_20261107/units'/str(enabled);w.mkdir(parents=True,exist_ok=True)
        run_logged([v,'--binary','--build','-j','2','--timing','--assert','-Wno-fatal','--top-module','tb_t08_attribute_dma',f'-GEARLY={enabled}',
          '--Mdir',str(w),'-o','simulation','rtl/dma/t08_attribute_decoder.sv','rtl/dma/axi4_t08_attribute_read_engine.sv',str(tb)],d/'build.log')
        run_logged([str(w/'simulation'),'+N=6144','+INPUT='+str(old/'input.memh'),'+EXPECTED='+str(old/'expected.memh')],d/'run.log')
        log=(d/'run.log').read_text();assert 'PASS T08 attribute DMA data_records=6144 control_cases=9' in log and 'beats=49172 ' in log
        rows.append(dict(enabled=enabled,cycles=int(re.search(r'T08_DMA_SERVICE cycles=(\d+)',log)[1]),status='PASS',log_sha256=sha(d/'run.log')))
    save(out/'report.json',dict(status='PASS',results=rows,signed_off=False,source_sha256={str(p.relative_to(ROOT)):sha(p) for p in [ROOT/'rtl/dma/axi4_t08_attribute_read_engine.sv',ROOT/'rtl/dma/t08_attribute_decoder.sv',tb]}))
    print(rows,flush=True)
if __name__=='__main__':main()
