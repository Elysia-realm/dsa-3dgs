"""Separate native workload service floors from unresolved memory architecture."""
import re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,SCENES,read,save,sha

def main():
    rows=[]
    for scene in SCENES:
        d=BASE/'diagnostic/native'/scene;input=read(BASE/'inputs/native'/scene/'manifest.json')
        full=(d/'result.json').exists();cycles=None;grants=None;skip=None
        if full:
            r=read(d/'result.json');p=r['counters']['REAL_PERF'];reads=p['state_reads'];writes=p['state_writes']
            cycles=r['command_cycles'];grants=r['counters']['REAL_SHARED_PE']['R'];skip=r['counters']['REAL_T07_TERMINATION']
        else:
            line=next(x for x in (d/'run.log').read_text().splitlines() if x.startswith('TIMEOUT perf '))
            p={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)};reads=p['reads'];writes=p['writes']
        w,h=input['width'],input['height'];blocks=((w+7)//8)*((h+7)//8)
        rows.append(dict(scene=scene,complete_frame=full,width=w,height=h,cycles=cycles,
          state_transfer_bytes=16*(reads+writes),state_GBps_at_30FPS=16*(reads+writes)*30/1e9,
          state_bytes_scope='render state only; excludes final RGB scan and all other DMA; timeout rows are partial lower bounds',
          shared_R_grants=grants,shared_R_single_service_budget_ratio=grants/(200000000/30) if grants else None,
          termination_counters=skip,full_pixel_bitmap_bytes=(w*h+7)//8,
          coarse_count7_payload_bytes=(blocks*7+7)//8,coarse_count7_plus_epoch16_bytes=(blocks*23+7)//8,
          log_sha256=sha(d/'run.log')))
    save(BASE/'recovery_20261107/native_service_budget.json',dict(status='NECESSARY_BUDGET_NOT_PHYSICAL_SIGNOFF',
       rows=rows,assumed_frequency_MHz=200,frequency_verified=False,
       existing_array_payload_bytes=dict(state_cache_4096=4096*(32+16+39+16+1)//8,termination_256=(256*97+7)//8),
       total_storage_pass=None,limitations=['Array subtotals exclude queues, replicated ports, QSU, BSU, auxiliary pipelines and controls',
       'No sustainable DDR rate or CACTI macro costs claimed','R grant budget and memory traffic are separate overlapping constraints; do not sum'],signed_off=False))
    for r in rows:print(r['scene'],round(r['state_GBps_at_30FPS'],2),'GB/s state',r['shared_R_single_service_budget_ratio'],flush=True)

if __name__=='__main__':main()
