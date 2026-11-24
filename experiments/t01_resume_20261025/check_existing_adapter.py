import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from asic.scripts.t01_sta_netlist_adapter import adapt
p=ROOT/'experiments/t01_resume_20261025/mapping_entry_smoke/nangate45/shared_pe.v'
lib=ROOT/'tmp/toolchains/freepdk45_google_954b16e2/Front_End/Liberty/NLDM/NangateOpenCellLibrary_typical.lib'
print(adapt(p,lib,'shared_reconfigurable_pe_slice'))
