"""Merge current-source DMA chunks into a new immutable baseline matrix."""
from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

from scripts.run_shared_pe_validation import sha256


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("reports", nargs="+", type=Path)
    parser.add_argument("--workloads", nargs="+", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    reports = [(p.resolve(), json.loads(p.read_text(encoding="utf-8"))) for p in args.reports]
    first = reports[0][1]
    for _, report in reports:
        if not report["functional_pass"]:
            raise ValueError("incomplete DMA chunk")
        for key in ("defines", "variants", "profiles", "source_sha256", "testbench_sha256"):
            if report[key] != first[key]:
                raise ValueError(f"incompatible DMA chunks: {key}")
    for source, digest in first["source_sha256"].items():
        if sha256(root / source) != digest:
            raise ValueError(f"stale source: {source}")
    if sha256(root / "verification/rtl/tb_real_dma_workload.sv") != first["testbench_sha256"]:
        raise ValueError("stale testbench")
    selected = []
    origins = []
    for name in args.workloads:
        matches = [(path, w) for path, report in reports for w in report["workloads"] if w["name"] == name]
        if len(matches) != 1:
            raise ValueError(f"missing/ambiguous workload {name}")
        path, workload = matches[0]
        selected.append(workload)
        origins.append((path, name))
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    for path, name in origins:
        shutil.copytree(path.parent / name, output / name)
    merged = dict(first, workloads=selected)
    merged["merged_chunk_reports"] = [str(p.relative_to(root)) for p, _ in reports]
    full = [r for w in selected for r in w["records"] if r["variant"] == "shared_projection"]
    merged["production_contention_observed"] = any(r["shared_pe"]["competing"] > 0 for r in full)
    merged["performance_pass"] = all(r["gap_percent"] <= 0 for r in full)
    merged["aggregate"] = {"runs": sum(len(w["records"]) for w in selected), "full_shared_runs": len(full),
                           "contended_runs": sum(r["shared_pe"]["competing"] > 0 for r in full),
                           "mean_gap_percent": sum(r["gap_percent"] for r in full)/len(full),
                           "max_gap_percent": max(r["gap_percent"] for r in full)}
    for key in [k for k in merged if k.endswith("_candidate")]:
        variant = merged[key]["variant"]
        rows = [r for w in selected for r in w["records"] if r["variant"] == variant]
        references = {(w["name"], r["mode"], r["profile"]): r for w in selected for r in w["records"] if r["variant"] == "shared_projection"}
        comparisons = []
        for w in selected:
            for r in w["records"]:
                if r["variant"] == variant:
                    before = references[w["name"], r["mode"], r["profile"]]["perf"]["cycles"]
                    after = r["perf"]["cycles"]
                    comparisons.append({"workload": w["name"], "mode": r["mode"], "profile": r["profile"],
                                        "serial_cycles": before, "parallel_cycles": after, "saved_cycles": before-after})
        merged[key] = dict(merged[key], runs=len(rows), contended_runs=sum(r["shared_pe"]["competing"] > 0 for r in rows),
                           improved_vs_serial_runs=sum(c["saved_cycles"] > 0 for c in comparisons),
                           non_regressing_vs_serial_runs=sum(c["saved_cycles"] >= 0 for c in comparisons),
                           performance_vs_bypass_pass=all(r["gap_percent"] <= 0 for r in rows),
                           mean_gap_vs_bypass_percent=sum(r["gap_percent"] for r in rows)/len(rows),
                           max_gap_vs_bypass_percent=max(r["gap_percent"] for r in rows), comparisons=comparisons)
    (output / "report.json").write_text(json.dumps(merged, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(merged["aggregate"], indent=2))


if __name__ == "__main__":
    main()
