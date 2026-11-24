"""Apply the bounded T07 parameter plumbing and a separate production testbench."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t07_common import initialize,BASE,read,save,sha

def main():
    initialize()
    files=['rtl/gs_accel_system_top.sv','rtl/gaussian_frame_render_pipeline.sv',
           'rtl/gaussian_sorted_render_pipeline.sv','rtl/gaussian_ordered_render_frontend.sv',
           'rtl/raster/ordered_block_raster_frontend.sv','rtl/raster/raster_pair_shell.sv']
    for name in files:
        p=ROOT/name;s=p.read_text()
        if 'parameter bit ENABLE_PIXEL_TERMINATION_SKIP' in s:continue
        needle='parameter bit ENABLE_ALPHA_ZERO_SKIP'
        assert s.count(needle)==1,name
        s=s.replace(needle,"parameter bit ENABLE_PIXEL_TERMINATION_SKIP=1'b0,\n    "+needle)
        needle='.ENABLE_ALPHA_ZERO_SKIP(ENABLE_ALPHA_ZERO_SKIP)'
        if name!='rtl/raster/raster_pair_shell.sv':
            assert s.count(needle)==1,name
            s=s.replace(needle,'.ENABLE_PIXEL_TERMINATION_SKIP(ENABLE_PIXEL_TERMINATION_SKIP),\n      '+needle)
        p.write_text(s)
    p=ROOT/'verification/rtl/system_top_sources.f';s=p.read_text()
    name='rtl/raster/raster_pixel_termination_filter.sv'
    if name not in s:s=s.replace('rtl/raster/raster_pair_shell.sv',name+'\nrtl/raster/raster_pair_shell.sv');p.write_text(s)
    state=read(ROOT/'verification/implementation_status.json')
    state.update(t07_status='IN_PROGRESS',t07_signed_off=False,t07_started_at='2026-10-29',
       t07_acceptance_plan='docs/T07验收与有界优化计划_2026-10-29.md',
       t07_latest_log='docs/开发日志_2026-10-29_T07逐像素终止与形状验收.md',
       t07_evidence_root='experiments/t07_20261029',
       t01_last_mapping_source_matches_current_rtl=False,
       t01_evidence_integrity_scope='Immutable t06_h_v1/T01 source_snapshot; T07 changes require separate validation. T01 initial-feedback signoff retained.')
    save(ROOT/'verification/implementation_status.json',state)
    print('T07 started; baseline snapshot retained')
if __name__=='__main__':main()
