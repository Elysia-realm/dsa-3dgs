from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime
from pathlib import Path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def stage_collect(log_path: Path) -> int:
    text = log_path.read_text(encoding="utf-8")
    match = re.search(r"^REAL_STAGE .*?\bcollect=(\d+)", text, re.MULTILINE)
    if match is None:
        raise RuntimeError(f"missing REAL_STAGE collect: {log_path}")
    return int(match.group(1))


def audit_report(report_path: Path) -> list[dict]:
    report = json.loads(report_path.read_text(encoding="utf-8"))
    rows: list[dict] = []
    for workload in report["workloads"]:
        by_key = {(r["variant"], r["mode"], r["profile"]): r for r in workload["records"]}
        case_dir = report_path.parent / workload["name"]
        for mode in ("G", "P", "R", "E"):
            for profile in ("ideal", "limited"):
                shared = by_key[("shared_projection", mode, profile)]
                stream = by_key[("streaming_prepass", mode, profile)]
                bypass = by_key[("bypass", mode, profile)]
                if len({shared["frame_sha256"], stream["frame_sha256"], bypass["frame_sha256"]}) != 1:
                    raise RuntimeError(f"frame mismatch: {workload['name']}/{mode}/{profile}")
                if stream["shared_pe"]["main_mac"] != shared["shared_pe"]["main_mac"]:
                    raise RuntimeError("streaming candidate changed the main XYZ MAC work")
                if shared["shared_pe"]["P"] - stream["shared_pe"]["P"] != 96:
                    raise RuntimeError("expected exactly three prepass MACs for each of 32 Gaussians")
                if stream["shared_pe"]["G"] != shared["shared_pe"]["G"]:
                    raise RuntimeError("streaming candidate changed sorting work")
                shared_collect = stage_collect(case_dir / f"shared_projection_{mode}_{profile}.log")
                stream_collect = stage_collect(case_dir / f"streaming_prepass_{mode}_{profile}.log")
                saved = shared["perf"]["cycles"] - stream["perf"]["cycles"]
                if saved <= 0 or shared_collect - stream_collect != saved:
                    raise RuntimeError("whole-frame savings must equal collect-stage savings")
                rows.append({
                    "workload": workload["name"], "scene": workload["scene"], "mode": mode,
                    "profile": profile, "shared_cycles": shared["perf"]["cycles"],
                    "streaming_cycles": stream["perf"]["cycles"], "bypass_cycles": bypass["perf"]["cycles"],
                    "saved_cycles": saved, "shared_collect_cycles": shared_collect,
                    "streaming_collect_cycles": stream_collect,
                    "streaming_gap_vs_bypass_percent": stream["gap_percent"],
                    "shared_p_grants": shared["shared_pe"]["P"],
                    "streaming_p_grants": stream["shared_pe"]["P"],
                    "main_xyz_mac_grants": stream["shared_pe"]["main_mac"],
                    "frame_sha256": stream["frame_sha256"],
                })
    return rows


def mean(values: list[float]) -> float:
    return sum(values) / len(values)


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit streaming depth-prepass A/B reports")
    parser.add_argument("reports", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    rows = [row for report in args.reports for row in audit_report(report.resolve())]
    ideal = [r for r in rows if r["profile"] == "ideal"]
    limited = [r for r in rows if r["profile"] == "limited"]
    result = {
        "report_version": 1,
        "generated_at": datetime.now().astimezone().isoformat(),
        "functional_pass": True,
        "performance_vs_shared_pass": all(r["saved_cycles"] > 0 for r in rows),
        "performance_vs_bypass_pass": all(r["streaming_gap_vs_bypass_percent"] <= 0 for r in rows),
        "default_enabled": False,
        "synthesis_or_ppa_signoff": False,
        "scope": "six n32 real workloads, four fixed modes, ideal/limited AXI; not full-scale or PPA",
        "runs": len(rows), "scenes": len({r["scene"] for r in rows}),
        "improved_vs_shared_runs": sum(r["saved_cycles"] > 0 for r in rows),
        "non_regressing_vs_shared_runs": sum(r["saved_cycles"] >= 0 for r in rows),
        "ideal_saved_cycles": sorted({r["saved_cycles"] for r in ideal}),
        "limited_saved_cycles": sorted({r["saved_cycles"] for r in limited}),
        "mean_saved_cycles": mean([r["saved_cycles"] for r in rows]),
        "mean_gap_vs_bypass_percent": mean([r["streaming_gap_vs_bypass_percent"] for r in rows]),
        "max_gap_vs_bypass_percent": max(r["streaming_gap_vs_bypass_percent"] for r in rows),
        "shared_collect_cycles": sorted({r["shared_collect_cycles"] for r in rows}),
        "streaming_collect_cycles": sorted({r["streaming_collect_cycles"] for r in rows}),
        "removed_shared_prepass_grants_per_n32_run": 96,
        "restored_local_multiplier_operators": 3,
        "source_sha256": {
            path: sha256(root / path) for path in (
                "rtl/gaussian_frame_render_pipeline.sv", "rtl/gs_accel_system_top.sv",
                "rtl/sort/gaussian_depth_prepass_core.sv", "scripts/run_shared_pe_validation.py",
                "verification/rtl/tb_real_dma_workload.sv")
        },
        "input_reports": [str(p) for p in args.reports],
        "rows": rows,
    }
    if len(rows) != 48 or result["scenes"] != 6:
        raise RuntimeError("expected six scenes x four modes x two AXI profiles")
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({k: result[k] for k in (
        "runs", "scenes", "improved_vs_shared_runs", "ideal_saved_cycles",
        "limited_saved_cycles", "mean_gap_vs_bypass_percent", "max_gap_vs_bypass_percent")}, indent=2))


if __name__ == "__main__":
    main()
