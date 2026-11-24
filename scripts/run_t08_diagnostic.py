"""Native-resolution baseline diagnosis; never a compression/GT signoff."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import shutil
import sys
import traceback

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from PIL import Image
from scripts.t08_common import BASE, WORK, T07, PROFILE, SCENES, MAX_COUNT, MAX_PIXELS, read, save, sha, run_logged, production_sources
from scripts.run_t01_wsl_real import blocks
from scripts.read_rgb888_frame import decode_rgb888

BENCH = 'verification/rtl/tb_t08_diagnostic.sv'


def sources():
    result = production_sources()
    result[BENCH] = sha(ROOT / BENCH)
    for p in ['verification/rtl/t06_perf_measurements.svh', 'verification/rtl/t06_memory_layout.svh',
              'verification/rtl/t06_memory_scratch.svh', 'verification/rtl/t06_scratch_signals.svh']:
        result[p] = sha(ROOT / p)
    return result


def build():
    old = read(T07 / 'build/full/C/binary.json')
    assert old['parameters'] == read(PROFILE)['parameters']
    cmd = [x.replace('tb_t07_workload', 'tb_t08_diagnostic') for x in old['command']]
    w, dest = WORK / 'build/native', BASE / 'build/native'
    w.mkdir(parents=True, exist_ok=True)
    cmd[cmd.index('--Mdir')+1] = str(w)
    cmd = [f'-DTB_MAX_COUNT={MAX_COUNT}' if x.startswith('-DTB_MAX_COUNT=') else
           f'-DTB_MAX_PIXELS={MAX_PIXELS}' if x.startswith('-DTB_MAX_PIXELS=') else x for x in cmd]
    m = sources()
    marker, binary = dest / 'binary.json', w / 'simulation'
    if marker.exists():
        info = read(marker)
        assert info['source_sha256'] == m and info['command'] == cmd and sha(binary) == info['binary_sha256']
        return info
    snap = dest / 'source_snapshot'
    for f, h in m.items():
        out = snap / f
        out.parent.mkdir(parents=True, exist_ok=True)
        if out.exists():
            assert sha(out) == h
        else:
            shutil.copy2(ROOT / f, out)
    save(snap / 'manifest.json', m)
    run_logged([cmd[0], '--version'], dest / 'version.log')
    run_logged(cmd, dest / 'build.log')
    assert binary.read_bytes()[:4] == b'\x7fELF' and sources() == m
    info = dict(path=str(binary), command=cmd, source_sha256=m, binary_sha256=sha(binary),
                parameters=old['parameters'], verilator_sha256=sha(Path(cmd[0])),
                harness_max_count=MAX_COUNT, harness_max_pixels=MAX_PIXELS)
    save(marker, info)
    return info


def validate_outputs(dest, width, height):
    raw = bytes(int(s, 16) for s in (dest / 'rgb.memh').read_text().split())
    stride = (width * 3 + 15) & ~15
    assert len(raw) == stride * height
    expected = bytearray(len(raw))
    count = 0
    with (dest / 'state.memh').open() as state:
        for line in state:
            value = int(line, 16)
            assert count < width * height
            if ((value >> 55) & 65535) == 1:
                y, x = divmod(count, width)
                for channel in range(3):
                    expected[y*stride+x*3+channel] = min(255, (((value >> (13*channel)) & 8191)*255+2048)//4096)
            count += 1
    assert count == width * height and raw == expected, 'DMA differs from architecturally visible RGB state'
    (dest / 'frame.rgb').write_bytes(raw)
    pixels = decode_rgb888(raw, width, height)
    Image.fromarray(pixels).save(dest / 'frame.png')
    assert Image.open(dest / 'frame.png').tobytes() == pixels.tobytes()
    return raw


def run_case(kind, name, info):
    dest = BASE / 'diagnostic' / kind / name
    dest.mkdir(parents=True, exist_ok=True)
    old = T07 / 'real' / ('subset/C' if kind == 'smoke' else 'full/C') / name
    if kind == 'smoke':
        old /= 'm0_ideal'
    reference = read(old / 'result.json')
    cmd = read(old / 'run.command.json')
    cmd[0] = info['path']
    native = read(BASE / 'inputs/native' / name / 'manifest.json')
    w, h = (reference['width'], reference['height']) if kind == 'smoke' else (native['width'], native['height'])
    for i, x in enumerate(cmd):
        if not x.startswith('+'):
            continue
        key = x[1:].split('=', 1)[0]
        if key in {'FRAME', 'RGB', 'SORTED_TRACE'}:
            cmd[i] = '+' + key + '=' + str(dest / {'FRAME':'state.memh', 'RGB':'rgb.memh', 'SORTED_TRACE':'sorted.txt'}[key])
        elif key in {'CAMERA', 'MEAN', 'ATTR'} and kind == 'native':
            cmd[i] = '+' + key + '=' + native['inputs'][key]
    inputs = {x[1:].split('=',1)[0]:Path(x.split('=',1)[1]) for x in cmd if x.startswith(('+CAMERA=', '+MEAN=', '+ATTR='))}
    hashes = {k:sha(p) for k,p in inputs.items()}
    expected = native['input_sha256'] if kind == 'native' else reference['input_sha256']
    assert hashes == expected and sources() == info['source_sha256']
    marker = dest / 'result.json'
    if marker.exists():
        prior = read(marker)
        assert prior['binary_sha256'] == info['binary_sha256'] and prior['input_sha256'] == hashes
        assert all(sha(dest/f) == digest for f,digest in prior['evidence_sha256'].items())
        return prior
    if (dest / 'launch.json').exists():
        raise RuntimeError(f'Existing unfinished/failed run at {dest}; inspect and archive attempt before retry')
    save(dest / 'launch.json', dict(command=cmd, source_sha256=info['source_sha256'], input_sha256=hashes,
         binary_sha256=info['binary_sha256'], parameters=info['parameters'], driver_sha256=sha(Path(__file__)),
         scene=name, width=w, height=h, full_scene=kind=='native', kind=kind, signed_off=False))
    save(dest / 'status.json', dict(status='RUNNING', pid=os.getpid(), signed_off=False))
    try:
        execution = run_logged(cmd, dest / 'run.log')
        log = (dest / 'run.log').read_text()
        assert 'PASS: tb_t08_diagnostic' in log and 'error=00000000' in log and 'disjoint=1' in log
        counters = blocks(log)
        assert counters['REAL_T07_TERMINATION']['enabled'] == 1
        assert counters['REAL_QSU']['enabled'] == 1
        assert (dest/'sorted.txt').read_bytes().replace(b'\r\n',b'\n') == (old/'sorted.txt').read_bytes().replace(b'\r\n',b'\n')
        # These counters depend on unchanged depth input/order, not image size.
        for key in ['mean_beats', 'attribute_beats', 'qsu_read_beats', 'qsu_write_beats']:
            assert counters['REAL_DMA_COUNTS'][key] == reference['counters']['REAL_DMA_COUNTS'][key], key
        raw = validate_outputs(dest, w, h)
        cycles = counters['REAL_END_TO_END']['command_cycles']
        if kind == 'smoke':
            assert raw == (old/'frame.rgb').read_bytes()
            assert (dest/'state.memh').read_bytes().replace(b'\r\n',b'\n') == (old/'state.memh').read_bytes().replace(b'\r\n',b'\n')
            assert cycles == reference['command_cycles']
        assert sources() == info['source_sha256'] and all(sha(p)==hashes[k] for k,p in inputs.items())
        row = dict(status='PASS_HARNESS_EQUIVALENCE' if kind=='smoke' else 'PROTOCOL_PASS_REFERENCE_PENDING',
                   scene=name, kind=kind, full_scene=kind=='native', gaussians=reference['gaussians'], camera_index=SCENES[name],
                   width=w, height=h, command_cycles=cycles, counters=counters, execution=execution,
                   source_sha256=info['source_sha256'], input_sha256=hashes, binary_sha256=info['binary_sha256'],
                   parameters=info['parameters'], independent_native_reference_pass=None if kind=='native' else 'T07 identical input/output',
                   GT_quality_pass=None, frequency_verified=False, assumed_200MHz_FPS=200000000/cycles, signed_off=False)
        row['evidence_sha256'] = {p.name:sha(p) for p in dest.iterdir() if p.is_file() and p.name not in {'result.json','status.json'}}
        save(marker, row)
        save(dest/'status.json', dict(status=row['status'], signed_off=False))
        print(row['status'], name, f'{w}x{h}', cycles, flush=True)
        return row
    except BaseException:
        save(dest/'status.json', dict(status='FAILED', error=traceback.format_exc(), signed_off=False))
        raise


def main():
    p = argparse.ArgumentParser()
    p.add_argument('kind', choices=['build','smoke','native'])
    p.add_argument('--scenes', nargs='+', choices=list(SCENES))
    p.add_argument('--jobs', type=int, default=2)
    a = p.parse_args()
    assert 1 <= a.jobs <= 2
    info = build()
    if a.kind == 'build':
        print('BUILT', info['path'])
        return
    names = a.scenes or list(SCENES)
    if a.kind == 'native':
        for name in SCENES:
            smoke = read(BASE/'diagnostic/smoke'/name/'result.json')
            assert smoke['status']=='PASS_HARNESS_EQUIVALENCE' and smoke['binary_sha256']==info['binary_sha256']
    tag = a.kind + ('_'+'_'.join(names) if a.scenes else '')
    save(BASE/(tag+'_status.json'),dict(status='RUNNING',pid=os.getpid(),scenes=names,signed_off=False))
    try:
        with ThreadPoolExecutor(max_workers=a.jobs) as pool:
            rows = list(pool.map(lambda n: run_case(a.kind,n,info), names))
        save(BASE/(tag+'_report.json'),dict(status='COMPLETE_DIAGNOSTIC_ONLY',results=rows,signed_off=False))
        save(BASE/(tag+'_status.json'),dict(status='COMPLETE_DIAGNOSTIC_ONLY',scenes=names,signed_off=False))
    except BaseException:
        save(BASE/(tag+'_status.json'),dict(status='FAILED',error=traceback.format_exc(),scenes=names,signed_off=False))
        raise


if __name__ == '__main__':
    main()
