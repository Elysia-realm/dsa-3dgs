import sys
from pathlib import Path
ROOT=Path('/mnt/d/3DGS');sys.path.insert(0,str(ROOT))
from scripts.t07_common import BASE,save
from asic.scripts.run_t01_wsl_synthesis import run_stage
rows=[]
for name,flow in [('flatten_purge',['proc','flatten -noscopeinfo','opt -purge','wreduce','memory_dff','memory_share','memory_collect','opt_clean -purge']),
                  ('t01_order',['proc','opt_expr','opt_clean','check -assert','opt -nodffe -nosdff','wreduce','memory_dff','memory_share','memory_collect','opt_clean','flatten -noscopeinfo','opt_clean'])]:
    d=BASE/'production_structure/probe'/name
    commands=['read_verilog -sv -DSYNTHESIS -Irtl/raster rtl/common/rv_reg_slice.sv rtl/raster/alpha_block_float_core.sv',
        'hierarchy -check -top alpha_block_float_core',*flow,'check -assert']
    try:r=run_stage('probe',commands,d);status='PASS'
    except AssertionError as e:r=str(e);status='FAIL'
    rows.append(dict(name=name,status=status,result=r));print(name,status,flush=True)
save(BASE/'production_structure/probe/report.json',rows)
