"""Check actual raster-shell pruning and generic storage at production parameters."""
import sys,argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t07_common import BASE,WORK,read,save,sha,source_manifest
from asic.scripts.run_t01_wsl_synthesis import q,run_stage

def number(s):return int(s,2) if isinstance(s,str) else int(s)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--pixel',type=int,choices=[0,1]);parser.add_argument('--combine',action='store_true');args=parser.parse_args()
    rows=[];sources=source_manifest();top='raster_pair_shell'
    for enabled in ([args.pixel] if args.pixel is not None else [0,1]):
        d=BASE/'production_structure'/f'pixel{enabled}';w=WORK/'production_structure'/f'pixel{enabled}';w.mkdir(parents=True,exist_ok=True)
        if args.combine:
            r=read(d/'result.json');assert r['source_sha256']==sources;assert sha(r['coarse_json'])==r['coarse_sha256'];rows.append(r);continue
        filelist=[ROOT/x.strip() for x in (ROOT/'verification/rtl/system_top_sources.f').read_text().splitlines() if x.strip()]
        params=dict(LANES=4,TASK_W=32,BLOCK_W=32,GID_W=32,EPOCH_W=16,PIXEL_W=32,STATE_ENTRIES=4096,
          STATE_WINDOW_ENTRIES=4,STATE_MSHR_COUNT=4,ENABLE_RESPONSE_BLEND_BYPASS=1,ENABLE_BLEND_COMMIT_BYPASS=1,
          USE_STATE_CACHE_BACKEND=1,USE_SHARED_RASTER_PE=1,ENABLE_ALPHA_ZERO_SKIP=1,ENABLE_PIXEL_TERMINATION_SKIP=enabled)
        commands=['read_verilog -sv -DSYNTHESIS -Irtl/raster '+' '.join(q(f) for f in filelist),
          'chparam '+' '.join(f'-set {k} {v}' for k,v in params.items())+' '+top,
          'hierarchy -check -top '+top,'proc','opt_expr','opt_clean','check -assert',
          'opt -nodffe -nosdff','wreduce','memory_dff','memory_share','memory_collect','opt_clean',
          'flatten -noscopeinfo','opt_clean','check -assert',
          'write_json '+q(w/'coarse.json')]
        execution=run_stage('coarse',commands,d)
        mod=read(w/'coarse.json')['modules'][top];memories=[];ff_bits=0;term_ff_bits=0
        for name,c in mod['cells'].items():
            if c['type']=='$mem_v2':
                p=c['parameters'];row=dict(name=name,width=number(p['WIDTH']),depth=number(p['SIZE']),
                  read_ports=number(p['RD_PORTS']),write_ports=number(p['WR_PORTS']))
                row['bits']=row['width']*row['depth'];memories.append(row)
            elif 'dff' in c['type'].lower():
                ff_bits+=number(c['parameters']['WIDTH'])
                if 'termination' in name:term_ff_bits+=number(c['parameters']['WIDTH'])
        names=list(mod['cells'])
        if enabled:
            assert not any('u_termination_filter.' in name or 'u_pixel_termination_mask.' in name for name in names)
            assert any('g_pixel_termination.u_filter' in name for name in names)
        else:assert not any('g_pixel_termination.u_filter' in name for name in names)
        rows.append(dict(enabled=enabled,status='PASS',parameters=params,generic_ff_bits=ff_bits,
          termination_named_ff_bits=term_ff_bits,memories=memories,generic_memory_bits=sum(m['bits'] for m in memories),
          coarse_json=str(w/'coarse.json'),coarse_sha256=sha(w/'coarse.json'),execution=execution,source_sha256=sources))
        save(d/'result.json',rows[-1])
        print('PASS actual raster structure',enabled,ff_bits,sum(m['bits'] for m in memories),flush=True)
    assert source_manifest()==sources
    if args.pixel is None:
        save(BASE/'production_structure/report.json',dict(status='PASS',results=rows,
          scope='Actual production raster shell: disabled legacy structures eliminated on candidate branch; generic state/memory only, not macro or full-chip 300KB signoff.'))
if __name__=='__main__':main()
