"""Extract complete local timing summaries without treating generation as closure."""
import re,sys,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t07_common import BASE,read,save,sha

def main():
    rows=[]
    for pixel in [0,1]:
        for pdk in ['nangate45','icsprout55']:
            d=BASE/'mapping'/f'pixel{pixel}'/pdk;r=read(d/'result.json');text=(d/'sta.log').read_text()
            assert sha(d/'mapped.v')==r['netlist_sha256'] and sha(d/'sta.log')==r['sta_log_sha256']
            slacks=dict((kind,float(v)) for kind,v in re.findall(r'worst slack (max|min)\s+(-?[\d.]+)',text))
            assert set(slacks)=={'max','min'}
            electrical=text.split('T01_BEGIN_ELECTRICAL')[1].split('T01_STA_REPORT_END')[0]
            reported=[line.strip() for line in electrical.splitlines() if 'VIOLATED' in line]
            r.update(setup_wns_ns=slacks['max'],hold_wns_ns=slacks['min'],electrical_reported_violations=reported,
                     electrical_count_scope='Printed entries only; original reporter caps output at 40, not an exhaustive violation count',
                     timing_closure=False,whole_chip_frequency_verified=False)
            rows.append(r)
    comparisons=[]
    for pdk in ['nangate45','icsprout55']:
        old=next(r for r in rows if r['pdk']==pdk and r['pixel_skip']==0)
        new=next(r for r in rows if r['pdk']==pdk and r['pixel_skip']==1)
        comparisons.append(dict(pdk=pdk,old_area_mm2=old['area_mm2'],new_area_mm2=new['area_mm2'],
          saved_area_mm2=old['area_mm2']-new['area_mm2'],saved_percent=100*(old['area_mm2']-new['area_mm2'])/old['area_mm2'],
          old_dff_cells=sum(v for k,v in old['cell_types'].items() if 'DFF' in k),
          new_dff_cells=sum(v for k,v in new['cell_types'].items() if 'DFF' in k)))
    save(BASE/'mapping/audit.json',dict(status='PASS_LOCAL_EVIDENCE_AUDIT',results=rows,comparisons=comparisons,
      whole_chip_ppa_pass=False,scope='Both actual termination alternatives, TT, same 292-bit payload and interface constraints. Local area benefit only, not whole-chip timing closure.'))
    print(comparisons)
if __name__=='__main__':main()
