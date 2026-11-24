"""Audit the user's final authorized T08 batches and record the contract decision."""
from itertools import product
from pathlib import Path
import re
import sys
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,read,save,sha
from scripts.run_t08_eight_beat_header import OUT as EIGHT
from scripts.run_t08_eight_native_shared import OUT as NATIVE,terminal_check
from scripts.run_t08_terminated_blocks import OUT as IDEAL
from scripts.run_t08_qsu_native_full import OUT as REFERENCES
from scripts.run_t08_dual_precision import OUT as DUAL
from scripts.read_rgb888_frame import decode_rgb888

OUT=BASE/'current_batch_handoff_20261123'


def verify_execution(folder,record):
    assert record['exit_code']==0
    assert record==read(folder/'run.execution.json')
    assert record['log_sha256']==sha(folder/'run.log')


def audit_gates():
    root=EIGHT/'gates'
    assert read(root/'status.json')['status']=='MAPPED_FUNCTION_CHECKED'
    report=read(root/'report.json')
    assert report['script_sha256']==sha(ROOT/'scripts/check_t08_eight_beat_gates.py')
    rows={(r['pdk'],r['sample'],r['variant']):r for r in report['results']}
    assert len(report['results'])==len(rows)==8
    expected=BASE/'dma_20261107/expected.memh'
    oracle=expected.read_text().splitlines()
    checks=[]
    for pdk in ('nangate45','icsprout55'):
        binary=report['builds'][pdk]
        assert binary==read(root/pdk/'binary.json')
        assert all(sha(p)==h for p,h in binary['inputs'].items())
        assert sha(binary['exe'])==binary['vvp_sha256']
        assert sha(Path(binary['exe']).with_name('cells.v'))==binary['cells_sha256']
        for sample,variant in product((False,True),(0,1)):
            r=rows[pdk,sample,variant]
            d=root/pdk/('sample' if sample else 'full')/str(variant)
            assert r==read(d/'result.json')
            verify_execution(d,r['execution'])
            cfg=read(d/'launch.json')
            assert cfg==r['config'] and cfg['command']==read(d/'run.command.json')
            assert cfg['vvp_sha256']==binary['vvp_sha256']
            cmd=cfg['command']
            paths=[Path(next(x.split('=',1)[1] for x in cmd if x.startswith(k))) for k in ('+INPUT=','+EXPECTED=')]
            assert sha(paths[0])==cfg['input_sha256'] and sha(paths[1])==cfg['expected_sha256']
            deck=(DUAL/'protocol/enabled'/str(variant)/'input.memh').read_text().splitlines()
            indices=[s*1024+i for s in range(5) for i in range(16)]+list(range(5120,6144,13)) if sample else list(range(6144))
            assert paths[0].read_text().splitlines()==[deck[i] for i in indices]
            assert paths[1].read_text().splitlines()==[oracle[i] for i in indices]
            physical=0
            for i,j in enumerate(indices):
                packet=int(deck[j],16)
                useful=(packet>>1152)&15
                room=1+(i//4)%8 if (i//32)%2==0 else 8
                physical+=max(room,useful) if packet>>1156==2 else useful
            assert (r['records'],r['physical_beats'],r['controls'])==(len(indices),physical,18)
            assert f"PASS T08 attribute DMA data_records={len(indices)} control_cases=18" in (d/'run.log').read_text()
            checks.append(dict(pdk=pdk,sample=sample,variant=variant,records=len(indices),physical_beats=physical,
                               control_cases=18,log_sha256=r['execution']['log_sha256']))
    return dict(results=checks,report_sha256=sha(root/'report.json'))


def audit_native():
    assert read(NATIVE/'status.json')['status']=='NATIVE_SHARED_PAIRS_COMPARED'
    report=read(NATIVE/'report.json')
    assert report['script_sha256']==sha(ROOT/'scripts/run_t08_eight_native_shared.py')
    binary=read(NATIVE/'build/binary.json')
    assert sha(binary['exe'])==binary['elf_sha256'] and all(sha(ROOT/p)==h for p,h in binary['sources'].items())
    rows={(r['scene'],r['fmt']):r for r in report['results']}
    assert set(rows)==set(product(('train','truck'),(3,2))) and len(report['results'])==4
    results=[]
    for scene in ('train','truck'):
        refdir=IDEAL/'native'/scene
        ref=read(refdir/'result.json')
        assert all(sha(refdir/f)==h for f,h in ref['hashes'].items())
        grid=read(REFERENCES/'reference'/scene/'samples.json')
        assert all(sha(p)==h for group in ('inputs','sources') for p,h in grid[group].items())
        pair=[]
        for fmt in (3,2):
            r=rows[scene,fmt]
            d=NATIVE/'native'/scene/f'f{fmt}'
            assert r==read(d/'result.json')
            verify_execution(d,r['execution'])
            assert all(sha(d/f)==h for f,h in r['hashes'].items())
            launch=read(d/'launch.json')
            assert launch['command']==read(d/'run.command.json') and launch['elf_sha256']==binary['elf_sha256']
            for arg in launch['command']:
                key,_,path=arg.partition('=')
                if key[1:] in ('MEAN','ATTR','CAMERA'):
                    assert sha(path)==launch['inputs'][key[1:]]
            assert r['full_model'] and r['camera']==grid['camera'] and (r['width'],r['height'])==(grid['width'],grid['height'])
            for f in ('rgb.memh','frame.png','sorted.txt'):assert r['hashes'][f]==ref['hashes'][f]
            assert terminal_check(d/'state.memh',refdir/'state.memh')==r['terminal_word_differences']
            rgb=decode_rgb888(bytes.fromhex((d/'rgb.memh').read_text()),r['width'],r['height'])
            assert Image.open(d/'frame.png').tobytes()==rgb.tobytes()
            delta=np.array([rgb[p['y'],p['x']].astype(int)-p['rgb'] for p in grid['samples']])
            assert delta.shape==(81,3)
            assert r['sample_comparison']==dict(mae_rgb8=float(abs(delta).mean()),max_channel_error=int(abs(delta).max()))
            c=r['counters'];stats=(d/'model.stats').read_text()
            assert 'PASS: tb_t08_native_eight_shared' in (d/'run.log').read_text()
            assert c['REAL_QSU']['enabled']==1 and c['REAL_ADDRESS_LAYOUT']['disjoint']==1
            assert c['REAL_T08']['format']==fmt
            assert c['REAL_SHARED_BUS']['final_queue']==0
            assert c['REAL_END_TO_END']['command_cycles']==r['cycles']
            assert int(re.search(r'ramulator\.incoming_requests\s+(\d+)',stats)[1])==c['REAL_LPDDR']['lines']
            assert c['REAL_LPDDR']['qsu_b']==c['REAL_DMA_COUNTS']['qsu_write_bursts']
            assert c['REAL_LPDDR']['out_b']==c['REAL_DMA_COUNTS']['output_write_bursts']
            assert c['REAL_RGB']['error']==0 and c['REAL_RGB']['reads']==r['width']*r['height']
            pair.append(dict(format=fmt,command_cycles=r['cycles'],assumed_200mhz_fps=200e6/r['cycles'],
                    attr_bytes=c['REAL_DMA_COUNTS']['attribute_beats']*16,attr_ar=c['REAL_DMA_COUNTS']['attribute_bursts'],
                    logical_requests=c['REAL_T08']['requests'],dram_lines=c['REAL_LPDDR']['lines'],
                    tail_dram_cycles=c['REAL_LPDDR']['dram_tail_cycles'],
                    total_axi_bytes=c['REAL_SHARED_BUS']['beats']*16,shared_R=c['REAL_SHARED_PE']['R'],
                    state_reads=c['REAL_PERF']['state_reads'],state_writes=c['REAL_PERF']['state_writes'],
                    sample=r['sample_comparison'],host_wall_s=r['execution']['wall_seconds'],
                    terminal_word_differences=r['terminal_word_differences'],result_sha256=sha(d/'result.json')))
        raw,compact=pair
        assert raw['logical_requests']==compact['logical_requests'] and compact['attr_bytes']<raw['attr_bytes']
        results.append(dict(scene=scene,camera=grid['camera'],records=grid['gaussians'],width=grid['width'],height=grid['height'],
                    cases=pair,cycle_savings_percent=100*(1-compact['command_cycles']/raw['command_cycles']),
                    attribute_savings_percent=100*(1-compact['attr_bytes']/raw['attr_bytes'])))
    return dict(results=results,report_sha256=sha(NATIVE/'report.json'))


if __name__=='__main__':
    gates=audit_gates()
    native=audit_native()
    # An observed failure at the required reference frequency already blocks D04.
    fps_failure=any(v['assumed_200mhz_fps']<30 for r in native['results'] for v in r['cases'])
    status=read(ROOT/'verification/implementation_status.json')
    save(OUT/'audit.json',dict(gates=gates,native=native,script_sha256=sha(__file__),
         current_batches_audited=True,signed_off=False,
         decision='T08 remains unsigned. Current batch results are complete; future development is exclusively user-directed.',
         contract=dict(D04_observed_fps_failure_at_assumed_200mhz=fps_failure,
                       D06_formal_GT_signed_off=status['ground_truth_quality_signed_off'],
                       D08_attribute_byte_reduction=True,ppa_signed_off=status['ppa_signed_off']),
         automation=dict(id='t08',delete_after_assessment=True,deletion_verified=False)))
    print('Current batches audited; T08 remains unsigned; delete t08 automation and finish handoff.')
