"""T02 linear/binary upper-bound comparison on the existing shared-PE bench."""
from __future__ import annotations
import argparse
import json
import subprocess
from pathlib import Path
from scripts.run_shared_pe_validation import parse_record, sha256

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = a.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    sources = ["rtl/control/shared_reconfigurable_pe_slice.sv", "rtl/sort/stable_group_sorter.sv",
               "rtl/sort/stable_group_sorter_shared_compare.sv", "rtl/sort/stable_group_sorter_parallel_shared.sv",
               "verification/rtl/tb_stable_group_sorter_parallel_shared.sv"]
    records = []
    for cap in (1, 2, 3, 8, 16, 32, 128):
        for binary in (0, 1):
            tag = f"cap{cap}_{'binary' if binary else 'linear'}"
            exe = out / f"{tag}.vvp"
            cmd = [r"D:\IcarusVerilog\iverilog\bin\iverilog.exe", "-g2012", "-DSYNTHESIS",
                   f"-DTB_SORT_CAPACITY={cap}", "-DTB_SORT_PARALLEL=0",
                   f"-DTB_SHARED_SORT_BINARY_SEARCH={binary}", "-s", "tb_stable_group_sorter_parallel_shared",
                   "-o", str(exe), *sources]
            c = subprocess.run(cmd, cwd=root, text=True, capture_output=True, timeout=90)
            (out / f"{tag}_compile.log").write_text(c.stdout+c.stderr)
            if c.returncode: raise RuntimeError(f"compile failed: {tag}")
            c = subprocess.run([r"D:\IcarusVerilog\iverilog\bin\vvp.exe", str(exe)], cwd=root,
                               text=True, capture_output=True, timeout=180)
            log = c.stdout+c.stderr
            (out / f"{tag}.log").write_text(log)
            if c.returncode or "PASS: tb_stable_group_sorter_parallel_shared" not in log:
                raise RuntimeError(log[-3000:])
            cases = [parse_record(line, "SORT_CASE") for line in log.splitlines() if line.startswith("SORT_CASE ")]
            record = dict(variant="binary" if binary else "linear", **parse_record(log, "SORT_ABLATION"), cases=cases)
            records.append(record)
            print(tag, "PASS", record["vectors"], "outputs", flush=True)
    comparisons = []
    for before, after in zip(records[::2], records[1::2]):
        assert before["vectors"] == after["vectors"]
        assert len(before["cases"]) == len(after["cases"])
        for b, c in zip(before["cases"], after["cases"]):
            assert all(b[k] == c[k] for k in ("index", "n", "kind", "budget", "stress"))
            # Random contention is functional stress, not cycle-aligned A/B.
            if not b["stress"]:
                comparisons.append(dict(capacity=before["capacity"], **c, linear_cycles=b["cycles"],
                                        saved_cycles=b["cycles"]-c["cycles"], linear_grants=b["grants"],
                                        saved_grants=b["grants"]-c["grants"]))
    report = dict(functional_pass=True, sva_executed=False, ppa_signed_off=False, records=records,
                  ideal_comparisons=comparisons, total_output_vectors=sum(r["vectors"] for r in records),
                  source_sha256={s: sha256(root/s) for s in sources})
    (out / "report.json").write_text(json.dumps(report, indent=2)+"\n")

if __name__ == "__main__": main()
