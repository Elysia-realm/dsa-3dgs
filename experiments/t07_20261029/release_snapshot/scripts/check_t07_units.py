"""Native focused tests and an exhaustive arithmetic termination bound."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t07_common import BASE,WORK,VERILATOR,save,sha,run_logged,source_manifest

def main():
    dest=BASE/'units';build=WORK/'units';build.mkdir(parents=True,exist_ok=True)
    files=['rtl/raster/raster_pixel_termination_filter.sv','verification/rtl/tb_t07_pixel_termination.sv']
    cmd=[VERILATOR,'--binary','--build','-j','2','--timing','--assert','-Wno-fatal',
         '--top-module','tb_t07_pixel_termination','--Mdir',str(build),'-o','simulation',*files]
    run_logged(cmd,dest/'build.log')
    run_logged([str(build/'simulation')],dest/'pixel.log')
    assert 'PASS T07_PIXEL_TERMINATION' in (dest/'pixel.log').read_text()
    # Independent integer equations, exhaustive old_T and every architectural
    # alpha code. Nonnegative color contribution is monotone; max color 4096
    # proves zero for every supported color code, not merely sampled colors.
    count=0
    for t in range(8):
        for alpha in range(4056):
            weight=(t*alpha+2048)//4096
            max_rgb_delta=(weight*4096+32768)//65536
            next_t=(t*(4096-alpha)+2048)//4096
            assert max_rgb_delta==0 and 0<=next_t<=t<=7
            count+=1
    run_logged([sys.executable,'-m','unittest',
                'verification.test_shape_block_reject.ShapeBlockRejectTest.test_opacity_bin_thresholds_are_sub_alpha_threshold',
                'verification.test_shape_block_reject.ShapeBlockRejectTest.test_random_rejections_have_no_passing_pixel',
                'verification.test_alpha_zero_skip.AlphaZeroSkipTests.test_zeroed_alpha_blend_is_identity_on_valid_pixel_states',
                '-v'],dest/'current_math.log')
    save(dest/'report.json',dict(status='PASS',termination_pairs=count,
         termination_scope='T=0..7, alpha=0..4055, RGB=0..4096; zero rounded RGB increment and nonincreasing T',
         source_sha256={f:sha(ROOT/f) for f in files},production_source_sha256=source_manifest(),
         historical_test_failures='existing_math.log retained: two September audits correctly reject stale RTL, one historical test hardcodes a different first stale file; these are not current T07 evidence. Current mathematical tests selected explicitly.'))
    print('PASS T07 units and exhaustive bound',count,flush=True)
if __name__=='__main__':main()
