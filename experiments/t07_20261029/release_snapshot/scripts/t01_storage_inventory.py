"""Inventory actual generic sequential/memory bits through the hierarchy."""
import argparse,collections,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,read,save,sha
def integer(s):
    s=s.strip()
    if "'" in s:
        width,value=s.split("'",1);assert not any(c in value for c in 'xz');return int(value,2)
    return int(s)
def main():
    p=argparse.ArgumentParser();p.add_argument('--alpha',type=int,default=1);a=p.parse_args()
    out=BASE/'synthesis'/f'alpha{a.alpha}';meta=read(out/'coarse.json');path=Path(meta['artifact'])
    assert sha(path)==meta['artifact_sha256'];mods={};module=None;cell=None
    with path.open() as f:
        for line in f:
            if line.startswith('module '):module=line.split(None,1)[1].strip();mods[module]=dict(ff_bits=0,latch_bits=0,memories=[],children=collections.Counter())
            elif line.startswith('  cell '):
                _,kind,name=line.strip().split(None,2);cell=dict(type=kind,name=name,params={})
            elif cell and line.startswith('    parameter '):
                s=line.strip().split(None,2);cell['params'][s[1].lstrip('\\')]=s[2]
            elif cell and line=='  end\n':
                c=cell;cell=None;t=c['type'];params=c['params'];m=mods[module]
                if t=='$mem_v2':
                    row={k:integer(params[k]) for k in ['WIDTH','SIZE','RD_PORTS','WR_PORTS']};row['name']=c['name'];row['bits']=row['WIDTH']*row['SIZE'];m['memories'].append(row)
                elif t.startswith('$') and ('dff' in t.lower() or t in ['$ff']):m['ff_bits']+=integer(params.get('WIDTH','1'))
                elif t.startswith('$') and 'latch' in t.lower():m['latch_bits']+=integer(params.get('WIDTH','1'))
                elif not t.startswith('$') or t.startswith('$paramod'):m['children'][t]+=1
    counts=collections.Counter()
    def visit(name,mult,stack):
        assert name not in stack,('recursive hierarchy',name)
        counts[name]+=mult
        for child,n in mods[name]['children'].items():
            if child in mods:visit(child,mult*n,stack+[name])
    visit('\\gs_accel_system_top',1,[])
    rows=[]
    for name,n in counts.items():
        m=mods[name];rows.append(dict(module=name,instances=n,ff_bits_each=m['ff_bits'],latch_bits_each=m['latch_bits'],memories=m['memories'],total_ff_bits=n*m['ff_bits'],total_memory_bits=n*sum(x['bits'] for x in m['memories'])))
    report=dict(status='GENERIC_STORAGE_INVENTORY',source_sha256=meta['source_sha256'],coarse_sha256=meta['artifact_sha256'],
      ff_bits=sum(r['total_ff_bits'] for r in rows),generic_memory_bits=sum(r['total_memory_bits'] for r in rows),rows=rows,
      scope='Actual retained generic state including arithmetic/control pipelines; not an SRAM macro capacity/area or final 300KB signoff')
    save(out/'storage_inventory.json',report);print({k:report[k] for k in ['status','ff_bits','generic_memory_bits']})
if __name__=='__main__':main()
