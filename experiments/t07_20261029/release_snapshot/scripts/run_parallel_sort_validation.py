"""Deterministic group-stream A/B across bounded capacities; non-PPA evidence."""
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
    sources = ["rtl/control/shared_reconfigurable_pe_slice.sv", "rtl/sort/stable_group_sorter.sv",
               "rtl/sort/stable_group_sorter_shared_compare.sv", "rtl/sort/stable_group_sorter_parallel_shared.sv",
               "verification/rtl/tb_stable_group_sorter_parallel_shared.sv"]
    records = []
    variants = {"serial": (0, 0, 0, 0, 0, 0), "odd_even": (1, 0, 0, 0, 0, 0),
                "fallback_only": (1, 1, 0, 0, 0, 0), "adaptive": (1, 1, 1, 0, 0, 0),
                "phase": (1, 1, 1, 1, 0, 0), "monotonic": (1, 1, 1, 1, 1, 0),
                "stable_runs": (1, 1, 1, 1, 1, 1)}
    for capacity in (1, 2, 3, 8, 16, 32):
        reference_vectors = None
        for variant, (parallel, fallback, forwarding, phase, monotonic, runs) in variants.items():
            tag = f"cap{capacity}_{variant}"
            binary = output / f"{tag}.vvp"
            command = [str(args.iverilog_root / "bin/iverilog.exe"), "-g2012", "-DSYNTHESIS",
                       f"-DTB_SORT_CAPACITY={capacity}", f"-DTB_SORT_PARALLEL={parallel}",
                       f"-DTB_SORT_SERIAL_FALLBACK={fallback}", f"-DTB_SORT_BATCH_FORWARDING={forwarding}",
                       f"-DTB_SORT_PHASE_FORWARDING={phase}",
                       f"-DTB_SORT_MONOTONIC_FASTPATH={monotonic}",
                       f"-DTB_SORT_STABLE_RUN_FASTPATH={runs}",
                       "-s", "tb_stable_group_sorter_parallel_shared", "-o", str(binary), *sources]
            result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=60)
            (output / f"{tag}_compile.log").write_text(result.stdout + result.stderr, encoding="utf-8")
            if result.returncode:
                raise RuntimeError(f"compile failed: {tag}")
            result = subprocess.run([str(args.iverilog_root / "bin/vvp.exe"), str(binary)],
                                    cwd=root, capture_output=True, text=True, timeout=60)
            log = result.stdout + result.stderr
            (output / f"{tag}.log").write_text(log, encoding="utf-8")
            if result.returncode or "PASS: tb_stable_group_sorter_parallel_shared" not in log:
                raise RuntimeError(log)
            record = parse_record(log, "SORT_ABLATION")
            cases = [parse_record(line, "SORT_CASE") for line in log.splitlines() if line.startswith("SORT_CASE ")]
            if len(cases) != record["groups"]:
                raise RuntimeError("per-group latency coverage incomplete")
            if reference_vectors is None:
                reference_vectors = record["vectors"]
            if record["vectors"] != reference_vectors:
                raise RuntimeError("serial/parallel input streams differ")
            records.append({"variant": variant, **record, "cases": cases})
            print(record, flush=True)
    comparisons = []
    for i in range(0, len(records), len(variants)):
        serial, *_, candidate = records[i:i+len(variants)]
        for before, after in zip(serial["cases"], candidate["cases"]):
            for field in ("index", "n", "kind", "budget", "stress"):
                if before[field] != after[field]:
                    raise RuntimeError("per-group experiment axes differ")
            if not before["stress"]:
                comparisons.append({"capacity": serial["capacity"], **after,
                                    "serial_cycles": before["cycles"], "saved_cycles": before["cycles"]-after["cycles"]})
    report = {"functional_pass": True, "synthesis_or_ppa_signoff": False, "sva_executed": False,
              "module_hardware_counters_monitor_pass": True,
              "non_stress_case_comparisons": comparisons,
              "performance_all_non_stress_cases_vs_serial_pass": all(r["saved_cycles"] >= 0 for r in comparisons),
              "scope": "one shared G comparator plus up to three dedicated local comparators",
              "source_sha256": {source: sha256(root / source) for source in sources}, "records": records}
    (output / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
