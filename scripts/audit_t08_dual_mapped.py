"""Bind the eight mapped DMA runs to the frozen netlists and both mixed-format RTL decks."""
from itertools import product
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.check_t08_dual_mapped import OUT, COST, DUAL
from scripts.t08_common import BASE,read,save,sha


def main():
    run = read(OUT/'report.json')
    assert read(OUT/'status.json')['status']=='PASS_ZERO_DELAY_MAPPED_FUNCTION'
    assert run['script_sha256']==sha(ROOT/'scripts/check_t08_dual_mapped.py')
    oracle = BASE/'dma_20261107/expected.memh'
    rtl = {r['variant']:r for r in read(DUAL/'protocol/report.json')['results'] if r['enabled']}
    assert set(rtl)=={0,1}
    expect = read(BASE/'dma_20261107/report.json')['expected_sha256']
    assert sha(oracle)==expect
    all_cells = list(product(('nangate45','icsprout55'),(False,True),(0,1)))
    results = {(r['pdk'],r['sample'],r['variant']):r for r in run['results']}
    assert len(run['results'])==len(results)==8 and set(results)==set(all_cells)
    indices=[scene*1024+i for scene in range(5) for i in range(16)]+list(range(5120,6144,13))
    rows=[]
    for pdk in ('nangate45','icsprout55'):
        build = run['builds'][pdk]
        assert build==read(OUT/pdk/'build.json')
        assert all(sha(p)==h for p,h in build['inputs'].items())
        assert sha(build['exe'])==build['binary_sha256']
        assert sha(Path(build['exe']).with_name('cells.v'))==build['cells_sha256']
        mapped = str(COST/pdk/'mapped.v')
        assert build['inputs'][mapped]==read(COST/pdk/'result.json')['hashes'][mapped]
        for name in ('cell_models','build'):
            ex=read(OUT/pdk/(name+'.execution.json'))
            assert ex['exit_code']==0 and ex['log_sha256']==sha(OUT/pdk/(name+'.log'))
        for sample,variant in product((False,True),(0,1)):
            r=results[pdk,sample,variant]
            d=OUT/pdk/('probe' if sample else 'full')/str(variant)
            assert r==read(d/'result.json') and r['config']==read(d/'launch.json')
            cfg=r['config']
            cmd=read(d/'run.command.json')
            assert cfg['command']==cmd and cfg['binary_sha256']==build['binary_sha256']
            assert cmd[:2]==['/usr/bin/vvp',build['exe']]
            data,expected=[Path(next(a.split('=',1)[1] for a in cmd if a.startswith(key))) for key in ('+INPUT=','+EXPECTED=')]
            original=DUAL/'protocol/enabled'/str(variant)/'input.memh'
            assert sha(original)==rtl[variant]['inputs_sha256'] and rtl[variant]['expected_sha256']==expect
            assert sha(data)==cfg['inputs_sha256'] and sha(expected)==cfg['expected_sha256']
            if sample:
                for selected,full in ((data,original),(expected,oracle)):
                    v=full.read_text().splitlines()
                    assert selected.read_text().splitlines()==[v[i] for i in indices]
            else:
                assert sha(data)==sha(original) and sha(expected)==expect
            records=data.read_text().splitlines()
            beats=sum((int(v,16)>>1152)&15 for v in records)
            assert (r['records'],r['beats'],r['controls'])==(len(records),beats,14)
            ex=read(d/'run.execution.json')
            log=(d/'run.log').read_text()
            assert ex==r['execution'] and ex['exit_code']==0 and ex['log_sha256']==sha(d/'run.log')
            assert f'beats={beats} ' in log and f'PASS T08 attribute DMA data_records={len(records)} control_cases=14' in log
            rows.append(dict(pdk=pdk,sample=sample,variant=variant,records=len(records),beats=beats,control_cases=14,
                             log_sha256=ex['log_sha256'],netlist_sha256=build['inputs'][mapped]))
    save(OUT/'audit.json',dict(status='AUDITED_ZERO_DELAY_GATE_FUNCTION',results=rows,report_sha256=sha(OUT/'report.json'),
         script_sha256=sha(__file__),signed_off=False,scope='Post-synthesis dual-format attribute DMA and decoder only; no SDF or renderer timing.'))


if __name__=='__main__':
    main()
