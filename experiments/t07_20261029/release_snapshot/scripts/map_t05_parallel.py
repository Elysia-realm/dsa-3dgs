"""Explicit four-way spatial/folded K8/K16 comparison, no old netlist reuse."""
import sys,json,hashlib
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import map_t05_modules as mapper
def main():
    mapper.OUT=ROOT/'experiments/t05_parallel_20261011/mapping'
    mapper.SOURCES.append('rtl/sort/bitonic_group_sorter_pipelined_shared.sv')
    previous=mapper.OUT/'report.json'
    if previous.exists():
        prior=json.loads(previous.read_text())
        for p,h in prior['source_sha256'].items():
            if hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=h:
                raise RuntimeError('Mapping source changed; use a fresh output directory: '+p)
        for lib in prior.get('libraries',{}).values():
            if hashlib.sha256(Path(lib['path']).read_bytes()).hexdigest()!=lib['sha256']:
                raise RuntimeError('Mapping library changed; old netlist cannot be reused')
    cases=[]
    for k in (8,16):
        params={'CAPACITY':k,'DEPTH_W':27,'GID_W':32,'SEQ_W':16,'PAYLOAD_W':1,'COMPARE_LANES':4}
        cases.extend([(f'fold{k}','bitonic_group_sorter_shared',params),(f'pipe{k}','bitonic_group_sorter_pipelined_shared',params)])
    mapper.OUT.mkdir(parents=True,exist_ok=True);rows=[]
    with ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(mapper.mapped,cases):rows+=result
    report={'status':'PASS','results':rows,'scope':'isolated BSU including buffers/counters, common external PE excluded, TT only; no chip STA or power signoff',
        'source_sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in mapper.SOURCES},
        'libraries':{pdk:{'path':str(lib),'sha256':hashlib.sha256(lib.read_bytes()).hexdigest()} for pdk,lib,_,_ in mapper.LIBS},
        'yosys_executable_sha256':hashlib.sha256(mapper.YOSYS.read_bytes()).hexdigest()}
    (mapper.OUT/'report.json').write_text(json.dumps(report,indent=2))
if __name__=='__main__':main()
