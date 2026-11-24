"""Replay the frozen T08 workloads with only the DMA timing option toggled."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import fcntl
import os
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.run_t01_wsl_real import blocks
from scripts.run_t07_real import state_values
from scripts.t08_common import BASE, SCENES, WORK, production_sources, read, run_logged, save, sha

OUT = BASE / 'early_advance_20261120'


def matching_source():
    edit = read(BASE / 'early_advance_20261107/edit.json')
    source = production_sources()
    assert source == edit['source_after'], 'DMA candidate source drifted'
    return source, edit['source_before']


def build(kind, enabled):
    if kind in ('subset', 'continuous'):
        origin = BASE / 'integration_20261107/build/binary.json'
    else:
        origin = BASE / 'extended_20261107/build' / kind / 'binary.json'
    old = read(origin)
    source, before = matching_source()
    for name, digest in old['source_sha256'].items():
        assert (before[name] if name in before else sha(ROOT / name)) == digest, name
    top = 'tb_t08_repeat' if kind == 'repeat' else 'tb_t08_integrated'
    old_bench = ROOT / 'verification/rtl' / f'{top}.sv'
    d = OUT / 'build' / kind / str(enabled)
    work = WORK / OUT.name / kind / str(enabled)
    d.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    testbench = d / f'{top}.sv'
    text = old_bench.read_text()
    needle = "gs_accel_system_top #(.ENABLE_COMPRESSED_ATTRIBUTES(1'b1),"
    assert text.count(needle) == 1
    text = text.replace(needle, needle + f'.ATTR_DMA_EARLY_ADVANCE(1\'b{enabled}),')
    if kind == 'continuous':
        for port in ('mean', 'attr'):
            needle = f'm_axi_{port}_rvalid_i<=0;{port}_ptr<={port}_ptr+1;'
            assert text.count(needle) == 1
            text = text.replace(needle, f'''
        if(read_gap==0&&{port}_left>1)begin
          m_axi_{port}_rvalid_i<=1;m_axi_{port}_rdata_i<={port}_mem[{port}_ptr+1];m_axi_{port}_rlast_i<={port}_left==2;
          t08_consecutive_{port}<=t08_consecutive_{port}+1;
        end else m_axi_{port}_rvalid_i<=0;
        {port}_ptr<={port}_ptr+1;''')
        text = text.replace(f'module {top};', f'module {top};\n  integer t08_consecutive_mean=0,t08_consecutive_attr=0;')
        prefix = f'$display("PASS: {top}");'
        assert text.count(prefix) == 1
        text = text.replace(prefix, f'''if(t08_consecutive_mean==0||t08_consecutive_attr==0)$fatal(1,"continuous supply path absent");
    $display("REAL_T08_CONTINUOUS mean=%0d attr=%0d",t08_consecutive_mean,t08_consecutive_attr);
    {prefix}''')
    if testbench.exists():
        assert testbench.read_text() == text
    else:
        testbench.write_text(text)
    sources = {**old['source_sha256'], **source, str(testbench.relative_to(ROOT)): sha(testbench)}
    cmd = [str(testbench) if p == str(old_bench.relative_to(ROOT)) else p for p in old['command']]
    cmd[cmd.index('--Mdir') + 1] = str(work)
    marker = d / 'binary.json'
    exe = work / 'simulation'
    if marker.exists():
        info = read(marker)
        assert info['command'] == cmd and info['source_sha256'] == sources and sha(exe) == info['binary_sha256']
        return info
    run_logged([cmd[0], '--version'], d / 'tool.log')
    run_logged(cmd, d / 'build.log')
    assert all(sha(ROOT / f) == h for f, h in sources.items())
    info = dict(path=str(exe), command=cmd, source_sha256=sources, binary_sha256=sha(exe),
                parameters={**old['parameters'], 'ATTR_DMA_EARLY_ADVANCE': enabled})
    save(marker, info)
    return info


def references(kind):
    if kind in ('subset', 'continuous'):
        for scene in SCENES:
            for mode in (range(4) if kind == 'subset' else [0]):
                for axi in (('ideal', 'limited') if kind == 'subset' else ('ideal',)):
                    for fmt in (0, 1):
                        key = f'm{mode}_{axi}_f{fmt}'
                        origin = BASE / 'integration_20261107/real' / scene / key
                        yield scene, key, origin, BASE / 'integration_20261107/real' / scene / f'm{mode}_{axi}_f0'
    elif kind == 'mixed':
        for scene in SCENES:
            yield scene, 'm0_limited_f1', BASE/'mixed_20261107/real'/scene/'m0_limited_f1', None
    else:
        for scene in SCENES:
            for fmt in (0, 1):
                origin = BASE / 'extended_20261107/real' / kind / scene
                yield scene, f'f{fmt}', origin / f'f{fmt}', origin / 'f0'


def replay(kind, info, item):
    scene, key, origin, raw_origin = item
    enabled = info['parameters']['ATTR_DMA_EARLY_ADVANCE']
    destination = OUT / 'real' / kind / str(enabled) / scene / key
    reference = read(origin / 'result.json')
    old_inputs = read(origin / 'launch.json')['input_sha256']
    for name in ('run.command.json', 'frame.rgb', 'sorted.txt', 'state.memh'):
        assert sha(origin / name) == reference['evidence_sha256'][name]
    result = destination / 'result.json'
    if result.exists():
        row = read(result)
        assert row['binary_sha256'] == info['binary_sha256']
        assert row['input_sha256'] == old_inputs
        assert all(sha(destination / name) == h for name, h in row['outputs'].items())
        return row
    cmd = read(origin / 'run.command.json')
    cmd[0] = info['path']
    outputs = {'FRAME': 'state.memh', 'RGB': 'rgb.memh', 'SORTED_TRACE': 'sorted.txt'}
    inputs = {}
    for i, arg in enumerate(cmd):
        if not arg.startswith('+') or '=' not in arg:
            continue
        k, value = arg[1:].split('=', 1)
        if k in outputs:
            cmd[i] = f'+{k}={destination / outputs[k]}'
        if k in ('MEAN', 'CAMERA', 'ATTR'):
            inputs[k] = sha(Path(value))
    assert inputs == old_inputs
    launch = dict(command=cmd, input_sha256=inputs, source_sha256=info['source_sha256'],
                  binary_sha256=info['binary_sha256'], reference_sha256=sha(origin / 'result.json'))
    launch_path = destination / 'launch.json'
    if launch_path.exists():
        # An exited simulator can be rechecked if only the host audit stopped.
        # An incomplete simulator run needs separate inspection and evidence.
        assert read(launch_path) == launch
        execution = read(destination / 'run.execution.json')
        assert execution['exit_code'] == 0 and execution['log_sha256'] == sha(destination / 'run.log')
        assert read(destination / 'run.command.json') == cmd
    else:
        save(launch_path, launch)
        execution = run_logged(cmd, destination / 'run.log')
    log = (destination / 'run.log').read_text()
    top = 'tb_t08_repeat' if kind == 'repeat' else 'tb_t08_integrated'
    assert f'PASS: {top}' in log and 'error=00000000' in log
    counters = blocks(log)
    for k in ('REAL_DMA_COUNTS', 'REAL_T08'):
        if k == 'REAL_DMA_COUNTS':
            for field in ('attribute_beats', 'attribute_bursts'):
                assert counters[k][field] == reference['counters'][k][field], (scene, field)
        else:
            assert counters[k] == reference['counters'][k], (scene, k)
    assert bytes(int(x, 16) for x in (destination / 'rgb.memh').read_text().split()) == (origin / 'frame.rgb').read_bytes()
    assert (destination / 'sorted.txt').read_text() == (origin / 'sorted.txt').read_text()
    epoch = 2 if kind == 'repeat' else 1
    new = state_values(destination / 'state.memh', epoch)
    old = state_values(origin / 'state.memh', epoch)
    assert len(new) == len(old) and all(a == b and (t == u or max(t, u) <= 7) for (a, t), (b, u) in zip(new, old))
    cycles = counters['REAL_END_TO_END']['command_cycles']
    if enabled == 0 and kind != 'continuous':
        assert cycles == reference['command_cycles'], (scene, key, cycles, reference['command_cycles'])
    raw = read(raw_origin / 'result.json')['command_cycles'] if raw_origin else None
    row = dict(status='PASS_SCOPED', scene=scene, case=key, early_advance=enabled,
               format=reference['format'], command_cycles=cycles, previous_cycles=reference['command_cycles'],
               uncompressed_cycles=raw, counters=counters, execution=execution, input_sha256=inputs,
               binary_sha256=info['binary_sha256'], parameters=info['parameters'],
               outputs={f: sha(destination / f) for f in (*outputs.values(), 'run.log', 'launch.json')}, signed_off=False)
    save(result, row)
    print(kind, scene, key, 'early', enabled, cycles, 'delta', cycles - reference['command_cycles'], flush=True)
    return row


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('kind', choices=('subset', 'repeat', 'mixed', 'full', 'continuous'))
    parser.add_argument('--jobs', type=int, default=4, choices=range(1, 7))
    parser.add_argument('--enable', type=int, nargs='+', choices=(0, 1), default=[0, 1])
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--after-current', action='store_true', help='Wait for the live batch before checking or resuming it')
    args = parser.parse_args()
    assert os.name == 'posix'
    kind = args.kind
    if args.after_current:
        wait_for_current(kind)
    if kind == 'full' and not args.build_only:
        for gate in ('subset', 'repeat', 'mixed'):
            assert read(OUT / f'{gate}_report.json')['status'] == 'PASS_SCOPED'
    builds = {}
    with ThreadPoolExecutor(max_workers=2) as pool:
        for enabled, info in zip(args.enable, pool.map(lambda e: build('subset' if kind == 'mixed' else kind, e), args.enable)):
            builds[enabled] = info
    if args.build_only:
        return
    OUT.mkdir(parents=True, exist_ok=True)
    with (WORK / OUT.name / f'{kind}.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        execute_cases(kind, args.jobs, builds)


def execute_cases(kind, jobs, builds):
    work = [(info, item) for item in references(kind) for info in builds.values()]
    status = OUT / f'{kind}_status.json'
    if pid := active_batch(kind):
        raise RuntimeError(f'{kind} is already running as PID {pid}')
    save(status, dict(status='RUNNING', pid=os.getpid(), cases=len(work), signed_off=False))
    rows, failures = [], []
    try:
        with ThreadPoolExecutor(max_workers=jobs) as pool:
            pending = {pool.submit(replay, kind, info, item): (info, item) for info, item in work}
            for job in as_completed(pending):
                info, (scene, key, _, _) = pending[job]
                try:
                    rows.append(job.result())
                except Exception as error:
                    failures.append(dict(scene=scene, case=key, early_advance=info['parameters']['ATTR_DMA_EARLY_ADVANCE'],
                                         error=str(error)))
                save(status, dict(status='RUNNING', pid=os.getpid(), cases=len(work), passed=len(rows),
                                  failures=failures, signed_off=False))
        matching_source()
        if failures:
            raise RuntimeError(f'{len(failures)} cases need inspection: {failures}')
        rows.sort(key=lambda r: (r['scene'], r['case'], r['early_advance']))
        save(OUT / f'{kind}_report.json', dict(status='PASS_SCOPED', cases=len(rows), results=rows, signed_off=False))
        save(status, dict(status='PASS_SCOPED', cases=len(rows), signed_off=False))
    except BaseException:
        save(status, dict(status='FAILED_OR_INTERRUPTED', passed=len(rows), cases=len(work),
                          failures=failures, signed_off=False))
        raise


def active_batch(kind):
    status = OUT / f'{kind}_status.json'
    if not status.exists():
        return None
    current = read(status)
    if current['status'] != 'RUNNING':
        return None
    pid = current['pid']
    try:
        args = (Path('/proc') / str(pid) / 'cmdline').read_bytes().split(b'\0')
    except FileNotFoundError:
        return None
    if any(arg.endswith(b'run_t08_early_advance.py') for arg in args) and kind.encode() in args:
        return pid
    return None


def wait_for_current(kind):
    pid = active_batch(kind)
    if pid is None:
        return
    print(f'Waiting for {kind} PID {pid}; verified completed artifacts will be reused', flush=True)
    while active_batch(kind) == pid:
        time.sleep(10)


if __name__ == '__main__':
    main()
