"""Current-source, epoch-aware audit for the optional per-pixel alpha no-op skip."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from statistics import mean

if __package__:
    from .run_shared_pe_validation import sha256
else:
    from run_shared_pe_validation import sha256


def audit(root: Path, reports: list[Path]) -> dict:
    rows: list[dict] = []
    scene_names: set[str] = set()
    for path in reports:
        report = json.loads(path.read_text(encoding="utf-8"))
        if not report["functional_pass"] or "alpha_zero_skip_candidate" not in report:
            raise ValueError(f"incomplete alpha-skip report: {path}")
        for source, digest in report["source_sha256"].items():
            if sha256(root / source) != digest:
                raise ValueError(f"stale RTL evidence: {source}")
        if sha256(root / "verification/rtl/tb_real_dma_workload.sv") != report["testbench_sha256"]:
            raise ValueError("stale DMA testbench evidence")
        for workload in report["workloads"]:
            name = workload["name"]
            if name in scene_names:
                raise ValueError(f"duplicate workload: {name}")
            scene_names.add(name)
            records = workload["records"]
            if len(records) != 24 or len({r["frame_sha256"] for r in records}) != 1:
                raise ValueError(f"incomplete or divergent image: {name}")
            index = {(r["variant"], r["mode"], r["profile"]): r for r in records}
            for mode in ("G", "P", "R", "E"):
                for profile in ("ideal", "limited"):
                    bypass = index[("bypass", mode, profile)]
                    shared = index[("shared_projection", mode, profile)]
                    skip = index[("alpha_zero_skip", mode, profile)]
                    if bypass["alpha_skip"]["skipped"] or shared["alpha_skip"]["skipped"]:
                        raise ValueError(f"default-off alpha skip fired: {name}/{mode}/{profile}")
                    if skip["alpha_skip"]["enabled"] != 1:
                        raise ValueError(f"alpha skip disabled: {name}/{mode}/{profile}")
                    skipped = skip["alpha_skip"]["skipped"]
                    removed_commits = shared["perf"]["commits"] - skip["perf"]["commits"]
                    if skipped != removed_commits:
                        raise ValueError(f"completion accounting mismatch: {name}/{mode}/{profile}")
                    removed_reads = shared["perf"]["state_reads"] - skip["perf"]["state_reads"]
                    removed_writes = shared["perf"]["state_writes"] - skip["perf"]["state_writes"]
                    if removed_reads < 0 or removed_writes < 0:
                        raise ValueError(f"alpha skip increased state traffic: {name}/{mode}/{profile}")
                    rows.append({
                        "workload": name, "mode": mode, "profile": profile,
                        "bypass_cycles": bypass["perf"]["cycles"],
                        "shared_cycles": shared["perf"]["cycles"],
                        "skip_cycles": skip["perf"]["cycles"],
                        "skipped_pixels": skipped,
                        "removed_state_reads": removed_reads,
                        "removed_state_writes": removed_writes,
                        "raw_frame_equal": shared["raw_frame_sha256"] == skip["raw_frame_sha256"],
                    })
    if not rows:
        raise ValueError("empty alpha-skip audit")
    by_workload = []
    for name in sorted(scene_names):
        sample = [row for row in rows if row["workload"] == name]
        by_workload.append({
            "workload": name,
            "runs": len(sample),
            "skipped_pixels": sum(row["skipped_pixels"] for row in sample),
            "improved_vs_shared_runs": sum(row["skip_cycles"] < row["shared_cycles"] for row in sample),
            "faster_than_bypass_runs": sum(row["skip_cycles"] < row["bypass_cycles"] for row in sample),
            "mean_saved_vs_shared_cycles": mean(row["shared_cycles"] - row["skip_cycles"] for row in sample),
            "mean_saved_vs_shared_percent": mean(100 * (row["shared_cycles"] - row["skip_cycles"])
                                                  / row["shared_cycles"] for row in sample),
        })
    return {
        "source_current": True,
        "functional_pass": True,
        "synthesis_or_ppa_signoff": False,
        "default_enabled": False,
        "reports": [path.relative_to(root).as_posix() for path in reports],
        "scenes": len(scene_names), "candidate_runs": len(rows),
        "skipped_pixels": sum(r["skipped_pixels"] for r in rows),
        "removed_state_reads": sum(r["removed_state_reads"] for r in rows),
        "removed_state_writes": sum(r["removed_state_writes"] for r in rows),
        "improved_vs_shared_runs": sum(r["skip_cycles"] < r["shared_cycles"] for r in rows),
        "non_regressing_vs_shared_runs": sum(r["skip_cycles"] <= r["shared_cycles"] for r in rows),
        "faster_than_bypass_runs": sum(r["skip_cycles"] < r["bypass_cycles"] for r in rows),
        "non_regressing_vs_bypass_runs": sum(r["skip_cycles"] <= r["bypass_cycles"] for r in rows),
        "mean_saved_vs_shared_cycles": mean(r["shared_cycles"] - r["skip_cycles"] for r in rows),
        "mean_saved_vs_shared_percent": mean(100 * (r["shared_cycles"] - r["skip_cycles"])
                                             / r["shared_cycles"] for r in rows),
        "mean_gap_vs_bypass_percent": mean(100 * (r["skip_cycles"] - r["bypass_cycles"])
                                           / r["bypass_cycles"] for r in rows),
        "max_gap_vs_bypass_percent": max(100 * (r["skip_cycles"] - r["bypass_cycles"])
                                          / r["bypass_cycles"] for r in rows),
        "raw_frame_mismatch_runs": sum(not r["raw_frame_equal"] for r in rows),
        "by_workload": by_workload,
        "rows": rows,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    result = audit(root, [path.resolve() for path in args.reports])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({key: value for key, value in result.items() if key != "rows"}, indent=2,
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
