"""Real one-record continuation command contract, same-format and mismatch."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,WORK,read,save,sha,run_logged,production_sources

def main():
    early_advance='--early-advance' in sys.argv
    folder='continuation_early_advance_20261120' if early_advance else 'continuation_20261107'
    out=BASE/folder;out.mkdir(parents=True,exist_ok=True);work=WORK/folder;work.mkdir(parents=True,exist_ok=True)
    s=(ROOT/'verification/rtl/tb_t08_integrated.sv').read_text().replace('tb_t08_integrated','tb_t08_continuation')
    if early_advance:
        needle="gs_accel_system_top #(.ENABLE_COMPRESSED_ATTRIBUTES(1'b1),"
        assert s.count(needle)==1
        s=s.replace(needle,needle+".ATTR_DMA_EARLY_ADVANCE(1'b1),")
    s=s.replace('module tb_t08_continuation;','module tb_t08_continuation;\n integer mismatch=0;logic[15:0]saved_epoch;longint unsigned saved_mean,saved_attr;')
    s=s.replace('camera_mem[27][63:32]=32\'h47534301;',"camera_mem[27][63:32]=32'h47534301;camera_mem[27][31:0]=1;")
    s=s.replace('qsu_requested=$test$plusargs("AUTO_QSU");','qsu_requested=0;apb_write(12\'h02c,3);')
    start=s.index("    apb_write(12'h000,batch_list_mode?batch_control:")
    end=s.index('    if(state_in_mode)begin',start)
    s=s[:start]+'''    if(!$value$plusargs("MISMATCH=%d",mismatch))$fatal;
    apb_write(12'h000,32'h11);
    timeout=0;while(!frame_busy_o&&timeout<1000000)begin tick();timeout++;end
    while(frame_busy_o&&timeout<1000000)begin tick();timeout++;end
    if(timeout>=1000000||frame_error_o||!dut.logical_frame_open_q||dut.done_sticky_q||irq_o)$fatal(1,"intermediate batch contract");
    if(mean_beats!=1||t08_requests!=1)$fatal(1,"real first record not executed");
    saved_epoch=epoch_id_o;saved_mean=mean_beats;saved_attr=attr_beats;
    apb_write(12'h0f0,mismatch?(1-t08_format):t08_format);
    apb_write(12'h000,32'h9);
    timeout=0;while(!dut.done_sticky_q&&timeout<1000000)begin tick();timeout++;end
    tick();
    if(timeout>=1000000||!irq_o||frame_busy_o||dut.logical_frame_open_q)$fatal(1,"continuation did not close");
    if(epoch_id_o!=saved_epoch)$fatal(1,"continuation changed epoch");
    if(mismatch)begin
      if(!frame_error_status_o[18]||mean_beats!=saved_mean||attr_beats!=saved_attr||measure_start_count!=1)$fatal(1,"mismatch accepted DMA");
      apb_write(12'h000,4);repeat(3)tick();if(frame_error_o||irq_o)$fatal(1,"mismatch clear failed");
    end else begin
      if(frame_error_o||mean_beats!=2||t08_requests!=2||measure_start_count!=2||rgb_write_beats*16!=rgb_bytes)$fatal(1,"valid continuation failed");
      frame_file=$fopen(rgb_path,"w");for(i=0;i<rgb_bytes;i++)$fdisplay(frame_file,"%02h",rgb_mem[i]);$fclose(frame_file);
    end
    if(b_put!=b_get||dut.attr_dma_busy||m_axi_out_bvalid_i)$fatal(1,"not drained");
    $display("PASS T08 continuation format=%0d mismatch=%0d epoch=%0d",t08_format,mismatch,epoch_id_o);$finish;
'''+s[end:]
    perf=(ROOT/'verification/rtl/t06_perf_measurements.svh').read_text().replace('if(rst_ni&&frame_done_pulse_o',"if(1'b0&&rst_ni&&frame_done_pulse_o")
    pp=out/'measure.svh';pp.write_text(perf);s=s.replace('verification/rtl/t06_perf_measurements.svh',pp.relative_to(ROOT).as_posix())
    tb=out/'tb_t08_continuation.sv';tb.write_text(s)
    info=read(BASE/'integration_20261107/build/binary.json');cmd=[x.replace('tb_t08_integrated','tb_t08_continuation') for x in info['command']]
    cmd=[str(tb) if x=='verification/rtl/tb_t08_continuation.sv' else x for x in cmd];cmd[cmd.index('--Mdir')+1]=str(work)
    source=production_sources();run_logged(cmd,out/'build.log');rows=[]
    for fmt in [0,1]:
        old=read(BASE/f'integration_20261107/real/bonsai/m0_limited_f{fmt}/run.command.json')
        for mismatch in [0,1]:
            d=out/f'f{fmt}_m{mismatch}';d.mkdir(exist_ok=True);run=[x for x in old if x not in ['+MUTATE_FORMAT','+AUTO_QSU']];run[0]=str(work/'simulation')
            for i,x in enumerate(run):
                if x.startswith(('+FRAME=','+RGB=','+SORTED_TRACE=')):run[i]=x.split('=')[0]+'='+str(d/(x.split('=')[0][1:]+'.memh'))
            run+=['+MISMATCH='+str(mismatch)];ex=run_logged(run,d/'run.log');assert 'PASS T08 continuation' in (d/'run.log').read_text()
            rows.append(dict(format=fmt,mismatch=mismatch,status='PASS',execution=ex));print('PASS continuation',fmt,mismatch,flush=True)
    assert (out/'f0_m0/RGB.memh').read_bytes()==(out/'f1_m0/RGB.memh').read_bytes()
    assert all(sha(ROOT/f)==h for f,h in source.items())
    save(out/'report.json',dict(status='PASS',results=rows,source_sha256=source,early_advance=early_advance,signed_off=False,
      scope='One real Gaussian repeated across two legal continuation batches; both format directions rejected on mismatch before second DMA; same-format RGB identical. Control scope, not five-scene complete rendering.'))

if __name__=='__main__':main()
