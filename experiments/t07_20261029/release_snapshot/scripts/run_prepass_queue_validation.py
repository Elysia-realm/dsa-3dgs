"""Reproducible context-depth ablation; simulation evidence, not PPA/SVA signoff."""
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

from scripts.run_shared_pe_validation import parse_record, sha256


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--iverilog-root", type=Path, default=Path(r"D:\IcarusVerilog\iverilog"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    sources = ["rtl/common/rv_reg_slice.sv", "rtl/control/shared_reconfigurable_pe_slice.sv",
               "rtl/sort/gaussian_depth_prepass_core.sv", "rtl/sort/gaussian_depth_prepass_shared_mac.sv",
               "verification/rtl/tb_gaussian_depth_prepass_shared_mac.sv"]
    records = []
    for contexts in (1, 3, 4):
        binary = output / f"contexts_{contexts}.vvp"
        command = [str(args.iverilog_root / "bin/iverilog.exe"), "-g2012", "-DSYNTHESIS",
                   f"-DTB_PREPASS_CONTEXTS={contexts}", "-s", "tb_gaussian_depth_prepass_shared_mac",
                   "-o", str(binary), *sources]
        compiled = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=60)
        (output / f"contexts_{contexts}_compile.log").write_text(compiled.stdout + compiled.stderr, encoding="utf-8")
        if compiled.returncode:
            raise RuntimeError(f"compile failed: contexts={contexts}")
        simulated = subprocess.run([str(args.iverilog_root / "bin/vvp.exe"), str(binary)],
                                   cwd=root, capture_output=True, text=True, timeout=60)
        log = simulated.stdout + simulated.stderr
        (output / f"contexts_{contexts}.log").write_text(log, encoding="utf-8")
        if simulated.returncode or "PASS: tb_gaussian_depth_prepass_shared_mac" not in log:
            raise RuntimeError(log)
        record = parse_record(log, "PREPASS_QUEUE")
        if record["vectors"] != 324 or record["grants"] != 3 * record["vectors"] or record["stalls"] == 0:
            raise RuntimeError(f"incomplete ablation: {record}")
        records.append(record)
        print(record, flush=True)
    report = {"functional_pass": True, "synthesis_or_ppa_signoff": False, "sva_executed": False,
              "source_sha256": {source: sha256(root / source) for source in sources}, "records": records,
              "burst64_speedup_context4_vs_context1": records[0]["burst64_cycles"] / records[2]["burst64_cycles"]}
    (output / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
