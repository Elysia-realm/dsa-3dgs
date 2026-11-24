"""Archive verified T06 measurements; no RTL changes or performance signoff."""
import hashlib,json,re,shutil,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'experiments/t06_20261018'
OUT=BASE/'performance_baseline'
NAMES=['bonsai','counter','room','kitchen','garden']
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1<<20),b''):h.update(b)
    return h.hexdigest()
def parse_log(p):
    text=p.read_text();blocks={}
    for line in text.splitlines():
        if line.startswith('REAL_'):
            blocks[line.split()[0]]={k:int(v) if v.isdecimal() else v for k,v in re.findall(r'(\w+)=([^\s]+)',line)}
    def capture(pattern):
        m=re.search(pattern,text);return float(m[1]) if m else None
    return dict(counters=blocks,simulator_wall_seconds=capture(r'walltime ([\d.]+) s'),
                simulator_cpu_seconds=capture(r'cpu ([\d.]+) s'),
                simulator_threads=capture(r'on (\d+) threads'))
def main():
    audit=read(BASE/'audit.json');assert audit['pending_evidence']==[]
    assert all(r['status']=='PASS' for r in audit['full_model_frames'])
    assert read(BASE/'full_render/report.json')['status']=='PASS'
    rows=[];sources={};artifacts={}
    for n in NAMES:
        d=BASE/'full_render'/n;m=read(d/'manifest.json');paths={};row=dict(scene=n,camera_index=m['camera_index'],
            gaussians=m['gaussians'],visible=m['visible'],full_scene=m['full_scene'],width=m['width'],height=m['height'],
            mode='G',axi_profile='ideal',software_preprocessing=m['software_preprocessing'],input_sha256=m['input_sha256'])
        for role,folder in [('production','production_v2'),('reference','oracle')]:
            p=d/folder;r=read(p/'result.json')
            for f,h in r['source_sha256'].items():assert sha(ROOT/f)==h,f
            sources.update(r['source_sha256']);data=parse_log(p/'run.log')
            data.update(runner_wall_seconds=r['seconds'],command=read(p/'command.json'),log=(p/'run.log').relative_to(ROOT).as_posix())
            row[role]=data
            for name in ['result.json','command.json','run.log','frame.rgb','frame.png']:
                paths[(p/name).relative_to(ROOT).as_posix()]=sha(p/name)
        prod=row['production']['counters'];q=prod['REAL_QSU'];perf=prod['REAL_PERF'];rgb=prod['REAL_RGB'];cycles=perf['cycles']
        assert q['input']==m['visible'] and q['reads']==q['axi_reads'] and q['writes']==q['axi_writes']
        row['derived']={
            'cycles':cycles,'command_accept_to_done_cycles':None,'hypothetical_200MHz_seconds':cycles/2e8,'hypothetical_200MHz_fps':2e8/cycles,
            'measured_hardware_fps':None,'qsu_leaf_average_records':q['input']/q['leaves'],
            'qsu_scratch_read_bytes':q['reads']*16,'qsu_scratch_write_bytes':q['writes']*16,
            'qsu_scratch_read_write_GiB':(q['reads']+q['writes'])*16/2**30,
            'mean_read_bytes_derived':m['gaussians']*16,'attribute_read_bytes_derived':m['visible']*144,
            'camera_read_bytes_derived':224,'state_render_read_bytes_derived':perf['state_reads']*16,
            'state_write_bytes_derived':perf['state_writes']*16,'rgb_state_read_bytes_derived':rgb['reads']*16,
            'rgb_write_bus_bytes_derived':rgb['write_beats']*16,
            'sorted_backpressure_cycle_fraction':prod['REAL_STAGE']['sorted_bp']/cycles,
            'blend_window_full_cycle_fraction':prod['REAL_BACKEND']['blend_full']/cycles,
            'projection_raster_overlap_cycles':prod['REAL_STAGE']['overlap']}
        row['independent_float_rgb8_mae']=next(x['independent_float_rgb8_mae'] for x in audit['full_model_frames'] if x['scene']==n)
        paths[(d/'manifest.json').relative_to(ROOT).as_posix()]=sha(d/'manifest.json')
        row['artifact_sha256']=paths;artifacts.update(paths);rows.append(row)
    report=dict(status='VERIFIED_FUNCTIONAL_BASELINE_NOT_OPTIMIZATION_SIGNOFF',signed_off=False,results=rows,
        timing_boundary='Production REAL_PERF resets at non-continuation batch_start AFTER initial camera DMA, then counts frame_busy_o. Includes mean/QSU/attribute/render/drain/final RGB busy; excludes initial camera fetch/command preparation, host PLY encoding and input file load. Exact command_accept-to-final-done cycles are NOT measured by this counter. Reference continuation accounting is separate and must not be used as a fair end-to-end speedup denominator.',
        caveats=['Busy/stall counters overlap; do not sum as disjoint latency.',
          'Derived DMA byte volumes use accepted beat counts or workload counts asserted by the bench; they are not measured physical LPDDR bandwidth.',
          'Non-RGB read burst counts, physical DDR contention, mapped timing/area/power and native-resolution GT performance are unmeasured.',
          'G/ideal full models at width 128 only; hypothetical 200MHz is not achieved STA or measured silicon frequency.',
          'REAL_WORKLOAD label is a historical constant; use manifest scene/camera and input hashes for identity.',
          'Bottleneck causal ablation and optimization decision remain pending.'],source_sha256=sources,artifact_sha256=artifacts)
    OUT.mkdir(parents=True,exist_ok=True)
    for f,h in sources.items():
        dest=OUT/'source_snapshot'/f;dest.parent.mkdir(parents=True,exist_ok=True)
        if dest.exists():assert sha(dest)==h,'refuse to replace frozen baseline '+f
        else:shutil.copy2(ROOT/f,dest)
    for f,h in artifacts.items():
        dest=OUT/'evidence'/Path(f).relative_to(BASE.relative_to(ROOT));dest.parent.mkdir(parents=True,exist_ok=True)
        if dest.exists():assert sha(dest)==h,'refuse to replace frozen evidence '+f
        else:shutil.copy2(ROOT/f,dest)
    target=OUT/'report.json'
    if target.exists():assert read(target)==report,'refuse to overwrite different baseline'
    else:target.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    for r in rows:
        print(r['scene'],json.dumps(r['derived']), 'wall_s=',r['production']['simulator_wall_seconds'],'reference_wall_s=',r['reference']['simulator_wall_seconds'])
if __name__=='__main__':main()
