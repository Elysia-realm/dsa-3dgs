"""Build one opt-in Q20/Q24 top from the frozen serial-cull sources and replay all four commands."""
from concurrent.futures import ThreadPoolExecutor
import fcntl
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.run_t08_precision_rgb import PREVIOUS, OUT as PRECISION, freeze
from scripts.run_t08_q24_compact import OUT as COMPACT, edit
from scripts.run_t01_wsl_real import blocks
from scripts.t08_common import BASE, WORK, SCENES, read, save, sha, run_logged
from scripts.read_rgb888_frame import decode_rgb888
from PIL import Image

OUT = BASE/'dual_precision_native_20261122'
BUILD = OUT/'build'
LOCAL = WORK/OUT.name


def attach_child(text, child, signal):
    start = re.search(r'\b' + child + r'\s*#\(', text)
    assert start, child
    instance = re.search(r'\)\s*(\w+)\s*\(\s*\.\w+', text[start.end():])
    assert instance, child
    pos = text.index('.', start.end() + instance.start(1))
    return text[:pos] + '.cfg_cov_q24_i(' + signal + '),' + text[pos:]


def rounding(text, name, width, shift, increment):
    # Both shifts remain elaboration constants. The mux selects one rounded value.
    pattern = r'function automatic logic signed \[' + width + r'-1:0\] ' + name + r'\(.*?endfunction'
    match = re.search(pattern, text, re.S)
    assert match, name
    old = match.group()
    q20 = old.replace(name, name+'_q20')
    q24 = old.replace(name, name+'_q24').replace(shift, '('+shift+increment+')')
    select = old.split(');', 1)[0] + ');\n        ' + name + ' = cfg_cov_q24_i ? ' + name + '_q24(value) : ' + name + '_q20(value);\n    endfunction'
    return edit(text, old, q20 + '\n    ' + q24 + '\n    ' + select)


def build():
    previous = PREVIOUS/'build/1'
    prior = read(previous/'binary.json')
    sources = prior['sources'].copy()
    assert all(sha(ROOT/p) == digest for p, digest in sources.items())
    BUILD.mkdir(parents=True, exist_ok=True)
    LOCAL.mkdir(parents=True, exist_ok=True)
    files = (previous/'sources.f').read_text().splitlines()
    children = {
        'gs_accel_system_top':['gaussian_frame_render_pipeline'],
        'gaussian_frame_render_pipeline':['gaussian_sorted_render_pipeline'],
        'gaussian_sorted_render_pipeline':['gaussian_ordered_render_frontend'],
        'gaussian_ordered_render_frontend':['gaussian_projection_sh_array'],
        'gaussian_projection_sh_array':['raw_gaussian_projection_array'],
        'raw_gaussian_projection_array':['raw_gaussian_projection_lane'],
        'raw_gaussian_projection_lane':['camera_projection_tile_lane','quaternion_scale_covariance_core'],
        'camera_projection_tile_lane':['screen_covariance_core'],
        'quaternion_scale_covariance_core':[], 'screen_covariance_core':[]}
    modules = set(children) | {'axi4_t08_attribute_read_engine','t08_attribute_decoder'}
    changed = set()
    for i, path in enumerate(files):
        name = Path(path).stem
        if name not in modules:
            continue
        changed.add(name)
        text = (ROOT/path).read_text()
        if name in children:
            if name != 'gs_accel_system_top':
                text, count = re.subn(r'\binput\s+logic\s+clk_i\b', r'input logic cfg_cov_q24_i,\n    \g<0>', text)
                assert count == 1, name
            signal = 'ENABLE_Q24_ATTRIBUTES && cmd_attribute_format_q[1]' if name == 'gs_accel_system_top' else 'cfg_cov_q24_i'
            for child in children[name]:
                text = attach_child(text, child, signal)
        if name == 'gs_accel_system_top':
            text = edit(text, 'parameter bit ENABLE_COMPRESSED_ATTRIBUTES', "parameter bit ENABLE_Q24_ATTRIBUTES=1'b0,\n    parameter bit ENABLE_COMPRESSED_ATTRIBUTES")
            text = edit(text, 'USE_AXI_ATTR_DMA&&attribute_format==1', 'USE_AXI_ATTR_DMA&&(attribute_format==1||ENABLE_Q24_ATTRIBUTES)')
            text = edit(text, 'axi4_t08_attribute_read_engine #(', 'axi4_t08_attribute_read_engine #(.ENABLE_Q24(ENABLE_Q24_ATTRIBUTES),')
        elif name == 'quaternion_scale_covariance_core':
            text = rounding(text,'round_cov_value','CACC_W','COV_SHIFT','-4')
        elif name == 'screen_covariance_core':
            text = rounding(text,'round_cov_to_q8','COV_ACC_W','COV_TO_Q8_SHIFT','+4')
        elif name == 'axi4_t08_attribute_read_engine':
            text = edit(text, 'parameter bit EARLY_ADVANCE', "parameter bit ENABLE_Q24=1'b0,\n  parameter bit EARLY_ADVANCE")
            text = edit(text, 'logic compressed_q,', 'logic version2_q;\n  logic compressed_q,')
            text = edit(text, 'compressed_q<=0;', 'version2_q<=0;compressed_q<=0;')
            text = edit(text, 'compressed_q<=format_i==1;', 'version2_q<=ENABLE_Q24&&format_i==2;compressed_q<=format_i==1;')
            text = edit(text, 'format_i==1', '(format_i==1||(ENABLE_Q24&&format_i==2))', 3)
            text = edit(text, '||format_i>1||', '||(!ENABLE_Q24&&format_i>1)||')
            text = edit(text, 'm_axi_rdata_i[9:8]!=1', "m_axi_rdata_i[9:8]!=(version2_q?2'd2:2'd1)")
            text = edit(text, "!=16'h3dc8", "!=(version2_q?16'h3ec8:16'h3dc8)")
            text = edit(text, 'u_decoder(.clk_i', 'u_decoder(.version2_i(version2_q),.clk_i')
        elif name == 't08_attribute_decoder':
            text = edit(text, 'input logic clk_i', 'input logic version2_i,input logic clk_i')
            text = edit(text, "s_packet_i[9:8]!=2'd1", "s_packet_i[9:8]!=(version2_i?2'd2:2'd1)")
            text = edit(text, '!=RAW_HEADER', "!=(version2_i?16'h3ec8:RAW_HEADER)")
        dest = BUILD/Path(path).name
        freeze(dest,text)
        sources[str(dest.relative_to(ROOT))] = sha(dest)
        files[i] = str(dest)
    assert changed == modules
    filelist = BUILD/'sources.f'
    freeze(filelist,'\n'.join(files)+'\n')
    old = previous/'tb_t08_bbox_pair.sv'
    bench = BUILD/'tb_t08_dual_precision.sv'
    text = old.read_text().replace(old.stem,bench.stem)
    text = edit(text, 'gs_accel_system_top #(', "gs_accel_system_top #(.ENABLE_Q24_ATTRIBUTES(1'b1),")
    text = edit(text, 't08_format==0?9', '(t08_format==0||t08_format==3)?9')
    text = edit(text, '(t08_format==1&&observed==0)', '(((t08_format==1||t08_format==2))!=(observed!=0))')
    text = edit(text, "apb_write(12'h0f0,2);", "apb_write(12'h0f0,t08_format^2);")
    freeze(bench,text)
    for p in [filelist,bench]:
        sources[str(p.relative_to(ROOT))] = sha(p)
    cmd = prior['command'].copy()
    cmd[cmd.index('-f')+1] = str(filelist)
    cmd[cmd.index(str(old))] = str(bench)
    cmd[cmd.index('--top-module')+1] = bench.stem
    cmd[cmd.index('--Mdir')+1] = str(LOCAL)
    marker = BUILD/'binary.json'
    exe = LOCAL/'simulation'
    if marker.exists():
        info = read(marker)
        assert info['sources']==sources and info['command']==cmd and sha(exe)==info['elf_sha256']
    else:
        run_logged(cmd,BUILD/'build.log')
        info = dict(sources=sources,command=cmd,elf_sha256=sha(exe),exe=str(exe))
        save(marker,info)
    return info


def scene_cases(scene,info):
    q20 = PREVIOUS/'real'/scene/'1'
    q24 = COMPACT/'real'/scene
    meta = read(PREVIOUS/'inputs'/scene/'manifest.json')
    rows = []
    for fmt in (1,2,0,3):
        reference = q20 if fmt<2 else q24/f'f{fmt}'
        cmd = read(reference/'run.command.json')
        cmd[0] = info['exe']
        d = OUT/'real'/scene/f'f{fmt}'
        d.mkdir(parents=True,exist_ok=True)
        paths = dict(RGB=d/'rgb.memh',FRAME=d/'state.memh',SORTED_TRACE=d/'sorted.txt')
        if fmt==0:
            paths['ATTR'] = PRECISION/'inputs'/scene/'raw.memh'
            cmd[cmd.index('+ATTR_FORMAT=1')] = '+ATTR_FORMAT=0'
        cmd = ['+'+k+'='+str(paths[k]) if (k:=a.partition('=')[0][1:]) in paths else a for a in cmd]
        inputs = {k:sha(a.partition('=')[2]) for a in cmd if (k:=a.partition('=')[0][1:]) in ('ATTR','MEAN','CAMERA')}
        attr_hash = (meta['input_sha256']['attribute.memh'] if fmt==1 else
                     read(PRECISION/'real'/scene/'f0/launch.json')['input_sha256']['ATTR'] if fmt==0 else
                     read(reference/'launch.json')['inputs']['ATTR'])
        assert inputs==dict(ATTR=attr_hash, MEAN=meta['input_sha256']['mean.memh'], CAMERA=meta['input_sha256']['camera.memh'])
        launch = dict(command=cmd,inputs=inputs,elf_sha256=info['elf_sha256'])
        marker = d/'launch.json'
        if marker.exists():
            assert read(marker)==launch
        else:
            save(marker,launch)
        execution = d/'run.execution.json'
        if execution.exists() and read(execution)['exit_code']==0:
            assert sha(d/'run.log')==read(execution)['log_sha256']
        else:
            run_logged(cmd,d/'run.log')
        log = (d/'run.log').read_text()
        assert 'PASS: tb_t08_dual_precision' in log and 'error=00000000' in log
        counters = blocks(log)
        actual = counters['REAL_T08']
        assert actual['format']==fmt and actual['requests']>0
        assert (actual['world_precomputed']>0)==(fmt in (1,2))
        assert actual['precomputed']==actual['world_precomputed']
        image = decode_rgb888(bytes.fromhex((d/'rgb.memh').read_text()),meta['width'],meta['height'])
        Image.fromarray(image).save(d/'frame.png')
        assert Image.open(d/'frame.png').tobytes()==image.tobytes()
        hashes = {f:sha(d/f) for f in ['rgb.memh','frame.png','state.memh','sorted.txt']}
        assert all(sha(reference/f)==h for f,h in hashes.items()), (scene,fmt,hashes)
        if fmt!=0:
            old_counts = blocks((reference/'run.log').read_text())
            for section in ['REAL_T08','REAL_DMA_COUNTS','REAL_END_TO_END']:
                assert counters[section]==old_counts[section], (scene,fmt,section)
        rows.append(dict(format=fmt,counters=counters,outputs=hashes,execution=read(execution)))
    result = dict(scene=scene,meta=meta,rows=rows)
    save(OUT/'real'/scene/'result.json',result)
    return result


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        save(OUT/'status.json',dict(status='BUILDING',pid=os.getpid(),signed_off=False))
        try:
            info=build()
            save(OUT/'status.json',dict(status='RUNNING_FOUR_MODES',pid=os.getpid(),signed_off=False))
            with ThreadPoolExecutor(max_workers=3) as pool:
                rows=list(pool.map(lambda s:scene_cases(s,info),SCENES))
            assert all(sha(ROOT/p)==digest for p,digest in info['sources'].items())
            save(OUT/'report.json',dict(results=rows,script_sha256=sha(__file__),signed_off=False,
                 scope='Same binary four commands, fresh process per case, late shadow writes. Native hotspot subsets.'))
            save(OUT/'status.json',dict(status='FOUR_MODES_COMPARED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise


if __name__=='__main__':
    main()
