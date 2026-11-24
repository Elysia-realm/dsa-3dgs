"""Functional gate simulation against the frozen attribute DMA oracles."""
import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from asic.scripts.run_t01_wsl_synthesis import q, run_stage
from scripts.map_t08_early_advance import LIBRARIES, OUT, TOP
from scripts.t08_common import BASE, WORK, read, run_logged, save, sha


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('pdk', choices=[row[0] for row in LIBRARIES])
    parser.add_argument('--sample', action='store_true', help='Run a short, stratified gate probe before the full vector deck')
    args = parser.parse_args()
    run_name = 'gate_sample' if args.sample else 'gate_functional'
    out = OUT / args.pdk / run_name
    lib = ROOT / next(spec[1] for spec in LIBRARIES if spec[0] == args.pdk)
    work = WORK / 'early_advance_20261120' / run_name / args.pdk
    work.mkdir(parents=True, exist_ok=True)
    bench = ROOT / 'verification/rtl/tb_t08_attribute_dma.sv'
    vectors = BASE / 'dma_20261107'
    oracle = read(vectors / 'report.json')
    assert sha(vectors / 'input.memh') == oracle['vectors_sha256']
    assert sha(vectors / 'expected.memh') == oracle['expected_sha256']
    inputs, expected = vectors / 'input.memh', vectors / 'expected.memh'
    count, beats = 6144, 49172
    if args.sample:
        vector_rows = inputs.read_text().splitlines()
        oracle_rows = expected.read_text().splitlines()
        # Alternate raw legacy and coded records across the five real sets.
        # The synthetic tail contributes all short/long coded lengths and raw escape.
        indices = [scene*1024 + k for scene in range(5) for k in range(16)]
        indices.extend(range(5120, 6144, 13))
        out.mkdir(parents=True, exist_ok=True)
        inputs, expected = out / 'input.memh', out / 'expected.memh'
        inputs.write_text(''.join(vector_rows[i]+'\n' for i in indices))
        expected.write_text(''.join(oracle_rows[i]+'\n' for i in indices))
        count = len(indices)
        beats = sum((int(vector_rows[i],16) >> 1152) & 15 for i in indices)
    rows = []
    for enabled in (0, 1):
        source = OUT / args.pdk / str(enabled)
        mapped = source / 'mapped.v'
        info = read(source / 'result.json')
        assert info['netlist_sha256'] == sha(mapped) and info['liberty_sha256'] == sha(lib)
        d = out / str(enabled)
        cells = work / f'with_cell_logic_{enabled}.v'
        commands = [f'read_liberty -ignore_miss_func -ignore_miss_dir -ignore_miss_data_latch {q(lib)}',
                    f'read_verilog {q(mapped)}', f'hierarchy -check -top {TOP}', 'check -assert',
                    f'write_verilog -noattr {q(cells)}']
        run_stage('cell_models', commands, d)
        exe = work / f'dma_{enabled}.vvp'
        run_logged(['/usr/bin/iverilog', '-g2012', '-s', 'tb_t08_attribute_dma', '-o', str(exe),
                    str(bench), str(cells)], d / 'build.log')
        execution = run_logged(['/usr/bin/vvp', str(exe), f'+N={count}',
                                '+INPUT=' + str(inputs), '+EXPECTED=' + str(expected)], d / 'run.log')
        log = (d / 'run.log').read_text()
        assert f'PASS T08 attribute DMA data_records={count} control_cases=9' in log and f'beats={beats} ' in log
        row = dict(pdk=args.pdk, early_advance=enabled, netlist_sha256=info['netlist_sha256'],
                   source_sha256=info['source_sha256'], liberty_sha256=sha(lib),
                   with_cell_logic_sha256=sha(cells), bench_sha256=sha(bench), execution=execution,
                   status='PASS_ZERO_DELAY_MAPPED_FUNCTION')
        save(d / 'result.json', row)
        rows.append(row)
        print(args.pdk, enabled, row['status'], flush=True)
    save(out/'report.json', dict(status='PASS_ZERO_DELAY_MAPPED_FUNCTION', results=rows, signed_off=False,
         vectors_sha256=sha(inputs), expected_sha256=sha(expected),
         scope=f'{count} data records and 9 protocol/error checks per mapped gate netlist, no delay annotation.'))


if __name__ == '__main__':
    main()
