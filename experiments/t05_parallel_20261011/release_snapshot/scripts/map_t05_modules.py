"""Bounded TT module comparison using the already installed T01 tools/libs."""
import sys,json,re,hashlib
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from asic.scripts.run_t01_synthesis import run_yosys,quote,liberty_cells,parse_delays
OUT=ROOT/'experiments/t05_20261009/mapping'
YOSYS=ROOT/'tmp/toolchains/oss-cad-suite-20260706/oss-cad-suite/bin/yosys.exe'
LIBS=[('nangate45',ROOT/'tmp/toolchains/freepdk45/NangateOpenCellLibrary_typical.lib','BUF_X4',3.899),
      ('icsprout55',ROOT/'tmp/toolchains/icsprout55/rvt-v1.10.102/liberty/ics55_LLSC_H7CR_typ_tt_1p2_25_nldm.lib','BUFX1H7R',3.53997)]
SOURCES=['rtl/common/rv_reg_slice.sv','rtl/sort/bitonic_group_sorter_shared.sv',
         'rtl/sort/stable_group_sorter_shared_compare.sv','rtl/sort/stable_group_sorter_parallel_shared.sv','rtl/raster/blend_fixed_core.sv',
         'rtl/control/shared_reconfigurable_pe_slice.sv']
def mapped(case):
    name,top,params=case;folder=OUT/name;folder.mkdir(parents=True,exist_ok=True)
    script=folder/'generic.ys';il=folder/'generic.il'
    lines=['read_verilog -sv -DSYNTHESIS '+' '.join(quote(ROOT/p) for p in SOURCES),
           'chparam '+' '.join(f'-set {k} {v}' for k,v in params.items())+' '+top,
           f'hierarchy -check -top {top}',f'rename {top} t05_dut','synth -top t05_dut -flatten -noabc',
           'check -assert',f'write_rtlil {quote(il)}']
    script.write_text('\n'.join(lines)+'\n')
    if il.exists():rc,seconds=0,0
    else:rc,seconds=run_yosys(YOSYS,script,folder/'generic.log',ROOT)
    if rc:raise RuntimeError(f'generic mapping failed {name}: '+(folder/'generic.log').read_text()[-2000:])
    results=[]
    for pdk,lib,driver,load in LIBS:
        target=folder/pdk;target.mkdir(exist_ok=True)
        constr=target/'abc.constr';constr.write_text(f'set_driving_cell {driver}\nset_load {load}\n')
        abc=target/'abc.script';abc.write_text('strash\ndc2\nmap\ncleanup\nbuffer\nupsize -D 5000\ndnsize -D 5000\nstime -p\n')
        ys=target/'map.ys';stats=target/'stats.json';net=target/'mapped.v'
        ys.write_text('\n'.join([f'read_rtlil {quote(il)}','delete t:$scopeinfo',f'read_liberty -lib {quote(lib)}',
            f'dfflibmap -liberty {quote(lib)}',f'abc -script {quote(abc)} -liberty {quote(lib)} -constr {quote(constr)} -D 5000',
            'clean','check -assert',f'tee -o {quote(stats)} stat -json -liberty {quote(lib)}',f'write_verilog -noattr -noexpr {quote(net)}'])+'\n')
        if stats.exists() and net.exists() and '$scopeinfo' not in stats.read_text():rc,elapsed=0,0
        else:rc,elapsed=run_yosys(YOSYS,ys,target/'map.log',ROOT)
        if rc:raise RuntimeError(f'target mapping failed {name}/{pdk}: '+(target/'map.log').read_text()[-2000:])
        stat=json.loads(stats.read_text())['modules']['\\t05_dut'];types=stat['num_cells_by_type']
        unknown=set(types)-liberty_cells(lib)
        if unknown:raise RuntimeError(f'unmapped cells: {unknown}')
        result={'name':name,'pdk':pdk,'top':top,'parameters':params,'corner':'TT','requested_clock_mhz':200,
                'cell_count':int(stat['num_cells']),'area_um2':float(stat['area']),
                'sequential_area_um2':float(stat['sequential_area']),
                'abc_max_module_delay_ps':max(parse_delays(target/'map.log'),default=None),'unmapped_cells':list(unknown),
                'seconds':elapsed,'netlist_sha256':hashlib.sha256(net.read_bytes()).hexdigest()}
        results.append(result);print(json.dumps(result),flush=True)
    return results
def main():
    previous=OUT/'report.json'
    if previous.exists():
        old=json.loads(previous.read_text())
        if old.get('status')=='PASS':
            for relative,expected in old['source_sha256'].items():
                if hashlib.sha256((ROOT/relative).read_bytes()).hexdigest()!=expected:
                    raise RuntimeError(f'Source changed: {relative}; use a fresh mapping output directory, do not reuse old netlists')
    cases=[]
    for k in (8,16):
        params={'CAPACITY':k,'DEPTH_W':27,'GID_W':32,'SEQ_W':16,'PAYLOAD_W':1}
        cases += [(f'bsu{k}','bitonic_group_sorter_shared',params|{'COMPARE_LANES':4}),
                  (f'linear{k}','stable_group_sorter_shared_compare',params),
                  (f'odd{k}','stable_group_sorter_parallel_shared',params|{'COMPARE_LANES':4,'ENABLE_SERIAL_FALLBACK':0,'ENABLE_MONOTONIC_FASTPATH':0,'ENABLE_STABLE_RUN_FASTPATH':0,'ENABLE_BATCH_FORWARDING':0,'ENABLE_PHASE_FORWARDING':0})]
    cases += [('blend_local','blend_fixed_core',{'META_W':128,'USE_SHARED_RASTER_PE':0}),
              ('blend_shared','blend_fixed_core',{'META_W':128,'USE_SHARED_RASTER_PE':1}),
              ('blend_local_prod','blend_fixed_core',{'META_W':204,'USE_SHARED_RASTER_PE':0}),
              ('blend_shared_prod','blend_fixed_core',{'META_W':204,'USE_SHARED_RASTER_PE':1}),
              ('shared_pe','shared_reconfigurable_pe_slice',{'DATA_W':32,'GID_W':32,'SEQ_W':16})]
    OUT.mkdir(parents=True,exist_ok=True);results=[]
    with ThreadPoolExecutor(max_workers=2) as pool:
        for rows in pool.map(mapped,cases):
            results+=rows;(OUT/'report.json').write_text(json.dumps({'status':'IN_PROGRESS','results':results},indent=2))
    (OUT/'report.json').write_text(json.dumps({'status':'PASS','scope':'module boundary, external shared PE excluded equally; no STA/power/full-chip signoff',
      'results':results,'source_sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in SOURCES},
      'libraries':{pdk:{'path':str(lib),'sha256':hashlib.sha256(lib.read_bytes()).hexdigest()} for pdk,lib,_,_ in LIBS}},indent=2))
if __name__=='__main__':main()
