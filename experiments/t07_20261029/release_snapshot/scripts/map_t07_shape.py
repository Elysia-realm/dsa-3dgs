"""Area-only mapping of the newly enabled shape predicate in both frozen TT libraries."""
import sys,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t07_common import BASE,read,save,sha
from asic.scripts.run_t01_wsl_synthesis import q,run_stage

def main():
    top='gaussian_shape_block_reject';src=ROOT/f'rtl/raster/{top}.sv';rows=[]
    for pdk,lib,driver,load in [('nangate45',ROOT/'tmp/toolchains/freepdk45_google_954b16e2/Front_End/Liberty/NLDM/NangateOpenCellLibrary_typical.lib','BUF_X4',3.899),
      ('icsprout55',ROOT/'tmp/toolchains/icsprout55/rvt-v1.10.102/liberty/ics55_LLSC_H7CR_typ_tt_1p2_25_nldm.lib','BUFX1H7R',3.539972)]:
        d=BASE/'shape_mapping'/pdk;d.mkdir(parents=True,exist_ok=True)
        constr=d/'abc.constr';constr.write_text(f'set_driving_cell {driver}\nset_load {load}\n')
        commands=[f'read_verilog -sv -DSYNTHESIS {q(src)}',f'synth -top {top} -noabc',
          f'read_liberty -lib {q(lib)}',f'abc -liberty {q(lib)} -constr {q(constr)} -D 5000','clean','check -assert',
          f'tee -o {q(d/"stat.json")} stat -json -liberty {q(lib)}',f'write_verilog -noattr -noexpr -nodec {q(d/"mapped.v")}']
        execution=run_stage('mapping',commands,d);s=read(d/'stat.json');design=s.get('design') or s['modules']['\\'+top]
        cells=set(re.findall(r'cell\s*\(\s*([^\s)]+)',lib.read_text()));assert not (set(design['num_cells_by_type'])-cells)
        rows.append(dict(pdk=pdk,area_mm2=design['area']/1e6,cells=design['num_cells'],library_sha256=sha(lib),
           source_sha256=sha(src),netlist_sha256=sha(d/'mapped.v'),execution=execution,whole_chip_ppa_pass=False,
           scope='One combinational predicate instance, area-only; ABC timing is not integrated top-level STA.'))
    save(BASE/'shape_mapping/report.json',dict(status='PASS_AREA_MAPPING',results=rows));print(rows)
if __name__=='__main__':main()
