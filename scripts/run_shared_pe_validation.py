from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from datetime import datetime
from pathlib import Path


MODES = {0: "G", 1: "P", 2: "R", 3: "E"}
VARIANTS = {"bypass": (0, 0, 0, 1, 1, 0, 0), "prepass_only": (1, 0, 0, 1, 1, 0, 0),
            "shared_projection": (1, 1, 0, 1, 1, 0, 0), "parallel_sort": (1, 1, 1, 0, 0, 0, 0),
            "adaptive_sort": (1, 1, 1, 1, 1, 0, 0), "phase_sort": (1, 1, 1, 1, 1, 1, 0),
            "monotonic_sort": (1, 1, 1, 1, 1, 1, 1),
            "stable_run_sort": (1, 1, 1, 1, 1, 1, 1),
            "streaming_prepass": (1, 1, 0, 1, 1, 0, 0),
            "shape_block_reject": (1, 1, 0, 1, 1, 0, 0),
            "shared_raster_blend": (1, 1, 0, 1, 1, 0, 0),
            "alpha_zero_skip": (1, 1, 0, 1, 1, 0, 0),
            "shape_alpha_skip": (1, 1, 0, 1, 1, 0, 0),
            "binary_sort": (1, 1, 0, 1, 1, 0, 0)}
PROFILES = {
    "ideal": (0, 0, 1, 0, 2),
    "limited": (8, 2, 4, 1, 8),
}


def parse_record(log: str, prefix: str) -> dict[str, int]:
    match = re.search(rf"^{re.escape(prefix)} (.+)$", log, re.MULTILINE)
    if match is None:
        raise ValueError(f"missing {prefix} record")
    return {key: int(value) for key, value in re.findall(r"(\w+)=(\d+)", match.group(1))}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def semantic_frame_sha256(path: Path, epoch: int) -> str:
    """Hash architectural RGB/T, canonicalizing stale-epoch memory to clear state."""
    canonical = bytearray()
    for line in path.read_text(encoding="utf-8").splitlines():
        record = int(line, 16)
        record_epoch = (record >> 55) & 0xFFFF
        state = record & ((1 << 55) - 1) if record_epoch == epoch else 0xFFFF << 39
        canonical.extend(state.to_bytes(7, byteorder="little"))
    return hashlib.sha256(canonical).hexdigest().upper()


def main() -> None:
    parser = argparse.ArgumentParser(description="Shared PE production/bypass fixed-mode DMA A/B")
    parser.add_argument("workloads", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--iverilog-root", type=Path, default=Path(r"D:\IcarusVerilog\iverilog"))
    parser.add_argument("--variants", nargs="+", choices=tuple(VARIANTS))
    parser.add_argument("--max-count", type=int, default=64,
                        help="compiled Gaussian/group capacity; default keeps the n32 baseline unchanged")
    args = parser.parse_args()
    if not 1 <= args.max_count <= 255:
        parser.error("--max-count must fit the testbench 8-bit GID/sequence fields")
    variants = {key: value for key, value in VARIANTS.items() if args.variants is None or key in args.variants}
    if not {"bypass", "shared_projection"}.issubset(variants):
        parser.error("bypass and shared_projection are required performance references")
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    # Each experiment gets separate immutable-by-convention frames/logs; never
    # overwrite the workload's legacy frame artifacts or previous reports.
    output.mkdir(parents=True, exist_ok=False)
    binaries: dict[str, Path] = {}
    defines = {
        "TB_MAX_COUNT": args.max_count, "TB_MAX_PIXELS": 4096, "TB_STATE_ENTRIES": 512,
        "TB_STATE_WINDOW_ENTRIES": 4, "TB_STATE_MSHR_COUNT": 4,
        "TB_RESPONSE_BLEND_BYPASS": 1, "TB_BLEND_COMMIT_BYPASS": 1,
        "TB_OPERAND_ISOLATION": 1, "TB_LANES": 4, "TB_USE_MULTIWRITE": 1,
    }
    iverilog = args.iverilog_root / "bin/iverilog.exe"
    vvp = args.iverilog_root / "bin/vvp.exe"
    for variant, (shared, projection, parallel, fallback, forwarding, phase, monotonic) in variants.items():
        binary = output / f"{variant}.vvp"
        command = [str(iverilog), "-g2012", "-DSYNTHESIS", "-I", "rtl/raster",
                   *[f"-D{k}={v}" for k, v in defines.items()],
                   f"-DTB_USE_SHARED_PE={shared}", f"-DTB_USE_SHARED_PROJECTION_PE={projection}",
                   f"-DTB_USE_SHARED_RASTER_PE={int(variant == 'shared_raster_blend')}",
                   f"-DTB_ENABLE_ALPHA_ZERO_SKIP={int(variant in ('alpha_zero_skip', 'shape_alpha_skip'))}",
                   f"-DTB_USE_PARALLEL_GROUP_SORT={parallel}",
                   f"-DTB_SHARED_SORT_BINARY_SEARCH={int(variant == 'binary_sort')}",
                   f"-DTB_SORT_SERIAL_FALLBACK={fallback}", f"-DTB_SORT_BATCH_FORWARDING={forwarding}",
                   f"-DTB_SORT_PHASE_FORWARDING={phase}",
                   f"-DTB_SORT_MONOTONIC_FASTPATH={monotonic}",
                   f"-DTB_SORT_STABLE_RUN_FASTPATH={int(variant == 'stable_run_sort')}",
                   f"-DTB_USE_STREAMING_DEPTH_PREPASS={int(variant == 'streaming_prepass')}",
                   f"-DTB_ENABLE_SHAPE_BLOCK_REJECT={int(variant in ('shape_block_reject', 'shape_alpha_skip'))}",
                   "-s", "tb_real_dma_workload", "-o", str(binary),
                   "-f", "verification/rtl/system_top_sources.f", "verification/rtl/tb_real_dma_workload.sv"]
        result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=60)
        (output / f"{variant}_compile.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        if result.returncode:
            raise RuntimeError(f"compile failed: {variant}")
        binaries[variant] = binary
    sources = (root / "verification/rtl/system_top_sources.f").read_text(encoding="utf-8").splitlines()
    report: dict = {
        "report_version": 1, "generated_at": datetime.now().astimezone().isoformat(),
        "defines": defines, "variants": variants, "profiles": PROFILES,
        "source_sha256": {source: sha256(root / source) for source in sources if source.strip()},
        "testbench_sha256": sha256(root / "verification/rtl/tb_real_dma_workload.sv"),
        "workloads": [], "functional_pass": False, "performance_pass": False,
    }
    for workload in args.workloads:
        workload = workload.resolve()
        manifest = json.loads((workload / "manifest.json").read_text(encoding="utf-8"))
        if manifest["gaussian_count"] > args.max_count:
            raise ValueError(f"{workload.name} has {manifest['gaussian_count']} Gaussians, "
                             f"above compiled --max-count={args.max_count}")
        case_dir = output / workload.name
        case_dir.mkdir()
        records = []
        for mode, mode_name in MODES.items():
            for profile, timing in PROFILES.items():
                reference = None
                reference_cycles = None
                for variant, binary in binaries.items():
                    tag = f"{variant}_{mode_name}_{profile}"
                    frame = case_dir / f"{tag}.memh"
                    command = [str(vvp), str(binary), f"+MEAN={workload / 'mean.memh'}",
                               f"+ATTR={workload / 'attribute.memh'}", f"+CAMERA={workload / 'camera.memh'}",
                               f"+FRAME={frame}", f"+FRAME_MODE={mode}", f"+LABEL={tag}", "+MAX_TIMEOUT=500000",
                               *[f"+{key}={value}" for key, value in zip(
                                   ("READ_LATENCY", "READ_GAP", "READY_PERIOD", "READY_LOW", "WRITE_RESPONSE_LATENCY"), timing)]]
                    result = subprocess.run(command, cwd=root, text=True, capture_output=True, timeout=60)
                    log = result.stdout + result.stderr
                    (case_dir / f"{tag}.log").write_text(log, encoding="utf-8")
                    if result.returncode or "PASS: tb_real_dma_workload" not in log:
                        raise RuntimeError(f"DMA failed: {workload.name}/{tag}\n{log[-4000:]}")
                    perf = parse_record(log, "REAL_PERF")
                    telemetry = parse_record(log, "REAL_SHARED_PE")
                    sort_work = parse_record(log, "REAL_SORT_WORK")
                    shape = parse_record(log, "REAL_SHAPE")
                    alpha_skip = parse_record(log, "REAL_ALPHA_SKIP")
                    continuation = parse_record(log, "REAL_CONTINUATION")
                    raw_digest = sha256(frame)
                    digest = semantic_frame_sha256(frame, continuation["epoch"])
                    if reference is None:
                        reference, reference_cycles = digest, perf["cycles"]
                    if digest != reference:
                        raise RuntimeError(f"frame mismatch: {workload.name}/{tag}")
                    if parse_record(log, "REAL_STAGE")["mode"] != mode:
                        raise RuntimeError(f"mode mismatch: {tag}")
                    if telemetry["utilization"] != telemetry["G"] + telemetry["P"] + telemetry["R"]:
                        raise RuntimeError(f"utilization mismatch: {tag}")
                    if (variant == "shared_raster_blend") != (telemetry["R"] > 0):
                        raise RuntimeError(f"R-client grant mismatch: {tag}")
                    if variant in ("shared_projection", "parallel_sort", "adaptive_sort", "phase_sort", "monotonic_sort", "stable_run_sort", "streaming_prepass", "shape_block_reject", "shared_raster_blend", "alpha_zero_skip", "shape_alpha_skip", "binary_sort") and telemetry["main_mac"] == 0:
                        raise RuntimeError(f"main projection did not use PE: {tag}")
                    if shape["enabled"] != int(variant in ("shape_block_reject", "shape_alpha_skip")):
                        raise RuntimeError(f"shape enable mismatch: {tag}")
                    if variant not in ("shape_block_reject", "shape_alpha_skip") and shape["rejected_blocks"] != 0:
                        raise RuntimeError(f"disabled shape reject fired: {tag}")
                    if alpha_skip["enabled"] != int(variant in ("alpha_zero_skip", "shape_alpha_skip")):
                        raise RuntimeError(f"alpha skip enable mismatch: {tag}")
                    if variant not in ("alpha_zero_skip", "shape_alpha_skip") and alpha_skip["skipped"] != 0:
                        raise RuntimeError(f"disabled alpha skip fired: {tag}")
                    records.append({"variant": variant, "mode": mode_name, "profile": profile,
                                    "perf": perf, "shared_pe": telemetry, "sort_work": sort_work,
                                    "shape": shape, "alpha_skip": alpha_skip,
                                    "frame_sha256": digest, "raw_frame_sha256": raw_digest,
                                    "gap_percent": 100 * (perf["cycles"] - reference_cycles) / reference_cycles})
                    print(f"{workload.name}/{tag}: cycles={perf['cycles']} contention={telemetry['competing']} hash PASS", flush=True)
        # All modes and AXI timing profiles must also reproduce the same image.
        if len({record["frame_sha256"] for record in records}) != 1:
            raise RuntimeError(f"cross-mode/profile image mismatch: {workload.name}")
        report["workloads"].append({"name": workload.name, "scene": manifest["scene"], "records": records})
        (output / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    full = [r for w in report["workloads"] for r in w["records"] if r["variant"] == "shared_projection"]
    report["functional_pass"] = True
    report["production_contention_observed"] = any(r["shared_pe"]["competing"] > 0 for r in full)
    report["performance_pass"] = all(r["gap_percent"] <= 0 for r in full)
    report["aggregate"] = {"runs": sum(len(w["records"]) for w in report["workloads"]),
                           "full_shared_runs": len(full),
                           "contended_runs": sum(r["shared_pe"]["competing"] > 0 for r in full),
                           "mean_gap_percent": sum(r["gap_percent"] for r in full) / len(full),
                           "max_gap_percent": max(r["gap_percent"] for r in full)}
    serial_cycles = {(w["name"], r["mode"], r["profile"]): r["perf"]["cycles"]
                     for w in report["workloads"] for r in w["records"] if r["variant"] == "shared_projection"}
    for variant in ("parallel_sort", "adaptive_sort", "phase_sort", "monotonic_sort", "stable_run_sort"):
        if variant not in variants:
            continue
        candidates = [r for w in report["workloads"] for r in w["records"] if r["variant"] == variant]
        comparisons = []
        for workload in report["workloads"]:
            for record in workload["records"]:
                if record["variant"] == variant:
                    before = serial_cycles[(workload["name"], record["mode"], record["profile"])]
                    comparisons.append({"workload": workload["name"], "mode": record["mode"], "profile": record["profile"],
                                        "serial_cycles": before, "parallel_cycles": record["perf"]["cycles"],
                                        "saved_cycles": before - record["perf"]["cycles"]})
        report[f"{variant}_candidate"] = {
            "functional_pass": True, "default_enabled": False, "synthesis_or_ppa_signoff": False,
            "variant": variant, "runs": len(candidates), "contended_runs": sum(r["shared_pe"]["competing"] > 0 for r in candidates),
            "improved_vs_serial_runs": sum(r["saved_cycles"] > 0 for r in comparisons),
            "non_regressing_vs_serial_runs": sum(r["saved_cycles"] >= 0 for r in comparisons),
            "performance_vs_bypass_pass": all(r["gap_percent"] <= 0 for r in candidates),
            "mean_gap_vs_bypass_percent": sum(r["gap_percent"] for r in candidates) / len(candidates),
            "max_gap_vs_bypass_percent": max(r["gap_percent"] for r in candidates), "comparisons": comparisons}
    if "streaming_prepass" in variants:
        candidates = [r for w in report["workloads"] for r in w["records"] if r["variant"] == "streaming_prepass"]
        comparisons = []
        for workload in report["workloads"]:
            for record in workload["records"]:
                if record["variant"] == "streaming_prepass":
                    before = serial_cycles[(workload["name"], record["mode"], record["profile"])]
                    comparisons.append({"workload": workload["name"], "mode": record["mode"],
                                        "profile": record["profile"], "shared_cycles": before,
                                        "streaming_cycles": record["perf"]["cycles"],
                                        "saved_cycles": before - record["perf"]["cycles"]})
        report["streaming_prepass_candidate"] = {
            "functional_pass": True, "default_enabled": False, "synthesis_or_ppa_signoff": False,
            "restored_local_multiplier_operators": 3, "runs": len(candidates),
            "improved_vs_shared_runs": sum(r["saved_cycles"] > 0 for r in comparisons),
            "non_regressing_vs_shared_runs": sum(r["saved_cycles"] >= 0 for r in comparisons),
            "mean_gap_vs_bypass_percent": sum(r["gap_percent"] for r in candidates) / len(candidates),
            "max_gap_vs_bypass_percent": max(r["gap_percent"] for r in candidates),
            "comparisons": comparisons}
    if "shape_block_reject" in variants:
        candidates = [r for w in report["workloads"] for r in w["records"] if r["variant"] == "shape_block_reject"]
        comparisons = []
        for workload in report["workloads"]:
            references = {(r["mode"], r["profile"]): r for r in workload["records"]
                          if r["variant"] == "shared_projection"}
            for record in workload["records"]:
                if record["variant"] == "shape_block_reject":
                    before = references[(record["mode"], record["profile"])]
                    comparisons.append({
                        "workload": workload["name"], "mode": record["mode"], "profile": record["profile"],
                        "shared_cycles": before["perf"]["cycles"], "shape_cycles": record["perf"]["cycles"],
                        "saved_cycles": before["perf"]["cycles"] - record["perf"]["cycles"],
                        "removed_commits": before["perf"]["commits"] - record["perf"]["commits"],
                        "removed_state_reads": before["perf"]["state_reads"] - record["perf"]["state_reads"],
                        "removed_state_writes": before["perf"]["state_writes"] - record["perf"]["state_writes"],
                        "rejected_blocks": record["shape"]["rejected_blocks"],
                    })
        report["shape_block_reject_candidate"] = {
            "functional_pass": True, "default_enabled": False, "synthesis_or_ppa_signoff": False,
            "conservative_axis": "l11*dy", "local_multiplier_operators": 1,
            "runs": len(candidates), "total_rejected_blocks": sum(r["shape"]["rejected_blocks"] for r in candidates),
            "improved_vs_shared_runs": sum(r["saved_cycles"] > 0 for r in comparisons),
            "non_regressing_vs_shared_runs": sum(r["saved_cycles"] >= 0 for r in comparisons),
            "total_removed_commits": sum(r["removed_commits"] for r in comparisons),
            "total_removed_state_reads": sum(r["removed_state_reads"] for r in comparisons),
            "total_removed_state_writes": sum(r["removed_state_writes"] for r in comparisons),
            "comparisons": comparisons,
        }
    if "shared_raster_blend" in variants:
        comparisons = []
        for workload in report["workloads"]:
            references = {(r["mode"], r["profile"]): r for r in workload["records"]
                          if r["variant"] == "shared_projection"}
            for record in workload["records"]:
                if record["variant"] == "shared_raster_blend":
                    before = references[(record["mode"], record["profile"])]
                    comparisons.append({
                        "workload": workload["name"], "mode": record["mode"], "profile": record["profile"],
                        "local_cycles": before["perf"]["cycles"], "r_client_cycles": record["perf"]["cycles"],
                        "added_cycles": record["perf"]["cycles"] - before["perf"]["cycles"],
                        "r_grants": record["shared_pe"]["R"],
                        "r_stalls": record["shared_pe"]["R_stall"],
                    })
        report["shared_raster_blend_candidate"] = {
            "functional_pass": True, "default_enabled": False, "synthesis_or_ppa_signoff": False,
            "operation": "blend old_t_q16 * alpha_q12",
            "runs": len(comparisons),
            "r_grants": sum(r["r_grants"] for r in comparisons),
            "non_regressing_vs_local_runs": sum(r["added_cycles"] <= 0 for r in comparisons),
            "mean_added_cycles": sum(r["added_cycles"] for r in comparisons) / len(comparisons),
            "comparisons": comparisons,
        }
    if "alpha_zero_skip" in variants:
        comparisons = []
        for workload in report["workloads"]:
            references = {(r["mode"], r["profile"]): r for r in workload["records"]
                          if r["variant"] == "shared_projection"}
            for record in workload["records"]:
                if record["variant"] == "alpha_zero_skip":
                    before = references[(record["mode"], record["profile"])]
                    removed_commits = before["perf"]["commits"] - record["perf"]["commits"]
                    if removed_commits != record["alpha_skip"]["skipped"]:
                        raise RuntimeError(f"alpha skip accounting mismatch: {workload['name']}/{record['mode']}/{record['profile']}")
                    comparisons.append({
                        "workload": workload["name"], "mode": record["mode"], "profile": record["profile"],
                        "shared_cycles": before["perf"]["cycles"], "alpha_skip_cycles": record["perf"]["cycles"],
                        "saved_cycles": before["perf"]["cycles"] - record["perf"]["cycles"],
                        "skipped_pixels": record["alpha_skip"]["skipped"],
                        "removed_commits": removed_commits,
                        "removed_state_reads": before["perf"]["state_reads"] - record["perf"]["state_reads"],
                        "removed_state_writes": before["perf"]["state_writes"] - record["perf"]["state_writes"],
                    })
        report["alpha_zero_skip_candidate"] = {
            "functional_pass": True, "default_enabled": False, "synthesis_or_ppa_signoff": False,
            "runs": len(comparisons),
            "skipped_pixels": sum(r["skipped_pixels"] for r in comparisons),
            "improved_vs_shared_runs": sum(r["saved_cycles"] > 0 for r in comparisons),
            "non_regressing_vs_shared_runs": sum(r["saved_cycles"] >= 0 for r in comparisons),
            "removed_state_reads": sum(r["removed_state_reads"] for r in comparisons),
            "removed_state_writes": sum(r["removed_state_writes"] for r in comparisons),
            "comparisons": comparisons,
        }
    (output / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(report["aggregate"], indent=2), flush=True)


if __name__ == "__main__":
    main()
