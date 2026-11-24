"""Compare immutable DMA matrices by workload/configuration, never by averages alone."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from scripts.run_shared_pe_validation import parse_record


def compare(previous_path: Path, current_path: Path, variants: set[str] | None = None,
            scenes: set[str] | None = None) -> dict:
    previous = json.loads(previous_path.read_text(encoding="utf-8"))
    current = json.loads(current_path.read_text(encoding="utf-8"))
    if not previous["functional_pass"] or not current["functional_pass"]:
        raise ValueError("both matrices must be complete and functionally passing")

    def indexed(report):
        return {(w["name"], r["variant"], r["mode"], r["profile"]): r
                for w in report["workloads"] if scenes is None or w["name"] in scenes for r in w["records"]
                if variants is None or r["variant"] in variants}

    old, new = indexed(previous), indexed(current)
    if variants is not None and ({key[1] for key in old} != variants or {key[1] for key in new} != variants):
        raise ValueError("requested variant is missing")
    if old.keys() != new.keys():
        raise ValueError("matrix axes differ")
    records = []
    for key, before in old.items():
        after = new[key]
        # Older reports stored the physical frame-slot digest in frame_sha256.
        # New reports additionally expose raw_frame_sha256 while frame_sha256
        # canonicalizes pixels from stale epochs for rendered-image comparison.
        # Cross-round unchanged-work comparisons must retain the raw contract.
        before_raw = before.get("raw_frame_sha256", before["frame_sha256"])
        after_raw = after.get("raw_frame_sha256", after["frame_sha256"])
        if before_raw != after_raw:
            raise ValueError(f"cross-round image mismatch: {key}")
        for field in ("commits", "state_reads", "state_writes"):
            if before["perf"][field] != after["perf"][field]:
                raise ValueError(f"work changed: {key}/{field}")
        for field in ("G", "P", "R", "main_mac"):
            if before["shared_pe"][field] != after["shared_pe"][field]:
                raise ValueError(f"PE operation count changed: {key}/{field}")
        name, variant, mode, profile = key
        tag = f"{variant}_{mode}_{profile}"
        stages = [parse_record((path.parent / name / f"{tag}.log").read_text(encoding="utf-8"), "REAL_STAGE")
                  for path in (previous_path, current_path)]
        records.append({"workload": name, "variant": variant, "mode": mode, "profile": profile,
                        "previous_cycles": before["perf"]["cycles"], "current_cycles": after["perf"]["cycles"],
                        "saved_cycles": before["perf"]["cycles"] - after["perf"]["cycles"],
                        "previous_collect": stages[0]["collect"], "current_collect": stages[1]["collect"],
                        "previous_drain": stages[0]["drain"], "current_drain": stages[1]["drain"]})
    full = [r for r in records if r["variant"] == "shared_projection"]
    return {"cross_round_functional_pass": True, "records": records,
            "previous_mean_gap_percent": previous["aggregate"]["mean_gap_percent"],
            "current_mean_gap_percent": current["aggregate"]["mean_gap_percent"],
            "full_shared_improved_runs": sum(r["saved_cycles"] > 0 for r in full),
            "full_shared_runs": len(full), "current_performance_pass": current["performance_pass"]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--previous", required=True, type=Path)
    parser.add_argument("--current", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--variants", nargs="+")
    args = parser.parse_args()
    report = compare(args.previous, args.current, None if args.variants is None else set(args.variants))
    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "records"}, indent=2))


if __name__ == "__main__":
    main()
