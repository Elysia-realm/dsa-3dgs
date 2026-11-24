"""Current-profile T01 synthesis: original RTL, including all cache control/storage.

Register-expanded storage is a documented first-feedback implementation, not a
final SRAM macro or PPA signoff. No cell or module is blackboxed here.
"""
import argparse,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,WORK,PROFILE,read,save,sha,frozen,initialize,run_logged
YOSYS=Path.home()/'eda/opt/oss-cad-suite-20260706/oss-cad-suite/bin/yosys'
TOP='gs_accel_system_top'
def q(p):return '"'+str(p)+'"'
def run_stage(name,commands,folder):
    folder.mkdir(parents=True,exist_ok=True);script=folder/f'{name}.ys'
    script.write_text('\n'.join(commands)+'\n')
    return run_logged([str(YOSYS),'-s',str(script)],folder/f'{name}.log')
def main():
    p=argparse.ArgumentParser();p.add_argument('stage',choices=['coarse','premap','map']);p.add_argument('--alpha',type=int,choices=[0,1],default=1);p.add_argument('--pdk',choices=['nangate45','icsprout55'],default='nangate45');p.add_argument('--liberty',type=Path,help='Relocate the frozen library without changing its contents');a=p.parse_args()
    initialize();sources=frozen();cfg=read(PROFILE)['parameters'].copy();cfg['ENABLE_ALPHA_ZERO_SKIP']=a.alpha
    out=BASE/'synthesis'/f'alpha{a.alpha}';work=WORK/'synthesis'/f'alpha{a.alpha}';work.mkdir(parents=True,exist_ok=True)
    coarse=work/'coarse.il';premap=work/'premap.il'
    provenance=dict(source_sha256=sources,parameters=cfg,yosys_sha256=sha(YOSYS),storage='original RTL; arrays expanded to registers for first feedback',blackboxed_modules=[])
    if a.stage=='coarse':
        files=[ROOT/f.strip() for f in (ROOT/'verification/rtl/system_top_sources.f').read_text().splitlines() if f.strip()]
        cmds=['read_verilog -sv -DSYNTHESIS -I'+str(ROOT/'rtl/raster')+' '+' '.join(q(f) for f in files),
          'chparam '+' '.join(f'-set {k} {v}' for k,v in cfg.items())+' '+TOP,
          'hierarchy -check -top '+TOP,'proc','opt_expr','opt_clean','check -assert',
          'opt -nodffe -nosdff','wreduce','memory_dff','memory_share','memory_collect','opt_clean',
          'check -assert','tee -o '+q(out/'coarse_stat.json')+' stat -json -top '+TOP,
          'write_rtlil '+q(coarse)]
        result=run_stage('coarse',cmds,out);save(out/'coarse.json',dict(**provenance,artifact=str(coarse),artifact_sha256=sha(coarse),execution=result))
    elif a.stage=='premap':
        prev=read(out/'coarse.json');assert prev['parameters']==cfg and sha(coarse)==prev['artifact_sha256']
        from asic.scripts.t01_memory_padding import define_padding
        mapped=work/'memory_mapped.il';defined=work/'memory_padding_defined.il'
        run_stage('memory_expansion',['read_rtlil '+q(coarse),'memory_map','write_rtlil '+q(mapped)],out)
        define_padding(mapped,defined,out/'padding_definition.json')
        cmds=['read_rtlil '+q(defined),'opt -fast','techmap','opt -fast',
          'write_rtlil '+q(work/'premap_unchecked.il'),'check -assert',
          'tee -o '+q(out/'premap_stat.json')+' stat -json -top '+TOP,'write_rtlil '+q(premap)]
        result=run_stage('premap',cmds,out);save(out/'premap.json',dict(**provenance,artifact=str(premap),artifact_sha256=sha(premap),execution=result))
    else:
        prev=read(out/'premap.json');assert prev['parameters']==cfg and sha(premap)==prev['artifact_sha256']
        lib=ROOT/('tmp/toolchains/freepdk45_google_954b16e2/Front_End/Liberty/NLDM/NangateOpenCellLibrary_typical.lib' if a.pdk=='nangate45' else 'tmp/toolchains/icsprout55/rvt-v1.10.102/liberty/ics55_LLSC_H7CR_typ_tt_1p2_25_nldm.lib')
        if a.liberty:
            relocated=a.liberty.resolve();assert sha(relocated)==sha(lib),'This recovery run freezes the library version; only path relocation is allowed'
            lib=relocated
        lib_hash=sha(lib)
        dest=out/a.pdk;dest.mkdir(parents=True,exist_ok=True);constraint=dest/'abc.constr';abc=dest/'abc.script'
        driver,load=('BUF_X4',3.899) if a.pdk=='nangate45' else ('BUFX1H7R',3.539972)
        constraint.write_text(f'set_driving_cell {driver}\nset_load {load}\n')
        abc.write_text('strash\ndc2\nmap\ncleanup\nbuffer\nupsize -D 5000\ndnsize -D 5000\nstime -p\n')
        net=dest/'gs_accel_system_top_mapped.v'
        cmds=['read_rtlil '+q(premap),'read_liberty -lib '+q(lib),'dfflibmap -liberty '+q(lib),
          f'abc -script {q(abc)} -liberty {q(lib)} -constr {q(constraint)} -D 5000',
          'clean','check -assert','tee -o '+q(dest/'mapped_stat.json')+' stat -json -liberty '+q(lib)+' -top '+TOP,
          'write_verilog -noattr -noexpr -nodec '+q(net)]
        result=run_stage('mapping',cmds,dest);assert sha(lib)==lib_hash
        save(dest/'mapping.json',dict(**provenance,liberty=str(lib),liberty_sha256=lib_hash,netlist_sha256=sha(net),execution=result))
    frozen()
if __name__=='__main__':main()
