"""Reproducible round audit. Measured scope only, never PPA/optimality signoff."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from scripts.run_shared_pe_validation import sha256
from scripts.compare_shared_pe_validation import compare


def audit(root: Path, bundle: Path, dma_subdir: str = "dma_matrix_final") -> dict:
    module = json.loads((bundle / "sorter_ablation_checked/report.json").read_text(encoding="utf-8"))
    dma_path = bundle / dma_subdir / "report.json"
    dma = json.loads(dma_path.read_text(encoding="utf-8"))
    if not module["functional_pass"] or not dma["functional_pass"]:
        raise ValueError("incomplete/failed functional evidence")
    for report in (module, dma):
        for source, digest in report["source_sha256"].items():
            if sha256(root / source) != digest:
                raise ValueError(f"stale source evidence: {source}")
    if sha256(root / "verification/rtl/tb_real_dma_workload.sv") != dma["testbench_sha256"]:
        raise ValueError("stale DMA testbench evidence")
    cases = module["non_stress_case_comparisons"]
    candidate = dma["stable_run_sort_candidate"]
    collect_before = collect_after = fast = latency_improved = 0
    for workload in dma["workloads"]:
        before = {(r["mode"], r["profile"]): r for r in workload["records"] if r["variant"] == "monotonic_sort"}
        for record in workload["records"]:
            if record["variant"] != "stable_run_sort":
                continue
            reference = before[(record["mode"], record["profile"])]
            if record["frame_sha256"] != reference["frame_sha256"]:
                raise ValueError("cross-candidate image mismatch")
            collect_before += reference["sort_work"]["collect"]
            collect_after += record["sort_work"]["collect"]
            fast += record["sort_work"]["fast"]
            latency_improved += record["perf"]["cycles"] < reference["perf"]["cycles"]
    previous = root / "experiments/shared_pe/validation_20260914_monotonic_sort_n32/dma_matrix_checked/report.json"
    cross = compare(previous, dma_path, {"bypass", "shared_projection", "monotonic_sort"})
    prior_stable = root / "experiments/shared_pe/validation_20260914_stable_runs_n32/dma_matrix_final/report.json"
    prior = compare(prior_stable, dma_path, {"bypass", "shared_projection", "stable_run_sort"})
    stable_rows = [r for r in prior["records"] if r["variant"] == "stable_run_sort"]
    return {
        "source_current": True,
        "module_configurations": len(module["records"]),
        "module_output_vectors": sum(r["vectors"] for r in module["records"]),
        "non_stress_cases": len(cases),
        "non_stress_non_regressing": sum(r["saved_cycles"] >= 0 for r in cases),
        "non_stress_regressions": [r for r in cases if r["saved_cycles"] < 0],
        "real_dma_runs": dma["aggregate"]["runs"],
        "real_candidate_runs": candidate["runs"],
        "real_candidate_fast_groups": fast,
        "real_candidate_improved_vs_same_round_monotonic_runs": latency_improved,
        "real_candidate_improved_vs_previous_candidate_runs": sum(r["saved_cycles"] > 0 for r in stable_rows),
        "real_candidate_non_regressing_vs_previous_candidate_runs": sum(r["saved_cycles"] >= 0 for r in stable_rows),
        "previous_round_comparisons": prior,
        "real_collect_before": collect_before,
        "real_collect_after": collect_after,
        "real_collect_removed": collect_before-collect_after,
        "candidate_performance_vs_bypass_pass": candidate["performance_vs_bypass_pass"],
        "previous_baselines": cross,
        "universal_non_regression_signed_off": False,
        "energy_area_frequency_signed_off": False,
        "scope": "full-key stable bounded group sort; 374 directed non-stress latency cases and 3 n32 scenes; not final RGB DMA or autonomous full-scene input signoff",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--dma-subdir", default="dma_matrix_final")
    args = parser.parse_args()
    report = audit(Path(__file__).resolve().parents[1], args.bundle.resolve(), args.dma_subdir)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k not in ("previous_baselines", "previous_round_comparisons")}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
