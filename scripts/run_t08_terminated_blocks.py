"""Check a bounded block termination counter before pixel expansion against frozen QSU-on frames."""
from concurrent.futures import ThreadPoolExecutor
import fcntl
import os
from pathlib import Path
import sys

from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,WORK,SCENES,read,save,sha,run_logged
from scripts.run_t08_qsu_root_precount import OUT as LOW
from scripts.run_t08_qsu_native_full import OUT as NATIVE
from scripts.run_t08_q24_compact import edit,freeze
from scripts.read_rgb888_frame import decode_rgb888
from scripts.run_t01_wsl_real import blocks

OUT=BASE/'terminated_blocks_20261123'
LOCAL=WORK/OUT.name
RTL=ROOT/'rtl/raster/terminated_block_counter.sv'
BENCH=ROOT/'verification/rtl/tb_t08_terminated_block_counter.sv'


def unit():
    d=OUT/'units'
    w=LOCAL/'units'
    w.mkdir(parents=True,exist_ok=True)
    exe=w/'counter.vvp'
    run_logged(['/usr/bin/iverilog','-g2012','-s',BENCH.stem,'-o',str(exe),str(RTL),str(BENCH)],d/'build.log')
    ex=run_logged(['/usr/bin/vvp',str(exe)],d/'run.log')
    assert 'PASS terminated block counter' in (d/'run.log').read_text()
    save(d/'report.json',dict(execution=ex,sources={str(p):sha(p) for p in (BENCH,RTL)},exe_sha256=sha(exe)))


def build():
    prior=read(NATIVE/'build/1/binary.json')
    sources=prior['sources'].copy()
    assert all(sha(ROOT/p)==h for p,h in sources.items())
    cmd=prior['command'].copy()
    d=OUT/'build'
    d.mkdir(parents=True,exist_ok=True)
    listing=Path(cmd[cmd.index('-f')+1])
    files=listing.read_text().splitlines()
    for name in ['gaussian_frame_render_pipeline','gaussian_sorted_render_pipeline','gaussian_ordered_render_frontend','ordered_block_raster_frontend']:
        i,=[i for i,f in enumerate(files) if Path(f).stem==name]
        body=(ROOT/files[i]).read_text()
        if name in ('gaussian_frame_render_pipeline','gaussian_sorted_render_pipeline'):
            if name=='gaussian_sorted_render_pipeline':
                body=edit(body,'input logic cfg_cov_q24_i,','input logic new_frame_i,input logic cfg_cov_q24_i,')
            signal='accepted_start&&!frame_continue_i' if name=='gaussian_frame_render_pipeline' else 'new_frame_i'
            body=edit(body,'.cfg_cov_q24_i(cfg_cov_q24_i),.clk_i',f'.new_frame_i({signal}),.cfg_cov_q24_i(cfg_cov_q24_i),.clk_i')
        elif name=='gaussian_ordered_render_frontend':
            body=edit(body,'input logic cfg_cov_q24_i,','input logic new_frame_i,input logic cfg_cov_q24_i,')
            body=edit(body,'))u_raster(', '))u_raster(.new_frame_i(new_frame_i),')
        else:
            body=edit(body,'input logic clk_i,input logic rst_ni,','input logic new_frame_i,input logic clk_i,input logic rst_ni,')
            body=edit(body,'    assign block_ready_o=shape_reject_accept?1\'b1:expand_block_ready;',"""
    logic coarse_full,coarse_skip,was_stalled_q,coarse_skipped_q;
    terminated_block_counter u_coarse(.clk_i(clk_i),.rst_ni(rst_ni),.new_frame_i(new_frame_i),
        .update_i(commit_valid_o&&commit_ready_i&&commit_newly_terminated_o),
        .update_block_i(commit_block_id_o),.query_block_i(input_block_id),.query_full_o(coarse_full));
    assign coarse_skip=ENABLE_PIXEL_TERMINATION_SKIP && block_valid_i && !culled_i && !shape_reject_accept && coarse_full && !was_stalled_q;
    assign block_ready_o=(coarse_skip||shape_reject_accept)?1'b1:expand_block_ready;
    always_ff @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin was_stalled_q<=0;coarse_skipped_q<=0;end
        else begin was_stalled_q<=block_valid_i&&!block_ready_o;coarse_skipped_q<=coarse_skip;end
    end""")
            body=edit(body,'.s_valid_i(block_valid_i&&!shape_reject_accept)', '.s_valid_i(block_valid_i&&!shape_reject_accept&&!coarse_skip)')
            body=edit(body,'=expand_empty_pulse||shape_rejected_pulse_o;', '=expand_empty_pulse||shape_rejected_pulse_o||coarse_skipped_q;')
        dest=d/(name+'.sv')
        freeze(dest,body)
        files[i]=str(dest)
        sources[str(dest.relative_to(ROOT))]=sha(dest)
    files.append(str(RTL))
    filelist=d/'sources.f'
    freeze(filelist,'\n'.join(files)+'\n')
    cmd[cmd.index('-f')+1]=str(filelist)
    oldbench=NATIVE/'build/1/tb_t08_native_root.sv'
    bench=d/'tb_t08_terminated_blocks.sv'
    body=oldbench.read_text().replace(oldbench.stem,bench.stem)
    monitor="""
  logic [63:0] checked_pixels[32768];
  longint unsigned coarse_updates=0,coarse_skips=0;
  always @(posedge clk_i)if(rst_ni)begin
    if(F.new_frame_i)begin
      for(int b=0;b<32768;b++)checked_pixels[b]=0;
    end else begin
      if(F.coarse_skip)begin
        if(F.input_block_id>=32768||checked_pixels[F.input_block_id]!==64'hffffffffffffffff)
          $fatal(1,"coarse skip without 64 unique committed pixels");
        coarse_skips++;
      end
      if(F.commit_valid_o&&F.commit_ready_i&&F.commit_newly_terminated_o&&F.commit_block_id_o<32768)begin
        if(checked_pixels[F.commit_block_id_o][F.u_raster.commit_pixel_in_block])$fatal(1,"duplicate first termination");
        checked_pixels[F.commit_block_id_o][F.u_raster.commit_pixel_in_block]=1;
        coarse_updates++;
      end
    end
  end
""".replace('F.','dut.u_frame.u_render.u_render.u_raster.')
    body=edit(body,'endmodule',monitor+'\nendmodule')
    key=f'$display("PASS: {bench.stem}");'
    freeze(bench,edit(body,key,'$display("REAL_COARSE_BLOCK updates=%0d skipped=%0d",coarse_updates,coarse_skips);\n    '+key))
    for p in [RTL,bench,filelist]:
        sources[str(p.relative_to(ROOT))]=sha(p)
    cmd[cmd.index(str(oldbench))]=str(bench)
    cmd[cmd.index('--top-module')+1]=bench.stem
    cmd[cmd.index('--Mdir')+1]=str(LOCAL)
    marker=d/'binary.json'
    exe=LOCAL/'simulation'
    if marker.exists():
        info=read(marker)
        assert info['sources']==sources and info['command']==cmd and sha(exe)==info['elf_sha256']
    else:
        run_logged(cmd,d/'build.log')
        info=dict(exe=str(exe),sources=sources,elf_sha256=sha(exe),command=cmd)
        save(marker,info)
    return info


def run_scene(scene,kind,info):
    native=kind=='native'
    ref=(NATIVE/'real'/scene/'1') if native else (LOW/'real'/scene)
    baseline=read(ref/'result.json')
    orig=read(ref/'launch.json')
    assert sha(ref/'launch.json')==baseline['hashes']['launch.json']
    cmd=orig['command'].copy()
    for arg in cmd:
        key,_,value=arg.partition('=')
        if key[1:] in ('MEAN','ATTR','CAMERA'):
            assert sha(value)==orig['inputs'][key[1:]]
    d=OUT/kind/scene
    d.mkdir(parents=True,exist_ok=True)
    cmd[0]=info['exe']
    outputs=dict(FRAME='state.memh',RGB='rgb.memh',SORTED_TRACE='sorted.txt')
    cmd=['+'+k+'='+str(d/outputs[k]) if (k:=a.partition('=')[0][1:]) in outputs else a for a in cmd]
    meta=read(BASE/'inputs/native'/scene/'manifest.json')
    if not any(a.startswith('+LABEL=') for a in cmd):
        cmd.append(f"+LABEL={scene}_camera{meta['camera_index']}")
    config=dict(command=cmd,inputs=orig['inputs'],baseline_result_sha256=sha(ref/'result.json'),elf_sha256=info['elf_sha256'])
    marker=d/'launch.json'
    if marker.exists():
        assert read(marker)==config
    else:
        save(marker,config)
    ex=d/'run.execution.json'
    if ex.exists() and read(ex)['exit_code']==0:
        assert sha(d/'run.log')==read(ex)['log_sha256']
    else:
        run_logged(cmd,d/'run.log')
    log=(d/'run.log').read_text()
    assert 'PASS: tb_t08_terminated_blocks' in log and 'error=00000000' in log
    c=blocks(log)
    old=baseline['counters']
    assert c['REAL_T08']==old['REAL_T08']
    for key in ('input','partitions','leaves','axi_reads','axi_writes'):
        assert c['REAL_QSU'][key]==old['REAL_QSU'][key]
    for filename in ('sorted.txt','rgb.memh'):
        assert sha(d/filename)==baseline['hashes'][filename],(scene,kind,filename)
    wh=orig['inputs']['CAMERA']
    cam=next(Path(a[8:]) for a in cmd if a.startswith('+CAMERA='))
    assert sha(cam)==wh
    words=cam.read_text().split()
    width,height=[int(words[i],16) for i in (25,26)]
    rgb=decode_rgb888(bytes.fromhex((d/'rgb.memh').read_text()),width,height)
    Image.fromarray(rgb).save(d/'frame.png')
    assert sha(d/'frame.png')==baseline['hashes']['frame.png'] and Image.open(d/'frame.png').tobytes()==rgb.tobytes()
    assert sha(ref/'state.memh')==baseline['hashes']['state.memh']
    terminal_changes=n=0
    with (d/'state.memh').open('rb') as a,(ref/'state.memh').open('rb') as b:
        for x,y in zip(a,b,strict=True):
            n+=1
            if x==y:continue
            v,w=int(x,16),int(y,16)
            assert ((v>>55)&65535)==((w>>55)&65535)==1
            assert (v&((1<<39)-1))==(w&((1<<39)-1)) and max((v>>39)&65535,(w>>39)&65535)<=7
            terminal_changes+=1
    assert n==width*height
    result=dict(scene=scene,kind=kind,execution=read(ex),counters=c,terminal_changes=terminal_changes,
                cycles_saved=old['REAL_END_TO_END']['command_cycles']-c['REAL_END_TO_END']['command_cycles'],
                r_grants_saved=old['REAL_SHARED_PE']['R']-c['REAL_SHARED_PE']['R'],
                hashes={f:sha(d/f) for f in ('state.memh','rgb.memh','sorted.txt','frame.png','launch.json')})
    save(d/'result.json',result)
    return result


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            save(OUT/'status.json',dict(status='UNIT_AND_BUILD',pid=os.getpid(),signed_off=False))
            unit()
            info=build()
            rows=[]
            for kind,scenes in [('full128',SCENES),('native',['train','truck'])]:
                save(OUT/'status.json',dict(status='RUNNING_'+kind.upper(),pid=os.getpid(),signed_off=False))
                with ThreadPoolExecutor(max_workers=3) as pool:
                    batch=list(pool.map(lambda s:run_scene(s,kind,info),scenes))
                save(OUT/(kind+'_report.json'),dict(results=batch,signed_off=False))
                rows.extend(batch)
            assert all(sha(ROOT/p)==h for p,h in info['sources'].items())
            save(OUT/'report.json',dict(results=rows,script_sha256=sha(__file__),signed_off=False))
            save(OUT/'status.json',dict(status='PAIRS_COMPARED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise
