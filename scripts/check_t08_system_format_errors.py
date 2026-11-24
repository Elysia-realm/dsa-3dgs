"""Production error completion/IRQ/drain/clear on nonempty real input."""
import sys,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t08_common import BASE,WORK,read,save,sha,run_logged,production_sources

def main():
    recover='--recover' in sys.argv
    early_advance='--early-advance' in sys.argv
    folder='system_format_recovery_20261107' if recover else 'system_format_errors_20261107'
    if early_advance:
        folder=folder.replace('_20261107','_early_advance_20261120')
    out=BASE/folder;out.mkdir(parents=True,exist_ok=True)
    work=WORK/folder;work.mkdir(parents=True,exist_ok=True)
    s=(ROOT/'verification/rtl/tb_t08_integrated.sv').read_text().replace('tb_t08_integrated','tb_t08_format_errors')
    if early_advance:
        needle="gs_accel_system_top #(.ENABLE_COMPRESSED_ATTRIBUTES(1'b1),"
        assert s.count(needle)==1
        s=s.replace(needle,needle+".ATTR_DMA_EARLY_ADVANCE(1'b1),")
    s=s.replace('module tb_t08_format_errors;','module tb_t08_format_errors;\n integer injected_fault=0;logic[127:0]saved_header;')
    needle="    apb_write(12'h0f0,t08_format);"
    assert s.count(needle)==1
    s=s.replace(needle,'''    if(!$value$plusargs("FAULT=%d",injected_fault))$fatal;
    saved_header=attr_mem[0];
    case(injected_fault)
      0:t08_format=2;
      1:attr_mem[0][7:0]=0;
      2:attr_mem[0][9:8]=0;
      3:attr_mem[0][15:14]=1;
      4:attr_mem[0][15:0]=16'h05c8;
      default:$fatal;
    endcase
'''+needle)
    needle='    if($test$plusargs("MUTATE_FORMAT"))apb_write(12\'h0f0,2);'
    assert s.count(needle)==1
    s=s.replace(needle,'''    timeout=0;
    while((!frame_error_o||frame_busy_o)&&timeout<1000000)begin tick();timeout++;end
    if(timeout>=1000000||!frame_error_o||!irq_o||!dut.done_sticky_q)$fatal(1,"format error did not complete/IRQ");
    if(b_put!=b_get||m_axi_out_bvalid_i||dut.attr_dma_busy||dut.qsu_rd_busy||dut.qsu_wr_busy||
       qsu_b_get!=qsu_aw_put||qsu_b_get!=qsu_w_put||qsu_read_left!=0)$fatal(1,"format error did not drain");
    if(injected_fault==0)begin
      if(measure_start_count!=0||mean_beats!=0||attr_beats!=0||!frame_error_status_o[18])$fatal(1,"unsupported command format issued DMA");
    end else if(measure_start_count!=1||mean_beats!=512||!dut.attr_dma_error_status[1])$fatal(1,"invalid header did not traverse production DMA");
    $display("T08_FORMAT_ERROR fault=%0d error=%h mean=%0d attr=%0d",injected_fault,frame_error_status_o,mean_beats,attr_beats);
    apb_write(12'h000,4);repeat(4)tick();
    if(frame_error_o||irq_o||frame_busy_o||dut.attr_dma_error)$fatal(1,"format error clear failed");
    $display("PASS T08 production format error fault=%0d drain=1 clear=1",injected_fault);$finish;
''')
    if recover:
        needle='$display("PASS T08 production format error fault=%0d drain=1 clear=1",injected_fault);$finish;'
        assert s.count(needle)==1
        s=s.replace(needle,'''attr_mem[0]=saved_header;apb_write(12'h0f0,1);apb_write(12'h000,1);
    timeout=0;while(!frame_done_pulse_o&&timeout<1000000)begin tick();timeout++;end
    tick();
    if(timeout>=1000000||frame_error_o||!irq_o||frame_busy_o||!dut.done_sticky_q)$fatal(1,"fresh frame after error failed");
    if(b_put!=b_get||m_axi_out_bvalid_i||dut.attr_dma_busy||dut.qsu_rd_busy||dut.qsu_wr_busy)$fatal(1,"recovery frame not drained");
    if(epoch_id_o!=(injected_fault==0?1:2))$fatal(1,"recovery epoch wrong");
    frame_file=$fopen(rgb_path,"w");if(frame_file==0)$fatal;
    for(i=0;i<rgb_bytes;i++)$fdisplay(frame_file,"%02h",rgb_mem[i]);$fclose(frame_file);
    $display("PASS T08 production format recovery fault=%0d epoch=%0d",injected_fault,epoch_id_o);$finish;''')
    perf=(ROOT/'verification/rtl/t06_perf_measurements.svh').read_text()
    perf=perf.replace('if(rst_ni&&frame_done_pulse_o', 'if(rst_ni&&!frame_error_o&&frame_done_pulse_o')
    if recover:perf=perf.replace('if(rst_ni&&!frame_error_o&&frame_done_pulse_o','if(1\'b0&&rst_ni&&!frame_error_o&&frame_done_pulse_o')
    pp=out/'error_measurements.svh';pp.write_text(perf)
    s=s.replace('verification/rtl/t06_perf_measurements.svh',pp.relative_to(ROOT).as_posix())
    tb=out/'tb_t08_format_errors.sv';tb.write_text(s)
    info=read(BASE/'integration_20261107/build/binary.json')
    cmd=[x.replace('tb_t08_integrated','tb_t08_format_errors') for x in info['command']]
    cmd=[str(tb) if x=='verification/rtl/tb_t08_format_errors.sv' else x for x in cmd]
    cmd[cmd.index('--Mdir')+1]=str(work)
    source=production_sources();source[str(tb.relative_to(ROOT))]=sha(tb);source[str(pp.relative_to(ROOT))]=sha(pp)
    run_logged(cmd,out/'build.log')
    rows=[]
    old=read(BASE/'integration_20261107/real/bonsai/m0_limited_f1/run.command.json')
    for fault in range(5):
        d=out/f'fault{fault}';d.mkdir(exist_ok=True)
        run=[x for x in old if x!='+MUTATE_FORMAT'];run[0]=str(work/'simulation')
        for i,x in enumerate(run):
            if x.startswith(('+FRAME=','+RGB=','+SORTED_TRACE=')):
                key=x.split('=',1)[0];run[i]=key+'='+str(d/('state.memh' if key=='+FRAME' else 'rgb.memh' if key=='+RGB' else 'sorted.txt'))
        run+=['+FAULT='+str(fault)]
        execution=run_logged(run,d/'run.log')
        assert f'PASS T08 production format {"recovery" if recover else "error"} fault={fault}' in (d/'run.log').read_text()
        if recover:
            raw=bytes(int(x,16) for x in (d/'rgb.memh').read_text().split())
            assert raw==(BASE/'integration_20261107/real/bonsai/m0_limited_f1/frame.rgb').read_bytes()
            (d/'frame.rgb').write_bytes(raw)
        rows.append(dict(fault=fault,status='PASS',execution=execution));print('PASS production format error',fault,flush=True)
    assert all(sha(ROOT/f)==h for f,h in source.items())
    save(out/'report.json',dict(status='PASS_ERROR_THEN_FRESH_REAL_FRAME' if recover else 'PASS_ERROR_COMPLETION_DRAIN_CLEAR',results=rows,source_sha256=source,
        binary_sha256=sha(work/'simulation'),early_advance=early_advance,signed_off=False,
        scope='Nonempty Bonsai 512 input, unsupported command and four malformed header cases. Recovery option checks fresh-frame epoch and exact RGB DMA. Continuation mismatch remains a separate test.'))

if __name__=='__main__':main()
