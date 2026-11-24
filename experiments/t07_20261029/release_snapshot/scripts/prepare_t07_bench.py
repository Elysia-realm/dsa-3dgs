"""Create a versioned T07 bench from the frozen production RGB-DMA harness."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t07_common import BASE,save,sha

def main():
    repeat='--repeat' in sys.argv
    oldname='tb_t06_release_repeat' if repeat else 'tb_t06_rgb_workload'
    newname='tb_t07_repeat' if repeat else 'tb_t07_workload'
    original=ROOT/f'verification/rtl/{oldname}.sv'
    target=ROOT/f'verification/rtl/{newname}.sv'
    s=original.read_text().replace(oldname,newname)
    pos=s.index('`ifndef TB_RGB_READ_BURST')
    prefix='''`ifndef TB_PIXEL_TERMINATION_SKIP
`define TB_PIXEL_TERMINATION_SKIP 0
`endif
  longint unsigned t07_accepted=0,t07_issued=0,t07_skipped=0,t07_updates=0,t07_full_blocks=0;
  always @(posedge clk_i)if(rst_ni)begin
    if(dut.u_frame.u_render.u_render.u_raster.u_raster.task_valid_i&&dut.u_frame.u_render.u_render.u_raster.u_raster.task_ready_o)begin
      t07_accepted<=t07_accepted+1;
      if(`TB_PIXEL_TERMINATION_SKIP&&
        (dut.u_frame.u_render.u_render.u_raster.u_raster.color_r_q12_i>4096||
         dut.u_frame.u_render.u_render.u_raster.u_raster.color_g_q12_i>4096||
         dut.u_frame.u_render.u_render.u_raster.u_raster.color_b_q12_i>4096))
        $fatal(1,"T07 termination color bound violated");
    end
    if(dut.u_frame.u_render.u_render.u_raster.u_raster.filtered_valid&&dut.u_frame.u_render.u_render.u_raster.u_raster.filtered_ready)t07_issued<=t07_issued+1;
    if(dut.u_frame.u_render.u_render.u_raster.u_raster.skipped_terminated_pulse_o)t07_skipped<=t07_skipped+1;
    if(dut.u_frame.u_render.u_render.u_raster.u_raster.new_terminated_mask!=0)t07_updates<=t07_updates+1;
    if(dut.u_frame.u_render.u_render.u_raster.u_raster.block_terminated_pulse_o)t07_full_blocks<=t07_full_blocks+1;
  end
'''
    s=s[:pos]+prefix+s[pos:]
    needle='.ENABLE_ALPHA_ZERO_SKIP(`TB_ENABLE_ALPHA_ZERO_SKIP)'
    assert s.count(needle)==1
    s=s.replace(needle,'.ENABLE_PIXEL_TERMINATION_SKIP(`TB_PIXEL_TERMINATION_SKIP),'+needle)
    needle='if(state_in_mode)$readmemh(state_in_path,state_mem,0,workload_width*workload_height-1);'
    assert needle in s
    s=s.replace(needle,'if(state_in_mode&&`TB_PIXEL_TERMINATION_SKIP)$fatal(1,"T07 candidate does not accept TB-injected termination state; use real production frames");\n    '+needle)
    needle=f'$display("PASS: {newname}");'
    assert needle in s
    s=s.replace(needle,'''if(t07_accepted!=t07_issued+t07_skipped)$fatal(1,"T07 task accounting not drained");
    $display("REAL_T07_TERMINATION enabled=%0d accepted=%0d alpha_issued=%0d skipped=%0d updates=%0d full_blocks=%0d",
      `TB_PIXEL_TERMINATION_SKIP,t07_accepted,t07_issued,t07_skipped,t07_updates,t07_full_blocks);
    '''+needle)
    target.write_text(s)
    save(BASE/('repeat_bench_derivation.json' if repeat else 'bench_derivation.json'),dict(original=str(original),original_sha256=sha(original),
      target=str(target),target_sha256=sha(target),changes=['module name','explicit candidate parameter',
      'actual path and numerical-bound counters/assertions','reject legacy testbench state injection on candidate'],
      dma_input_output_and_memory_model_changed=False))
    print(target)
if __name__=='__main__':main()
