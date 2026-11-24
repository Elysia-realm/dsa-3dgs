#!/usr/bin/env python3
"""Resume pre-2026-10-03 runs with a mapped datapath but an inferred LUT ROM.

Normal new runs use run_t01_synthesis.py, which maps ROMs before ABC. This
recovery preserves the expensive already-mapped logic and maps only leftovers.
Original artifacts remain under *_before_rom.* and rom_mapping.log records
the recovery. Re-run the normal runner with --report-only afterwards.
"""
import argparse
from pathlib import Path
import shutil

from run_t01_synthesis import TOP, quote, run_yosys

p = argparse.ArgumentParser()
p.add_argument("--run-dir", type=Path, required=True)
p.add_argument("--yosys", type=Path, required=True)
p.add_argument("--liberty", type=Path, required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
d = a.run_dir.resolve()
net = d / "gs_accel_system_top_mapped.v"
old = d / "gs_accel_system_top_before_rom.v"
if old.exists():
    p.error("recovery already attempted; inspect saved artifacts before rerunning")
shutil.copy2(net, old)
shutil.copy2(d / "mapped_stat.json", d / "mapped_stat_before_rom.json")
script = d / "rom_mapping.ys"
script.write_text("\n".join([
    f"read_liberty -lib {quote(a.liberty)}",
    f"read_verilog -sv {quote(root / 'asic/stubs/image_state_cache_backend_blackbox.sv')}",
    f"read_verilog {quote(old)}",
    "proc", "memory_map", "techmap", "opt -fast",
    f"abc -script {quote(d / 'abc_fast.script')} -liberty {quote(a.liberty)} -constr {quote(d / 'abc.constr')} -D 5000",
    "clean", "check",
    f"tee -o {quote(d / 'mapped_stat.json')} stat -json -liberty {quote(a.liberty)} -top {TOP} -hierarchy",
    f"write_verilog -noattr -noexpr -nodec {quote(net)}",
]) + "\n", encoding="ascii")
code, seconds = run_yosys(a.yosys, script, d / "rom_mapping.log", root)
print(f"ROM recovery exit={code}, seconds={seconds:.2f}, log={d / 'rom_mapping.log'}")
raise SystemExit(code)
