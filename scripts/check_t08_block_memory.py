"""Inspect inferred termination arrays and a byte-padded two-array CACTI implementation option."""
import math
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from asic.scripts.run_t01_wsl_synthesis import YOSYS,q,run_stage
from scripts.run_t08_terminated_blocks import OUT,RTL
from scripts.run_t08_precision_rgb import freeze
from scripts.t08_common import read,save,sha,run_logged


def main():
    d=OUT/'memory'
    d.mkdir(exist_ok=True)
    binary=read(OUT/'build/binary.json')
    assert binary['sources'][str(RTL.relative_to(ROOT))]==sha(RTL)
    net=d/'inferred.json'
    execution=run_stage('inference',[f'read_verilog -sv {q(RTL)}','hierarchy -check -top terminated_block_counter',
                        'proc','opt','memory -nomap','opt_clean','check -assert',f'write_json {q(net)}'],d)
    module=read(net)['modules']['terminated_block_counter']
    arrays={}
    for name,cell in module['cells'].items():
        if cell['type']!='$mem_v2':
            continue
        fields=['WIDTH','SIZE','RD_PORTS','WR_PORTS','RD_CLK_ENABLE','WR_CLK_ENABLE']
        arrays[name]={k:int(cell['parameters'][k],2) for k in fields}
    assert set(arrays)=={'counts','full'},arrays
    assert all(r['SIZE']==32768 for r in arrays.values())
    assert arrays['full']['WIDTH']==1 and arrays['counts']['WIDTH']==6
    logical_bytes=sum(r['WIDTH']*r['SIZE'] for r in arrays.values())//8
    template=ROOT/'experiments/environment_setup_20261024/cacti_sram_diagnostic.cfg'
    cfg=d/'sram_bytewide.cfg'
    settings={'-size (bytes)':'32768','-block size (bytes)':'1','-read-write port':'0',
              '-exclusive read port':'1','-exclusive write port':'1','-output/input bus width':'8'}
    text=template.read_text()
    for key,value in settings.items():
        text,count=re.subn('^'+re.escape(key)+r' [0-9]+$',key+' '+value,text,flags=re.M)
        assert count==1,key
    freeze(cfg,text)
    wrapper=Path.home()/'eda/bin/cacti'
    exe=Path.home()/'eda/src-20261024/cacti/cacti'
    model=run_logged([str(wrapper),'-infile',str(cfg)],d/'cacti.log')
    log=(d/'cacti.log').read_text()
    number=r'([\d.eE+\-]+)'
    fields={}
    for key,heading in [('access_ns','Access time (ns)'),('cycle_ns','Cycle time (ns)'),
                        ('read_nJ','Total dynamic read energy per access (nJ)'),
                        ('write_nJ','Total dynamic write energy per access (nJ)'),
                        ('leakage_mW','Total leakage power of a bank (mW)')]:
        match=re.search(re.escape(heading)+r':\s*'+number,log)
        assert match,key
        fields[key]=float(match[1])
    dimensions=re.search(r'Cache height x width \(mm\):\s*'+number+r'\s*x\s*'+number,log)
    assert dimensions
    fields['area_mm2']=float(dimensions[1])*float(dimensions[2])
    assert all(math.isfinite(v) and v>0 for v in fields.values())
    save(d/'report.json',dict(arrays=arrays,inference=execution,inferred_logical_bytes=logical_bytes,
         padded_model_bytes=2*32768,settings=settings,model_per_array=fields,
         two_array_area_mm2=2*fields['area_mm2'],cacti=model,
         hashes={str(p):sha(p) for p in [RTL,Path(__file__),YOSYS,net,template,cfg,wrapper,exe]},
         scope='Generic 45nm 300K one-read/one-write 32768x8 RAM option per array. Counts and flags separately byte padded, full flag requires same-cycle random read. No macro substitution, IO timing signoff, control area or per-frame power.',signed_off=False))
    print(arrays,fields,flush=True)


if __name__=='__main__':
    main()
