"""Isolated Q24 command pair. The production Q20 binary remains version 1."""
from concurrent.futures import ThreadPoolExecutor
import fcntl
import os
from pathlib import Path
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from model.io.t08_attribute_codec import encode_record, unpack_legacy, RAW_HEADER
from scripts.run_t08_precision_rgb import OUT as PRECISION, PREVIOUS, freeze
from scripts.scan_t08_small_covariances import make_products, shift
from scripts.t08_common import BASE, WORK, SCENES, read, save, sha, run_logged
from scripts.run_t01_wsl_real import blocks
from scripts.read_rgb888_frame import decode_rgb888

OUT = BASE / 'v2_compact_native_20261122'
BUILD = OUT / 'build'
LOCAL = WORK / OUT.name
MASK128 = (1 << 128) - 1


def encode_q24(record):
    old = encode_record(record)
    if old['precomputed']:
        # The v1 precheck already excluded overflow in either common intermediate.
        _, quaternion, scale = unpack_legacy(record)
        prod = make_products(np.array([quaternion]), np.array([scale]))[0]
        cov = shift(prod[np.triu_indices(3)], 16)
        if np.all((cov >= -(1 << 23)) & (cov < (1 << 23))):
            payload = old['record'] & ~(((1 << 144) - 1) << 110)
            for i, value in enumerate(cov):
                payload |= (int(value) & 0xffffff) << (110 + 24*i)
            return (payload & ~(3 << 8)) | (2 << 8), old['beats']
    return (record << 16) | ((RAW_HEADER & ~(3 << 8)) | (2 << 8)), 9


def edit(text, old, new, count=1):
    assert text.count(old) == count, (old, text.count(old))
    return text.replace(old, new)


def build():
    prior = read(PRECISION / 'build/binary.json')
    sources = prior['sources'].copy()
    assert all(sha(ROOT / path) == digest for path, digest in sources.items())
    BUILD.mkdir(parents=True, exist_ok=True)
    LOCAL.mkdir(parents=True, exist_ok=True)
    files = (PRECISION / 'build/sources.f').read_text().splitlines()
    edits = {
        'rtl/dma/t08_attribute_decoder.sv': [("16'h3dc8", "16'h3ec8", 1),
            ("s_packet_i[9:8]!=2'd1", "s_packet_i[9:8]!=2'd2", 1)],
        'rtl/dma/axi4_t08_attribute_read_engine.sv': [
            ("16'h3dc8", "16'h3ec8", 1), ('m_axi_rdata_i[9:8]!=1', 'm_axi_rdata_i[9:8]!=2', 1),
            ('format_i==1', 'format_i==2', 3), ('format_i>1', 'format_i<2', 1)],
        'rtl/gs_accel_system_top.sv': [('attribute_format==0||(ENABLE_COMPRESSED_ATTRIBUTES&&USE_AXI_ATTR_DMA&&attribute_format==1)',
            'ENABLE_COMPRESSED_ATTRIBUTES&&USE_AXI_ATTR_DMA&&(attribute_format==2||attribute_format==3)', 1)]}
    for name, changes in edits.items():
        text = (ROOT / name).read_text()
        for old, new, count in changes:
            text = edit(text, old, new, count)
        output = BUILD / Path(name).name
        freeze(output, text)
        sources[str(output.relative_to(ROOT))] = sha(output)
        assert files.count(name) == 1
        files[files.index(name)] = str(output)
    filelist = BUILD / 'sources.f'
    freeze(filelist, '\n'.join(files) + '\n')
    old_bench = PREVIOUS / 'build/1/tb_t08_bbox_pair.sv'
    bench = BUILD / 'tb_t08_q24_compact.sv'
    text = old_bench.read_text().replace(old_bench.stem, bench.stem)
    text = edit(text, 't08_format==0?9', 't08_format==3?9')
    text = edit(text, '(t08_format==1&&observed==0)', '((t08_format==2)!=(observed!=0))')
    freeze(bench, edit(text, "apb_write(12'h0f0,2);", "apb_write(12'h0f0,t08_format^1);"))
    for path in (filelist, bench):
        sources[str(path.relative_to(ROOT))] = sha(path)
    cmd = prior['command'].copy()
    cmd[cmd.index('-f') + 1] = str(filelist)
    cmd[cmd.index(str(PRECISION / 'build/tb_t08_precision_rgb.sv'))] = str(bench)
    cmd[cmd.index('--top-module') + 1] = bench.stem
    cmd[cmd.index('--Mdir') + 1] = str(LOCAL)
    marker = BUILD / 'binary.json'
    exe = LOCAL / 'simulation'
    if marker.exists():
        info = read(marker)
        assert info['sources'] == sources and info['command'] == cmd and sha(exe) == info['elf_sha256']
    else:
        run_logged(cmd, BUILD / 'build.log')
        info = dict(sources=sources, command=cmd, elf_sha256=sha(exe), exe=str(exe))
        save(marker, info)
    return info


def run_scene(scene, info):
    raw = PRECISION / 'inputs' / scene / 'raw.memh'
    old_dir = PRECISION / 'real' / scene
    prior = read(old_dir / 'result.json')
    ref = prior['rows'][0]
    meta = prior['inputs']
    assert sha(raw) == read(old_dir / 'f0/launch.json')['input_sha256']['ATTR']
    words = [int(x, 16) for x in raw.read_text().split()]
    assert len(words) == len(meta['gids'])*9
    directory = OUT / 'real' / scene
    directory.mkdir(parents=True, exist_ok=True)
    packed = directory / 'compact.memh'
    lines = []
    for start in range(0, len(words), 9):
        record = sum(w << (128*i) for i, w in enumerate(words[start:start+9]))
        packet, _ = encode_q24(record)
        lines.extend(f'{(packet >> (128*i)) & MASK128:032x}\n' for i in range(9))
    freeze(packed, ''.join(lines))
    rows = []
    for fmt, attrs in [(3, raw), (2, packed)]:
        d = directory / f'f{fmt}'
        d.mkdir(exist_ok=True)
        paths = dict(ATTR=attrs, FRAME=d/'state.memh', RGB=d/'rgb.memh', SORTED_TRACE=d/'sorted.txt')
        cmd = read(old_dir / 'f0/run.command.json')
        cmd[0] = info['exe']
        cmd[cmd.index('+ATTR_FORMAT=0')] = f'+ATTR_FORMAT={fmt}'
        cmd = ['+' + k + '=' + str(paths[k]) if (k := a.partition('=')[0][1:]) in paths else a for a in cmd]
        inputs = {k:sha(a.partition('=')[2]) for a in cmd if (k := a.partition('=')[0][1:]) in ('ATTR','MEAN','CAMERA')}
        for key in ('MEAN','CAMERA'):
            assert inputs[key] == meta['input_sha256'][key.lower()+'.memh']
        launch = dict(command=cmd, inputs=inputs, elf_sha256=info['elf_sha256'])
        marker = d / 'launch.json'
        if marker.exists():
            assert read(marker) == launch
        else:
            save(marker, launch)
        log = d / 'run.log'
        execution = log.with_suffix('.execution.json')
        if execution.exists() and read(execution)['exit_code'] == 0:
            assert sha(log) == read(execution)['log_sha256']
        else:
            run_logged(cmd, log)
        text = log.read_text()
        assert 'PASS: tb_t08_q24_compact' in text and 'error=00000000' in text
        counters = blocks(text)
        traffic = counters['REAL_T08']
        dma = counters['REAL_DMA_COUNTS']
        assert traffic['format'] == fmt and traffic['requests'] == ref['counters']['REAL_T08']['requests']
        assert traffic['precomputed'] == traffic['world_precomputed']
        assert (traffic['precomputed'] > 0) == (fmt == 2)
        assert traffic['expected_beats'] == dma['attribute_beats']
        rgb = bytes.fromhex((d/'rgb.memh').read_text())
        pixels = decode_rgb888(rgb, meta['width'], meta['height'])
        Image.fromarray(pixels).save(d/'frame.png')
        assert Image.open(d/'frame.png').tobytes() == pixels.tobytes()
        hashes = {name:sha(d/name) for name in ('state.memh','rgb.memh','frame.png','sorted.txt')}
        for name, key in [('state.memh','state_sha256'), ('rgb.memh','rgb_sha256'), ('frame.png','image_sha256')]:
            assert hashes[name] == ref[key], (scene, fmt, name)
        assert hashes['sorted.txt'] == sha(old_dir/'f0/sorted.txt')
        rows.append(dict(format=fmt, counters=counters, execution=read(execution), hashes=hashes,
                         attribute_bytes=16*dma['attribute_beats'], attribute_bursts=dma['attribute_bursts'],
                         cycles=counters['REAL_END_TO_END']['command_cycles']))
    assert rows[1]['attribute_bytes'] < rows[0]['attribute_bytes']
    result = dict(scene=scene, inputs=meta, reference_sha256=sha(old_dir/'result.json'), rows=rows)
    save(directory/'result.json', result)
    return result


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        save(OUT/'status.json', dict(status='BUILDING', pid=os.getpid(), signed_off=False))
        try:
            info = build()
            save(OUT/'status.json', dict(status='RUNNING_NATIVE_SUBSETS', pid=os.getpid(), signed_off=False))
            with ThreadPoolExecutor(max_workers=3) as pool:
                rows = list(pool.map(lambda scene: run_scene(scene, info), SCENES))
            assert all(sha(ROOT/path) == digest for path, digest in info['sources'].items())
            save(OUT/'report.json', dict(results=rows, signed_off=False, full_scene=False,
                 script_sha256=sha(__file__), scope='Isolated Q24 modes 2 and 3. Q20 release is a separate binary.'))
            save(OUT/'status.json', dict(status='NATIVE_SUBSETS_COMPARED', signed_off=False))
        except BaseException:
            save(OUT/'status.json', dict(status='FAILED_OR_INTERRUPTED', signed_off=False))
            raise


if __name__ == '__main__':
    main()
