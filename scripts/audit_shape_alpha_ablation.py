"""Audit the marginal benefit of shape rejection after alpha no-op retirement."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from statistics import mean

if __package__:
    from .run_shared_pe_validation import sha256
else:
    from run_shared_pe_validation import sha256


def summarize(rows: list[dict]) -> dict:
    return {
        "runs": len(rows),
        "improved_vs_alpha": sum(r["combined_cycles"] < r["alpha_cycles"] for r in rows),
        "equal_vs_alpha": sum(r["combined_cycles"] == r["alpha_cycles"] for r in rows),
        "regressed_vs_alpha": sum(r["combined_cycles"] > r["alpha_cycles"] for r in rows),
        "improved_vs_shared": sum(r["combined_cycles"] < r["shared_cycles"] for r in rows),
        "faster_than_bypass": sum(r["combined_cycles"] < r["bypass_cycles"] for r in rows),
        "raw_frame_equal_to_alpha": sum(r["raw_frame_equal_to_alpha"] for r in rows),
        "mean_saved_vs_alpha_cycles": mean(r["alpha_cycles"] - r["combined_cycles"] for r in rows),
        "mean_saved_vs_alpha_percent": mean(100 * (r["alpha_cycles"] - r["combined_cycles"])
                                            / r["alpha_cycles"] for r in rows),
        "mean_saved_vs_shared_percent": mean(100 * (r["shared_cycles"] - r["combined_cycles"])
                                             / r["shared_cycles"] for r in rows),
        "removed_alpha_tasks": sum(r["removed_alpha_tasks"] for r in rows),
        "extra_state_reads_saved_vs_alpha": sum(r["extra_state_reads_saved_vs_alpha"] for r in rows),
        "extra_state_writes_saved_vs_alpha": sum(r["extra_state_writes_saved_vs_alpha"] for r in rows),
    }


def audit(root: Path, paths: list[Path]) -> dict:
    rows = []
    seen = set()
    for path in paths:
        report = json.loads(path.read_text(encoding="utf-8"))
        if not report["functional_pass"]:
            raise ValueError(f"incomplete report: {path}")
        for source, digest in report["source_sha256"].items():
            if sha256(root / source) != digest:
                raise ValueError(f"stale source: {source}")
        if sha256(root / "verification/rtl/tb_real_dma_workload.sv") != report["testbench_sha256"]:
            raise ValueError("stale testbench")
        for workload in report["workloads"]:
            name = workload["name"]
            if name in seen:
                raise ValueError(f"duplicate workload: {name}")
            seen.add(name)
            records = workload["records"]
            if len(records) != 40 or len({r["frame_sha256"] for r in records}) != 1:
                raise ValueError(f"incomplete/divergent five-way matrix: {name}")
            index = {(r["variant"], r["mode"], r["profile"]): r for r in records}
            for mode in ("G", "P", "R", "E"):
                for profile in ("ideal", "limited"):
                    bypass, shared, shape, alpha, combined = (
                        index[(v, mode, profile)] for v in ("bypass", "shared_projection",
                            "shape_block_reject", "alpha_zero_skip", "shape_alpha_skip"))
                    if (combined["shape"]["enabled"], combined["alpha_skip"]["enabled"]) != (1, 1):
                        raise ValueError("combined configuration disabled")
                    if combined["shape"]["rejected_blocks"] != shape["shape"]["rejected_blocks"]:
                        raise ValueError("alpha retirement changed shape decisions")
                    removed = shared["perf"]["commits"] - shape["perf"]["commits"]
                    if removed != alpha["alpha_skip"]["skipped"] - combined["alpha_skip"]["skipped"]:
                        raise ValueError("shape/alpha overlap accounting failed")
                    if shape["perf"]["commits"] - combined["perf"]["commits"] != combined["alpha_skip"]["skipped"]:
                        raise ValueError("combined completion accounting failed")
                    if alpha["perf"]["commits"] != combined["perf"]["commits"]:
                        raise ValueError("shape rejection removed a contributing pixel")
                    rows.append({
                        "workload": name, "mode": mode, "profile": profile,
                        "bypass_cycles": bypass["perf"]["cycles"], "shared_cycles": shared["perf"]["cycles"],
                        "shape_cycles": shape["perf"]["cycles"], "alpha_cycles": alpha["perf"]["cycles"],
                        "combined_cycles": combined["perf"]["cycles"],
                        "rejected_blocks": combined["shape"]["rejected_blocks"],
                        "removed_alpha_tasks": removed,
                        "raw_frame_equal_to_alpha": alpha["raw_frame_sha256"] == combined["raw_frame_sha256"],
                        "extra_state_reads_saved_vs_alpha": alpha["perf"]["state_reads"] - combined["perf"]["state_reads"],
                        "extra_state_writes_saved_vs_alpha": alpha["perf"]["state_writes"] - combined["perf"]["state_writes"],
                    })
    if not rows:
        raise ValueError("empty ablation")
    return {"source_current": True, "functional_pass": True, "ppa_signed_off": False,
            "default_enabled": False, "reports": [p.relative_to(root).as_posix() for p in paths],
            "workloads": len(seen), "aggregate": summarize(rows),
            "by_workload": {name: summarize([r for r in rows if r["workload"] == name]) for name in sorted(seen)},
            "rows": rows}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = audit(Path(__file__).resolve().parents[1], [p.resolve() for p in args.reports])
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "rows"}, indent=2))


if __name__ == "__main__":
    main()
