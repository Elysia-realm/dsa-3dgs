"""Current-source shape-reject scope audit; structural elaboration is not PPA."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from statistics import mean

from scripts.check_shared_pe_elaboration import count_instances
from scripts.compare_shared_pe_validation import compare
from scripts.run_shared_pe_validation import sha256


def _matrix(root: Path, path: Path, expected_scenes: int, expected_capacity: int) -> dict:
    report = json.loads(path.read_text(encoding="utf-8"))
    if not report["functional_pass"] or len(report["workloads"]) != expected_scenes:
        raise ValueError(f"incomplete DMA matrix: {path}")
    if report["defines"]["TB_MAX_COUNT"] != expected_capacity:
        raise ValueError(f"wrong compiled capacity: {path}")
    for source, digest in report["source_sha256"].items():
        if sha256(root / source) != digest:
            raise ValueError(f"stale RTL evidence: {source}")
    if sha256(root / "verification/rtl/tb_real_dma_workload.sv") != report["testbench_sha256"]:
        raise ValueError("stale DMA testbench")
    rows = []
    for workload in report["workloads"]:
        if expected_capacity == 128:
            manifest = json.loads((root / "experiments/rtl_workloads" / workload["name"] /
                                   "manifest.json").read_text(encoding="utf-8"))
            if manifest["gaussian_count"] != 128:
                raise ValueError("n128 stress evidence does not contain 128 Gaussians")
        records = workload["records"]
        if len(records) != 24 or len({r["frame_sha256"] for r in records}) != 1:
            raise ValueError(f"incomplete or divergent image: {workload['name']}")
        index = {(r["variant"], r["mode"], r["profile"]): r for r in records}
        for mode in ("G", "P", "R", "E"):
            for profile in ("ideal", "limited"):
                bypass = index[("bypass", mode, profile)]
                shared = index[("shared_projection", mode, profile)]
                shape = index[("shape_block_reject", mode, profile)]
                if shared["shape"]["enabled"] or shared["shape"]["rejected_blocks"]:
                    raise ValueError("default-off shape logic fired")
                if shape["shape"]["enabled"] != 1:
                    raise ValueError("shape candidate was not enabled")
                for field in ("commits", "state_reads", "state_writes"):
                    if shape["perf"][field] > shared["perf"][field]:
                        raise ValueError(f"shape candidate increased {field}: {workload['name']}/{mode}/{profile}")
                rows.append({"workload": workload["name"], "mode": mode, "profile": profile,
                             "bypass_cycles": bypass["perf"]["cycles"],
                             "shared_cycles": shared["perf"]["cycles"],
                             "shape_cycles": shape["perf"]["cycles"],
                             "rejected_blocks": shape["shape"]["rejected_blocks"],
                             "removed_commits": shared["perf"]["commits"] - shape["perf"]["commits"],
                             "removed_reads": shared["perf"]["state_reads"] - shape["perf"]["state_reads"],
                             "removed_writes": shared["perf"]["state_writes"] - shape["perf"]["state_writes"],
                             "raw_frame_equal": shared["raw_frame_sha256"] == shape["raw_frame_sha256"]})
    return {"path": path.relative_to(root).as_posix(), "scenes": expected_scenes, "runs": len(rows), "rows": rows,
            "improved_vs_shared": sum(r["shape_cycles"] < r["shared_cycles"] for r in rows),
            "non_regressing_vs_shared": sum(r["shape_cycles"] <= r["shared_cycles"] for r in rows),
            "faster_than_bypass": sum(r["shape_cycles"] < r["bypass_cycles"] for r in rows),
            "non_regressing_vs_bypass": sum(r["shape_cycles"] <= r["bypass_cycles"] for r in rows),
            "rejected_blocks": sum(r["rejected_blocks"] for r in rows),
            "removed_commits": sum(r["removed_commits"] for r in rows),
            "removed_reads": sum(r["removed_reads"] for r in rows),
            "removed_writes": sum(r["removed_writes"] for r in rows),
            "mean_saved_vs_shared_cycles": mean(r["shared_cycles"] - r["shape_cycles"] for r in rows),
            "mean_gap_vs_bypass_percent": mean(100 * (r["shape_cycles"] - r["bypass_cycles"])
                                                / r["bypass_cycles"] for r in rows),
            "max_gap_vs_bypass_percent": max(100 * (r["shape_cycles"] - r["bypass_cycles"])
                                               / r["bypass_cycles"] for r in rows)}


def audit(root: Path, bundle: Path) -> dict:
    default = count_instances(json.loads((bundle / "default.json").read_text(encoding="utf-8")))
    shape = count_instances(json.loads((bundle / "shape.json").read_text(encoding="utf-8")))
    structural = {
        "default_shape_instances": default["gaussian_shape_block_reject"],
        "enabled_shape_instances": shape["gaussian_shape_block_reject"],
        "default_shared_pe_instances": default["shared_reconfigurable_pe_slice"],
        "enabled_shared_pe_instances": shape["shared_reconfigurable_pe_slice"],
    }
    if structural != {"default_shape_instances": 0, "enabled_shape_instances": 1,
                      "default_shared_pe_instances": 1, "enabled_shared_pe_instances": 1}:
        raise ValueError(f"unexpected elaborated resources: {structural}")
    six_path = bundle / "dma_six_original_scenes/report.json"
    six = _matrix(root, six_path, 6, 64)
    seven = _matrix(root, bundle / "dma_seven_new_scenes/report.json", 7, 64)
    small = _matrix(root, bundle / "dma_train_n128/report.json", 1, 128)
    large = _matrix(root, bundle / "dma_train_n128_d64/report.json", 1, 128)
    if {r["workload"] for r in six["rows"]} & {r["workload"] for r in seven["rows"]}:
        raise ValueError("thirteen-scene stress matrix contains duplicate scenes")
    previous_path = root / "experiments/shared_pe/validation_20260916_shape_block_reject_n32/dma_six_scene_release/report.json"
    previous = compare(previous_path, six_path, {"bypass", "shared_projection", "shape_block_reject"})
    if len(previous["records"]) != 144 or any(r["saved_cycles"] != 0 for r in previous["records"]):
        raise ValueError("generate guard changed measured six-scene behavior")
    combined = six["rows"] + seven["rows"]
    return {
        "source_current": True, "functional_pass": True,
        "structural_elaboration_pass": True, "structural": structural,
        "ppa_signed_off": False, "synthesis_executed": False,
        "n32_scenes": 13, "n32_candidate_runs": len(combined),
        "n32_improved_vs_shared": sum(r["shape_cycles"] < r["shared_cycles"] for r in combined),
        "n32_non_regressing_vs_shared": sum(r["shape_cycles"] <= r["shared_cycles"] for r in combined),
        "n32_faster_than_bypass": sum(r["shape_cycles"] < r["bypass_cycles"] for r in combined),
        "n32_non_regressing_vs_bypass": sum(r["shape_cycles"] <= r["bypass_cycles"] for r in combined),
        "n32_rejected_blocks": sum(r["rejected_blocks"] for r in combined),
        "n32_removed_commits": sum(r["removed_commits"] for r in combined),
        "n32_removed_reads": sum(r["removed_reads"] for r in combined),
        "n32_removed_writes": sum(r["removed_writes"] for r in combined),
        "n32_mean_saved_vs_shared_cycles": mean(r["shared_cycles"] - r["shape_cycles"] for r in combined),
        "n32_min_saved_vs_shared_cycles": min(r["shared_cycles"] - r["shape_cycles"] for r in combined),
        "n32_max_saved_vs_shared_cycles": max(r["shared_cycles"] - r["shape_cycles"] for r in combined),
        "n32_mean_gap_vs_bypass_percent": mean(100 * (r["shape_cycles"] - r["bypass_cycles"])
                                                  / r["bypass_cycles"] for r in combined),
        "n32_max_gap_vs_bypass_percent": max(100 * (r["shape_cycles"] - r["bypass_cycles"])
                                                 / r["bypass_cycles"] for r in combined),
        "n32_raw_frame_mismatch_runs": sum(not r["raw_frame_equal"] for r in combined),
        "unchanged_six_scene_runs": len(previous["records"]),
        "n128_small": small, "n128_d64": large,
        "n32_original": six, "n32_new": seven,
        "scope": "13 n32 scenes plus two n128 Train sizes, G/P/R/E and ideal/limited AXI; "
                 "epoch-aware RGB/T equality, structural RTL elaboration only, no mapped area/timing/power",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = audit(Path(__file__).resolve().parents[1], args.bundle.resolve())
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items()
                      if k not in ("n128_small", "n128_d64", "n32_original", "n32_new")},
                     indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
