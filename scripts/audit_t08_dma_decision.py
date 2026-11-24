"""Bind each gate result to its mapped netlist, vectors and successful log."""
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_early_advance import OUT,matching_source
from scripts.t08_common import BASE,WORK,read,save,sha


def main():
    sources,_=matching_source()
    full=read(OUT/'full_report.json')
    assert sha(OUT/'full_report.json')==read(OUT/'full_audit.json')['report_sha256']
    assert len(full['results'])==20
    for row in full['results']:
        directory=OUT/'real/full'/str(row['early_advance'])/row['scene']/row['case']
        assert row['execution']['exit_code']==0
        assert all(sha(directory/f)==digest for f,digest in row['outputs'].items())
    gates=[]
    for pdk,kind,n in [('nangate45','gate_functional',6144),('nangate45','gate_sample',159),('icsprout55','gate_sample',159)]:
        folder=OUT/'mapping'/pdk/kind
        report=read(folder/'report.json')
        data=BASE/'dma_20261107' if kind=='gate_functional' else folder
        # The full suite started before sample-specific vector hashes were
        # added to the summary. Bind its saved commands to the frozen oracle.
        vector_manifest=read(data/'report.json') if kind=='gate_functional' else report
        assert sha(data/'input.memh')==vector_manifest['vectors_sha256']
        assert sha(data/'expected.memh')==vector_manifest['expected_sha256']
        assert {r['early_advance'] for r in report['results']}=={0,1} and len(report['results'])==2
        for r in report['results']:
            opt=str(r['early_advance'])
            d=folder/opt
            cmd=read(d/'run.command.json')
            assert f'+N={n}' in cmd and '+INPUT='+str(data/'input.memh') in cmd and '+EXPECTED='+str(data/'expected.memh') in cmd
            mapped=folder.parent/opt
            mapping=read(mapped/'result.json')
            assert all(sources[f]==h for f,h in r['source_sha256'].items())
            assert mapping['netlist_sha256']==sha(mapped/'mapped.v')==r['netlist_sha256']
            assert mapping['liberty_sha256']==r['liberty_sha256']
            assert sha(WORK/OUT.name/kind/pdk/f'with_cell_logic_{opt}.v')==r['with_cell_logic_sha256']
            assert sha(ROOT/'verification/rtl/tb_t08_attribute_dma.sv')==r['bench_sha256']
            ex=read(d/'run.execution.json')
            assert ex==r['execution'] and ex['exit_code']==0 and ex['log_sha256']==sha(d/'run.log')
            assert f'PASS T08 attribute DMA data_records={n} control_cases=9' in (d/'run.log').read_text()
        gates.append(dict(pdk=pdk,suite=kind,vectors_per_configuration=n,report_sha256=sha(folder/'report.json')))
    save(OUT/'candidate_decision.json',dict(status='ACCEPT_FOR_T08_DEVELOPMENT',signed_off=False,
        qualified_parameters=dict(ENABLE_COMPRESSED_ATTRIBUTES=1,ATTR_DMA_EARLY_ADVANCE=1),
        full_width128_audit_sha256=sha(OUT/'full_audit.json'),local_mapping_sha256=sha(OUT/'mapping/report.json'),
        gates=gates,open_conditions=['native formal GT','native 30FPS with verified timing and shared DDR',
        'state traffic and QSU/R service rates','local minimum timing violations and final resource budget']))
    print('PASS 20 full-model evidence sets and 6 gate suites; DMA option accepted for development')


if __name__=='__main__':main()
