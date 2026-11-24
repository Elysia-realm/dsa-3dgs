"""Candidate v1 through production APB/AXI/QSU/render/RGB; bounded subsets."""
import argparse,sys,shutil
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,WORK,T07,SCENES,PROFILE,read,save,sha,run_logged,production_sources
from scripts.run_t01_wsl_real import blocks
from scripts.run_t07_real import state_values
from scripts.read_rgb888_frame import decode_rgb888
from model.io.t08_attribute_codec import encode_record
from PIL import Image
OUT=BASE/'integration_20261107'
BENCH='verification/rtl/tb_t08_integrated.sv'

def prepare():
    source=ROOT/'verification/rtl/tb_t07_workload.sv'
    s=source.read_text().replace('tb_t07_workload','tb_t08_integrated').replace('dut.g_axi_attr.u_attr_dma','dut.g_t08_attr.u_attr_dma')
    s=s.replace('gs_accel_system_top #(',"gs_accel_system_top #(.ENABLE_COMPRESSED_ATTRIBUTES(1'b1),",1)
    s=s.replace('  integer state_pending_beats[0:3];','''  integer t08_format=0;
  longint unsigned t08_expected_beats=0,t08_precomputed=0,t08_requests=0;
  longint unsigned t08_world_pre[0:`TB_LANES-1];
  function automatic integer t08_record_beats(input logic[15:0]h);
    if(h[10])return 9;
    case(h[12:11])0:return 3;1:return 4;2:return 6;3:return h[13]?9:8;endcase
  endfunction
  always @(posedge clk_i)if(rst_ni)begin
    if(dut.attr_req_valid&&dut.attr_req_ready)begin
      t08_requests<=t08_requests+1;
      t08_expected_beats<=t08_expected_beats+(t08_format==0?9:t08_record_beats(attr_mem[dut.attr_req_gid*9][15:0]));
    end
    if(dut.attr_rsp_valid&&dut.attr_rsp_ready&&dut.compressed_precomputed)t08_precomputed<=t08_precomputed+1;
  end
  generate for(genvar l=0;l<`TB_LANES;l++)begin:g_t08_observe
    initial t08_world_pre[l]=0;
    always @(posedge clk_i)if(rst_ni&&
      dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[l].u_lane.world_cov_valid&&
      dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[l].u_lane.world_cov_ready&&
      dut.u_frame.u_render.u_render.u_front.u_projection.g_lane[l].u_lane.world_aux[246])t08_world_pre[l]<=t08_world_pre[l]+1;
  end endgenerate
  integer state_pending_beats[0:3];''')
    # TB_LANES was previously defined below observations; set the compatibility
    # fallback before using it (release command supplies four explicitly).
    s=s.replace('module tb_t08_integrated;','module tb_t08_integrated;\n`ifndef TB_LANES\n`define TB_LANES 1\n`endif')
    s=s.replace("apb_write(12'h03c,ATTR_BASE[31:0]);", "if(!$value$plusargs(\"ATTR_FORMAT=%d\",t08_format))t08_format=0;\n    apb_write(12'h0f0,t08_format);\n    apb_write(12'h03c,ATTR_BASE[31:0]);",1)
    needle="apb_write(12'h000,batch_list_mode?batch_control:(two_batch_mode?32'h11:32'h1));"
    s=s.replace(needle,needle+"\n    if($test$plusargs(\"MUTATE_FORMAT\"))apb_write(12'h0f0,2);",1)
    s=s.replace('attr_beats!=(qsu_requested?dut.qsu_stats[31:0]:total_workload_count)*9','64\'(attr_beats)!=t08_expected_beats')
    s=s.replace('$display("PASS: tb_t08_integrated");','''begin
      longint unsigned observed;observed=0;
      for(integer l=0;l<LANES;l++)observed+=t08_world_pre[l];
      if(observed!=t08_precomputed||(t08_format==1&&observed==0))$fatal(1,"T08 precompute path missing or tag accounting mismatch");
      $display("REAL_T08 format=%0d requests=%0d expected_beats=%0d precomputed=%0d world_precomputed=%0d",t08_format,t08_requests,t08_expected_beats,t08_precomputed,observed);
    end
    $display("PASS: tb_t08_integrated");''')
    p=ROOT/BENCH
    if p.exists():assert p.read_text()==s
    else:p.write_text(s)
    for name in SCENES:
        d=OUT/'inputs'/name;d.mkdir(parents=True,exist_ok=True)
        path=ROOT/'experiments/t06_release_20261022/subset'/name/'attribute.memh'
        words=[int(x,16) for x in path.read_text().split()];packed=[];beats=0
        for i in range(512):
            raw=sum(words[9*i+j]<<(128*j) for j in range(9));enc=encode_record(raw);beats+=enc['beats']
            packed.extend(f'{(enc["record"]>>(128*j))&((1<<128)-1):032x}\n' for j in range(9))
        text=''.join(packed);target=d/'attribute.memh'
        if target.exists():assert target.read_text()==text
        else:target.write_text(text)
        save(d/'manifest.json',dict(scene=name,records=512,slot_bytes=144,useful_beats=beats,
             source_sha256=sha(path),encoded_sha256=sha(target),codec_sha256=sha(ROOT/'model/io/t08_attribute_codec.py')))

def sources():
    m=production_sources();m[BENCH]=sha(ROOT/BENCH)
    for p in ['verification/rtl/t06_perf_measurements.svh','verification/rtl/t06_memory_layout.svh','verification/rtl/t06_memory_scratch.svh','verification/rtl/t06_scratch_signals.svh']:m[p]=sha(ROOT/p)
    return m

def build():
    prepare();old=read(T07/'build/subset/C/binary.json');m=sources()
    cmd=[x.replace('tb_t07_workload','tb_t08_integrated') for x in old['command']]
    work=WORK/'integration_20261107';work.mkdir(parents=True,exist_ok=True);d=OUT/'build'
    cmd[cmd.index('--Mdir')+1]=str(work)
    marker=d/'binary.json';exe=work/'simulation'
    if marker.exists():
        prior=read(marker);assert prior['source_sha256']==m and prior['command']==cmd and sha(exe)==prior['binary_sha256'];return prior
    for f,h in m.items():
        p=d/'source_snapshot'/f;p.parent.mkdir(parents=True,exist_ok=True)
        if p.exists():assert sha(p)==h
        else:shutil.copy2(ROOT/f,p)
    save(d/'source_snapshot/manifest.json',m);run_logged(cmd,d/'build.log')
    assert sources()==m
    info=dict(path=str(exe),command=cmd,source_sha256=m,binary_sha256=sha(exe),parameters={**old['parameters'],'ENABLE_COMPRESSED_ATTRIBUTES':1})
    save(marker,info);return info

def case(info,name,mode,axi,fmt):
    old=T07/'real/subset/C'/name/f'm{mode}_{axi}'
    ref=read(old/'result.json');dest=OUT/'real'/name/f'm{mode}_{axi}_f{fmt}';dest.mkdir(parents=True,exist_ok=True)
    marker=dest/'result.json'
    if marker.exists():
        r=read(marker);assert r['binary_sha256']==info['binary_sha256'];assert all(sha(dest/f)==h for f,h in r['evidence_sha256'].items());return r
    assert not (dest/'launch.json').exists(),'unfinished run must be inspected before retry'
    cmd=read(old/'run.command.json');cmd[0]=info['path']
    for i,x in enumerate(cmd):
        if not x.startswith('+'):continue
        key=x[1:].split('=',1)[0]
        if key in {'FRAME','RGB','SORTED_TRACE'}:cmd[i]='+'+key+'='+str(dest/{'FRAME':'state.memh','RGB':'rgb.memh','SORTED_TRACE':'sorted.txt'}[key])
        if key=='ATTR' and fmt:cmd[i]='+ATTR='+str(OUT/'inputs'/name/'attribute.memh')
    cmd+=['+ATTR_FORMAT='+str(fmt),'+MUTATE_FORMAT']
    hashes={x.split('=',1)[0][1:]:sha(Path(x.split('=',1)[1])) for x in cmd if x.startswith(('+MEAN=','+CAMERA=','+ATTR='))}
    assert sources()==info['source_sha256']
    save(dest/'launch.json',dict(command=cmd,input_sha256=hashes,source_sha256=info['source_sha256'],binary_sha256=info['binary_sha256'],driver_sha256=sha(Path(__file__))))
    execution=run_logged(cmd,dest/'run.log');log=(dest/'run.log').read_text();c=blocks(log)
    assert 'PASS: tb_t08_integrated' in log and 'error=00000000' in log
    raw=bytes(int(x,16) for x in (dest/'rgb.memh').read_text().split())
    assert raw==(old/'frame.rgb').read_bytes(),('RGB mismatch',name,mode,axi,fmt)
    assert (dest/'sorted.txt').read_bytes().replace(b'\r\n',b'\n')==(old/'sorted.txt').read_bytes().replace(b'\r\n',b'\n')
    state=state_values(dest/'state.memh',1);baseline=state_values(old/'state.memh',1);assert len(state)==len(baseline)
    assert all(rgb==rgb0 and (t==t0 or (t<=7 and t0<=7)) for (rgb,t),(rgb0,t0) in zip(state,baseline))
    assert c['REAL_T08']['format']==fmt
    expected=read(OUT/'inputs'/name/'manifest.json')['useful_beats'] if fmt else ref['gaussians']*9
    assert c['REAL_DMA_COUNTS']['attribute_beats']==expected
    if fmt:assert expected<ref['counters']['REAL_DMA_COUNTS']['attribute_beats']
    w,h=ref['width'],ref['height'];(dest/'frame.rgb').write_bytes(raw);Image.fromarray(decode_rgb888(raw,w,h)).save(dest/'frame.png')
    assert Image.open(dest/'frame.png').tobytes()==decode_rgb888(raw,w,h).tobytes()
    row=dict(status='PASS_SUBSET_ONLY',scene=name,camera=SCENES[name],gaussians=512,full_model=False,width=w,height=h,
       mode=mode,axi=axi,format=fmt,command_cycles=c['REAL_END_TO_END']['command_cycles'],historical_cycles=ref['command_cycles'],
       counters=c,execution=execution,parameters=info['parameters'],source_sha256=info['source_sha256'],input_sha256=hashes,
       binary_sha256=info['binary_sha256'],signed_off=False,GT_pass=False)
    row['evidence_sha256']={p.name:sha(p) for p in dest.iterdir() if p.is_file() and p.name!='result.json'};save(marker,row)
    print('PASS subset',name,mode,axi,fmt,row['command_cycles'],'attribute beats',expected,flush=True);return row

def main():
    p=argparse.ArgumentParser();p.add_argument('--matrix',action='store_true');p.add_argument('--build-only',action='store_true');a=p.parse_args()
    info=build()
    if a.build_only:return
    cases=[(n,m,ax,fmt) for n in SCENES for m in (range(4) if a.matrix else [0]) for ax in (['ideal','limited'] if a.matrix else ['ideal']) for fmt in [0,1]]
    with ThreadPoolExecutor(max_workers=2) as pool:rows=list(pool.map(lambda x:case(info,*x),cases))
    save(OUT/('matrix_report.json' if a.matrix else 'smoke_report.json'),dict(status='PASS_SUBSET_ONLY',results=rows,signed_off=False))

if __name__=='__main__':main()
