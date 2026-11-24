"""Audit frozen A full-model outputs and quantify independent throughput bounds."""
import hashlib,json,re,sys
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.run_t06_perf_optimization import SCENES,read,save
from scripts.collect_t06_performance_baseline import sha,parse_log
BASE=ROOT/'experiments/t06_full_alpha_20261020'
SNAP=ROOT/'experiments/t06_alpha_20261020/source_snapshot'
def main():
    assert read(BASE/'status.json')['status']=='COMPLETE_REVIEW_REQUIRED';rows=[]
    budget=200_000_000/30
    for n in SCENES:
        d=BASE/n;m=read(d/'manifest.json');r=read(d/'A/result.json');o=read(d/'oracle/result.json')
        for entry in [r,o]:
            for f,h in entry['source_sha256'].items():assert sha((SNAP if entry is r else ROOT/'experiments/t06_perf_20261018/selection_snapshot')/f)==h
        for f,h in m['input_sha256'].items():assert sha(d/f)==h
        assert sha(d/'expected_sorted.txt')==m['oracle_sha256']
        raw=(d/'A/frame.rgb').read_bytes()
        assert sha(d/'A/frame.rgb')==r['rgb_sha256']
        assert raw==(d/'oracle/frame.rgb').read_bytes()==Image.open(d/'A/frame.png').tobytes()
        assert raw==bytes(int(x,16) for x in (d/'A/rgb.memh').read_text().split())
        assert (d/'A/sorted.txt').read_bytes()==(d/'expected_sorted.txt').read_bytes()
        state=[int(x,16) for x in (d/'A/state.memh').read_text().split()]
        w,h=m['width'],m['height'];stride=(w*3+15)&~15;expected=bytearray(stride*h)
        for i,s in enumerate(state):
            if (s>>55)&65535!=1:continue
            y,x=divmod(i,w)
            for c in range(3):expected[y*stride+3*x+c]=min(255,(((s>>(13*c))&8191)*255+2048)//4096)
        assert raw==expected
        perf=parse_log(d/'A/run.log');blocks=perf['counters'];t=blocks['REAL_END_TO_END'];p=blocks['REAL_SHARED_PE'];q=blocks['REAL_QSU'];dma=blocks['REAL_DMA_COUNTS']
        assert t['command_count']==1 and t['window']==4 and t['mshr']==4 and t['response_bypass']==t['commit_bypass']==1
        assert blocks['REAL_ALPHA_SKIP']['enabled']==1
        assert q['input']==m['visible'] and q['reads']==q['axi_reads'] and q['writes']==q['axi_writes']
        assert 'error=00000000' in (d/'A/run.log').read_text()
        bounds=dict(shared_PE_services=p['G']+p['P']+p['R'],P_only_services=p['P'],
          qsu_read_beats=dma['qsu_read_beats'],attribute_read_beats=dma['attribute_beats'],
          depth_prepass_min_MAC_services=3*m['gaussians'])
        float_path=(ROOT/'experiments/t06_20261018/float_full'/n/'float_floor_0.30078125_jac_clamp.png')
        if n in ['train','truck']:float_path=ROOT/'experiments/t06_full_f_20261019/float_refs'/n/'float_floor_0.30078125_jac_clamp.png'
        mae=None
        if float_path.exists():
            a=np.asarray(Image.open(d/'A/frame.png'),dtype=float);b=np.asarray(Image.open(float_path),dtype=float)
            assert a.shape==b.shape;mae=float(np.abs(a-b).mean());assert mae<=5,(n,mae)
        rows.append(dict(scene=n,camera_index=m['camera_index'],gaussians=m['gaussians'],visible=m['visible'],width=w,height=h,
          command_cycles=t['command_cycles'],hypothetical_200MHz_fps=200_000_000/t['command_cycles'],hardware_30fps_verified=False,
          lower_bound_cycles_at_one_service_per_cycle=bounds,
          minimum_required_rate_for_30fps_at_200MHz={k:v/budget for k,v in bounds.items()},
          production_measurements=perf,reference_measurements=parse_log(d/'oracle/run.log'),
          source_sha256=r['source_sha256'],input_sha256=m['input_sha256'],rgb_sha256=r['rgb_sha256'],independent_float_mae=mae,
          evidence_sha256={f:sha(d/f) for f in ['A/run.log','A/result.json','A/command.json','oracle/result.json','manifest.json']}))
    report=dict(status='PASS_FUNCTIONAL_PAIR_WITH_EXPLICIT_FLOAT_PENDING',signed_off=False,results=rows,
      pending_float=[x['scene'] for x in rows if x['independent_float_mae'] is None],
      inference_scope='Service-count lower bounds are separate bottlenecks; do not add across overlapping resources. P-only remains even if R is eliminated. Current single-PE and 128-bit per-port rates cannot meet these same-workload budgets at 200MHz.',
      limitations=['128-wide, G/ideal only; not final resolution or GT signoff','200MHz is hypothetical, no achieved STA/area/power proof','Full-stage architecture changes still require before/after real validation'])
    save(BASE/'functional_performance_audit.json',report)
    for x in rows:print(x['scene'],x['command_cycles'],x['minimum_required_rate_for_30fps_at_200MHz'])
if __name__=='__main__':main()
