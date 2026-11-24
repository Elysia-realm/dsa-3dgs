"""Count actual mapped library cells through hierarchy, rejecting unknown primitives."""
import argparse,collections,math,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,read,save,sha
def library_areas(path):
    areas={};cell=None
    with path.open() as f:
        for line in f:
            m=re.match(r'\s*cell\s*\(\s*"?([^\s"\)]+)',line)
            if m:cell=m[1]
            m=re.match(r'\s*area\s*:\s*([\d.eE+-]+)',line)
            if cell and m:areas[cell]=float(m[1]);cell=None
    assert areas and all(math.isfinite(v) and v>=0 for v in areas.values());return areas
def main():
    p=argparse.ArgumentParser();p.add_argument('--alpha',type=int,required=True);p.add_argument('--pdk',required=True);a=p.parse_args()
    dest=BASE/'synthesis'/f'alpha{a.alpha}'/a.pdk;m=read(dest/'mapping.json');stats=read(dest/'mapped_stat.json')
    areas=library_areas(Path(m['liberty']));mods={k.lstrip('\\'):v for k,v in stats['modules'].items()}
    leaf=collections.Counter();instances=collections.Counter();unknown=collections.Counter()
    def visit(name,mult,stack):
        assert name not in stack,('recursive hierarchy',name);instances[name]+=mult
        for t,n in mods[name]['num_cells_by_type'].items():
            t=t.lstrip('\\')
            if t in areas:leaf[t]+=n*mult
            elif t in mods:visit(t,n*mult,stack+[name])
            else:unknown[t]+=n*mult
    visit('gs_accel_system_top',1,[])
    area=sum(n*areas[t] for t,n in leaf.items());module_rows=[]
    for name,n in instances.items():
        local=sum(c*areas.get(t.lstrip('\\'),0) for t,c in mods[name]['num_cells_by_type'].items())
        module_rows.append(dict(module=name,instances=n,own_area_um2=local,total_own_area_um2=n*local))
    assert abs(sum(r['total_own_area_um2'] for r in module_rows)-area)<max(1,area)*1e-8
    design_area=stats.get('design',{}).get('area')
    if design_area is not None:assert abs(design_area-area)<max(1,area)*1e-5,(design_area,area)
    result=dict(status='PASS_LIBRARY_COVERAGE' if not unknown else 'FAIL_UNKNOWN_CELLS',pdk=a.pdk,alpha=a.alpha,
      standard_cell_area_um2=area,standard_cell_area_mm2=area/1e6,library_cell_instances=sum(leaf.values()),
      leaf_cells=dict(leaf),module_costs=sorted(module_rows,key=lambda r:-r['total_own_area_um2']),unknown_cells=dict(unknown),
      netlist_sha256=m['netlist_sha256'],liberty_sha256=m['liberty_sha256'],mapped_stat_sha256=sha(dest/'mapped_stat.json'),
      storage_included='All retained state/control from original RTL mapped to standard cells; no SRAM macro',
      final_asic_area_pass=False)
    save(dest/'mapping_audit.json',result)
    assert not unknown,unknown
    print(a.pdk,a.alpha,area/1e6,sum(leaf.values()),flush=True)
if __name__=='__main__':main()
