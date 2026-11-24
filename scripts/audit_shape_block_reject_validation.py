"""Audit conservative block rejection on measured n32 DMA scenes; not PPA signoff."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from statistics import mean

from scripts.compare_shared_pe_validation import compare
from scripts.run_shared_pe_validation import sha256


def audit(root: Path, bundle: Path) -> dict:
    report_path = bundle / "dma_six_scene_release/report.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if not report["functional_pass"]:
        raise ValueError("DMA matrix did not pass")
    for source, digest in report["source_sha256"].items():
        if sha256(root / source) != digest:
            raise ValueError(f"stale source evidence: {source}")
    if sha256(root / "verification/rtl/tb_real_dma_workload.sv") != report["testbench_sha256"]:
        raise ValueError("stale DMA testbench evidence")

    comparisons = []
    raw_mismatches = 0
    for workload in report["workloads"]:
        indexed = {(r["variant"], r["mode"], r["profile"]): r for r in workload["records"]}
        for mode in ("G", "P", "R", "E"):
            for profile in ("ideal", "limited"):
                bypass = indexed[("bypass", mode, profile)]
                shared = indexed[("shared_projection", mode, profile)]
                shape = indexed[("shape_block_reject", mode, profile)]
                if not (bypass["frame_sha256"] == shared["frame_sha256"] == shape["frame_sha256"]):
                    raise ValueError(f"rendered-image mismatch: {workload['name']}/{mode}/{profile}")
                if shape["shape"]["enabled"] != 1 or shared["shape"]["enabled"] != 0:
                    raise ValueError("shape control mismatch")
                if shape["perf"]["cycles"] >= shared["perf"]["cycles"]:
                    raise ValueError("candidate did not improve shared baseline")
                for field in ("commits", "state_reads", "state_writes"):
                    if shape["perf"][field] > shared["perf"][field]:
                        raise ValueError(f"candidate increased {field}")
                raw_mismatches += shape["raw_frame_sha256"] != shared["raw_frame_sha256"]
                comparisons.append({
                    "scene": workload["name"], "mode": mode, "profile": profile,
                    "saved_vs_shared_cycles": shared["perf"]["cycles"] - shape["perf"]["cycles"],
                    "saved_vs_bypass_cycles": bypass["perf"]["cycles"] - shape["perf"]["cycles"],
                    "rejected_blocks": shape["shape"]["rejected_blocks"],
                    "removed_commits": shared["perf"]["commits"] - shape["perf"]["commits"],
                    "removed_reads": shared["perf"]["state_reads"] - shape["perf"]["state_reads"],
                    "removed_writes": shared["perf"]["state_writes"] - shape["perf"]["state_writes"],
                    "gap_vs_bypass_percent": shape["gap_percent"],
                })
    if len(comparisons) != 48 or sum(r["rejected_blocks"] for r in comparisons) == 0:
        raise ValueError("expected candidate coverage is incomplete")
    old = root / "experiments/shared_pe/validation_20260915_streaming_prepass_n32"
    primary_names = {"bonsai_cammid_n32_d64", "train_cammid_n32_d64", "garden_cammid_n32_d64"}
    expanded_names = {"truck_cammid_n32_d64", "room_cammid_n32_d64", "counter_cammid_n32_d64"}
    primary = compare(old / "dma_matrix_release/report.json", report_path,
                      {"bypass", "shared_projection"}, primary_names)
    expanded = compare(old / "dma_expanded_release/report.json", report_path,
                       {"bypass", "shared_projection"}, expanded_names)
    for label, baseline in (("primary", primary), ("expanded", expanded)):
        if len(baseline["records"]) != 48 or any(row["saved_cycles"] != 0 for row in baseline["records"]):
            raise ValueError(f"default-off {label} baseline changed")
    return {
        "source_current": True, "functional_pass": True,
        "runs": len(comparisons), "scenes": len(report["workloads"]),
        "improved_vs_shared_runs": sum(r["saved_vs_shared_cycles"] > 0 for r in comparisons),
        "mean_saved_vs_shared_cycles": mean(r["saved_vs_shared_cycles"] for r in comparisons),
        "min_saved_vs_shared_cycles": min(r["saved_vs_shared_cycles"] for r in comparisons),
        "max_saved_vs_shared_cycles": max(r["saved_vs_shared_cycles"] for r in comparisons),
        "faster_than_bypass_runs": sum(r["saved_vs_bypass_cycles"] > 0 for r in comparisons),
        "non_regressing_vs_bypass_runs": sum(r["saved_vs_bypass_cycles"] >= 0 for r in comparisons),
        "mean_gap_vs_bypass_percent": mean(r["gap_vs_bypass_percent"] for r in comparisons),
        "max_gap_vs_bypass_percent": max(r["gap_vs_bypass_percent"] for r in comparisons),
        "rejected_blocks": sum(r["rejected_blocks"] for r in comparisons),
        "removed_commits": sum(r["removed_commits"] for r in comparisons),
        "removed_reads": sum(r["removed_reads"] for r in comparisons),
        "removed_writes": sum(r["removed_writes"] for r in comparisons),
        "raw_frame_mismatch_runs": raw_mismatches,
        "unchanged_default_off_baseline_runs": 96,
        "default_enabled": False, "area_timing_energy_signed_off": False,
        "scope": "six n32 scenes, G/P/R/E, ideal/limited AXI; epoch-aware RGB/T equality, not raw frame-slot equality or PPA",
        "comparisons": comparisons,
        "previous_primary_baseline": primary,
        "previous_expanded_baseline": expanded,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    result = audit(root, args.bundle.resolve())
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items()
                      if k not in ("comparisons", "previous_primary_baseline", "previous_expanded_baseline")},
                     indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
