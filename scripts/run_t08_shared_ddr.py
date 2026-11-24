"""Return real LPDDR4 timing to the integrated renderer's seven AXI channels."""
from concurrent.futures import ThreadPoolExecutor
import fcntl
import os
from pathlib import Path
import sys
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_ddr_windows import RAM,CFG
from scripts.run_t08_terminated_blocks import OUT as PRIOR
from scripts.run_t08_q24_compact import edit,freeze,encode_q24,MASK128
from scripts.run_t01_wsl_real import blocks
from scripts.t08_common import BASE,WORK,SCENES,read,save,sha,run_logged
from scripts.read_rgb888_frame import decode_rgb888
from scripts.run_t08_dual_full import compare_states

OUT=BASE/'shared_ddr_render_20261123'
LOCAL=WORK/OUT.name


def build():
    old=read(PRIOR/'build/binary.json')
    sources=old['sources'].copy()
    assert all(sha(ROOT/p)==h for p,h in sources.items())
    cmd=old['command'].copy()
    top='tb_t08_shared_ddr'
    d=OUT/'build'
    d.mkdir(parents=True,exist_ok=True)
    LOCAL.mkdir(parents=True,exist_ok=True)
    oldbench=PRIOR/'build/tb_t08_terminated_blocks.sv'
    body=oldbench.read_text().replace(oldbench.stem,top)
    obs=ROOT/'verification/rtl/t08_shared_lpddr.svh'
    cpp=ROOT/'verification/rtl/t08_shared_lpddr.cpp'
    body=edit(body,'endmodule',f'`include "{obs.relative_to(ROOT)}"\nendmodule')
    body=edit(body,f'$display("PASS: {top}");',f'report_shared_memory();$display("PASS: {top}");')
    for p,id in [('camera',0),('mean',1),('attr',2)]:
        needle=f'!m_axi_{p}_rvalid_i&&{p}_left>0'
        body=edit(body,needle,needle+f'&&(!ddr_timed||ddr_read_done[{id}])')
    for index in ['state_rsp_select']+[f'(state_rsp_select+{n})&3' for n in (1,2,3)]:
        needle=f'state_delay[{index}]==0'
        body=edit(body,needle,needle+f'&&(!ddr_timed||ddr_read_done[4+({index})])')
    for k in ('b_get+1','b_get'):
        needle=k+'<b_put&&axi_cycle'
        body=edit(body,needle,k+f'<b_put&&(!ddr_timed||{k}<ddr_out_done)&&axi_cycle')
    original='verification/rtl/t06_memory_scratch.svh'
    scratch=d/'scratch.svh'
    s=edit((ROOT/original).read_text(),'qsu_read_left!=0&&qsu_read_delay==0;',
           'qsu_read_left!=0&&qsu_read_delay==0&&(!ddr_timed||ddr_read_done[3]);')
    freeze(scratch,edit(s,'qsu_b_get<qsu_committed&&qsu_tick','qsu_b_get<qsu_committed&&(!ddr_timed||qsu_b_get<ddr_qsu_done)&&qsu_tick'))
    bench=d/(top+'.sv')
    freeze(bench,edit(body,original,str(scratch.relative_to(ROOT))))
    cmd[cmd.index(str(oldbench))]=str(bench)
    cmd[cmd.index('--top-module')+1]=top
    cmd[cmd.index('--Mdir')+1]=str(LOCAL)
    objects=sorted((RAM/'obj').glob('*.o'))
    cmd+=['-CFLAGS',f'-I{RAM}/src -DRAMULATOR','-LDFLAGS',' '.join(map(str,objects)),str(cpp)]
    for p in [bench,scratch,obs,cpp,CFG,*objects,*sorted((RAM/'src').glob('*.h'))]:
        sources[str(p)]=sha(p)
    marker=d/'binary.json'
    exe=LOCAL/'simulation'
    if marker.exists():
        data=read(marker)
        assert data['command']==cmd and data['sources']==sources and data['elf_sha256']==sha(exe)
    else:
        run_logged(cmd,d/'build.log')
        data=dict(command=cmd,sources=sources,elf_sha256=sha(exe),exe=str(exe))
        save(marker,data)
    return data


def prepare(kind,scene):
    if kind=='full128':
        folder=PRIOR/'full128'/scene
        old=read(folder/'launch.json')
        raw=Path(read(BASE/'inputs/native'/scene/'manifest.json')['inputs']['ATTR'])
        compact=Path(next(a[6:] for a in old['command'] if a.startswith('+ATTR=')))
        assert old['inputs']['ATTR']==sha(compact)
        assert sha(raw)==read(compact.parent/'manifest.json')['provenance']['raw_sha256']
        return old['command'],raw,compact,old['inputs']
    folder=BASE/'integration_20261107/real'/scene/'m0_ideal_f0'
    cmd=read(folder/'run.command.json')
    raw=Path(next(a[6:] for a in cmd if a.startswith('+ATTR=')))
    inputs=read(folder/'result.json')['input_sha256']
    assert sha(raw)==inputs['ATTR']
    words=raw.read_text().split()
    assert len(words)==512*9
    compact=OUT/'inputs'/scene/'v2.memh'
    compact.parent.mkdir(parents=True,exist_ok=True)
    lines=[]
    for i in range(0,len(words),9):
        rec=sum(int(v,16)<<(128*j) for j,v in enumerate(words[i:i+9]))
        packet,_=encode_q24(rec)
        lines.extend(f'{(packet>>(128*j))&MASK128:032x}\n' for j in range(9))
    freeze(compact,''.join(lines))
    return cmd,raw,compact,inputs


def case(kind,scene,fmt,timed,info,prepared):
    old,raw,compact,inputs=prepared
    cmd=old.copy()
    cmd[0]=info['exe']
    cmd[cmd.index(next(a for a in cmd if a.startswith('+ATTR_FORMAT=')))]=f'+ATTR_FORMAT={fmt}'
    d=OUT/kind/scene/f'f{fmt}_t{timed}'
    d.mkdir(parents=True,exist_ok=True)
    if timed:cmd+=['+LPDDR_TIMED',f'+MODEL_CFG={CFG}',f'+MODEL_STATS={d}/model.stats']
    paths=dict(FRAME=d/'state.memh',RGB=d/'rgb.memh',SORTED_TRACE=d/'sorted.txt',ATTR=compact if fmt==2 else raw)
    cmd=['+'+k+'='+str(paths[k]) if (k:=a.partition('=')[0][1:]) in paths else a for a in cmd]
    if not any(a.startswith('+LABEL=') for a in cmd):cmd.append(f'+LABEL={scene}_{kind}')
    hashes={k:sha(a.partition('=')[2]) for a in cmd if (k:=a.partition('=')[0][1:]) in ('MEAN','ATTR','CAMERA')}
    assert all(inputs[k]==hashes[k] for k in ('MEAN','CAMERA'))
    config=dict(command=cmd,elf_sha256=info['elf_sha256'],input_sha256=hashes)
    marker=d/'launch.json'
    if marker.exists():assert read(marker)==config
    else:save(marker,config)
    ex=d/'run.execution.json'
    if ex.exists() and read(ex)['exit_code']==0:assert sha(d/'run.log')==read(ex)['log_sha256']
    else:run_logged(cmd,d/'run.log')
    log=(d/'run.log').read_text()
    assert 'PASS: tb_t08_shared_ddr' in log and 'error=00000000' in log
    c=blocks(log)
    assert c['REAL_QSU']['enabled']==1 and c['REAL_T08']['requests']>0
    assert (c['REAL_T08']['world_precomputed']>0)==(fmt==2)
    cam=Path(next(a[8:] for a in cmd if a.startswith('+CAMERA=')))
    words=cam.read_text().split()
    width,height=(int(words[j],16) for j in (25,26))
    rgb=decode_rgb888(bytes.fromhex((d/'rgb.memh').read_text()),width,height)
    Image.fromarray(rgb).save(d/'frame.png')
    assert Image.open(d/'frame.png').tobytes()==rgb.tobytes()
    if timed:
        import re
        st=(d/'model.stats').read_text()
        assert int(re.search(r'ramulator\.incoming_requests\s+(\d+)',st)[1])==c['REAL_LPDDR']['lines']
        assert c['REAL_LPDDR']['qsu_b']==c['REAL_DMA_COUNTS']['qsu_write_bursts']
        assert c['REAL_LPDDR']['out_b']==c['REAL_DMA_COUNTS']['output_write_bursts']
    out=dict(format=fmt,timed=timed,counters=c,cycles=c['REAL_END_TO_END']['command_cycles'],execution=read(ex),
             hashes={f:sha(d/f) for f in ('frame.png','rgb.memh','sorted.txt','state.memh','launch.json')},
             stats_sha256=sha(d/'model.stats') if timed else None)
    save(d/'result.json',out)
    return d,out


def scene_cases(kind,scene,info):
    prep=prepare(kind,scene)
    # For full models use the frozen Q24 compact reference. Fresh ideal runs anchor the pilot.
    ref=PRIOR/'full128'/scene if kind=='full128' else None
    rows=[]
    for timed in ((0,1) if kind=='subset' else (1,)):
        for fmt in (3,2):
            d,row=case(kind,scene,fmt,timed,info,prep)
            if ref is None:ref=d
            for f in ('rgb.memh','sorted.txt','frame.png'):
                assert row['hashes'][f]==sha(ref/f),(kind,scene,fmt,timed,f)
            row['terminal_t_differences']=compare_states(d/'state.memh',ref/'state.memh')
            rows.append(row)
    save(OUT/kind/scene/'comparison.json',dict(scene=scene,kind=kind,rows=rows,signed_off=False))
    return rows


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    with (OUT/'batch.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            save(OUT/'status.json',dict(status='BUILDING',pid=os.getpid(),signed_off=False))
            info=build()
            for kind in ('subset','full128'):
                save(OUT/'status.json',dict(status='RUNNING_'+kind.upper(),pid=os.getpid(),signed_off=False))
                with ThreadPoolExecutor(max_workers=3) as pool:rows=list(pool.map(lambda s:scene_cases(kind,s,info),SCENES))
                save(OUT/(kind+'_report.json'),dict(results=rows,scenes=SCENES,signed_off=False))
            assert all(sha(ROOT/p)==h for p,h in info['sources'].items())
            save(OUT/'status.json',dict(status='FULL128_SHARED_DDR_COMPARED',signed_off=False))
        except BaseException:
            save(OUT/'status.json',dict(status='FAILED_OR_INTERRUPTED',signed_off=False))
            raise
