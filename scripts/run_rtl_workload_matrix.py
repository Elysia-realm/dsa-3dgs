from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from datetime import date
from pathlib import Path


PERF_RE = re.compile(
    r"REAL_PERF cycles=(\d+) commits=(\d+) state_misses=(\d+) read_stall=(\d+) "
    r"output_stall=(\d+) state_reads=(\d+) state_writes=(\d+)"
)
LOCALITY_RE = re.compile(r"REAL_WRITE_LOCALITY consecutive_same_pixel_commits=(\d+)")
WRITEBACK_RE = re.compile(
    r"REAL_WRITEBACK enabled=(\d+) depth=(\d+) coalesced=(\d+) forwarded_reads=(\d+)"
)
MULTIWRITE_RE = re.compile(r"REAL_MULTIWRITE enabled=(\d+) depth=(\d+) peak_outstanding=(\d+)")
STAGE_RE = re.compile(
    r"REAL_STAGE mode=(\d+) lanes=(\d+) collect=(\d+) drain=(\d+) group_busy=(\d+) "
    r"sort_busy=(\d+) attr_wait=(\d+) projection_busy=(\d+) sh_busy=(\d+) "
    r"raster_busy=(\d+) overlap=(\d+) sorted_bp=(\d+) block_bp=(\d+) "
    r"retire_wait=(\d+) state_cache_busy=(\d+) window_wait=(\d+) "
    r"window_same=(\d+) window_diff=(\d+) group_active=(\d+) group_service_stall=(\d+)"
)
BACKEND_RE = re.compile(
    r"REAL_BACKEND mshr_count=(\d+) blend_full=(\d+) mshr_zero=(\d+) mshr_one=(\d+) "
    r"mshr_two=(\d+) mshr_full_query_block=(\d+) cache_rsp_block=(\d+) "
    r"miss_issue_block=(\d+) ar_stall=(\d+) r_stall=(\d+) reader_rsp_block=(\d+)"
)
WINDOW_OPP_RE = re.compile(
    r"REAL_WINDOW_OPP third_candidate=(\d+) third_mshr_two=(\d+) third_mshr_one=(\d+) "
    r"third_distinct=(\d+) third_distinct_mshr_two=(\d+) third_raw=(\d+) "
    r"head_need_query=(\d+) head_wait_rsp=(\d+) head_need_blend=(\d+) "
    r"head_wait_blend=(\d+) head_done_blocked=(\d+)"
)
RECONFIG_RE = re.compile(
    r"REAL_RECONFIG projection_mask=([0-9a-fA-F]+) sh_mask=([0-9a-fA-F]+) "
    r"raster_mask=([0-9a-fA-F]+) projection_issue=(\d+) sh_issue=(\d+) raster_issue=(\d+) "
    r"projection_inactive_issue=(\d+) sh_inactive_issue=(\d+) raster_inactive_issue=(\d+)"
)
BLEND_BYPASS_RE = re.compile(r"REAL_BLEND_BYPASS enabled=(\d+) fires=(\d+)")
COMMIT_BYPASS_RE = re.compile(r"REAL_COMMIT_BYPASS enabled=(\d+) fires=(\d+)")
OPERAND_ISOLATION_RE = re.compile(
    r"REAL_OPERAND_ISOLATION enabled=(\d+) broadcast_exposures=(\d+) isolated_exposures=(\d+) avoided_exposures=(\d+)"
)


def run(command: list[str], root: Path) -> str:
    result = subprocess.run(command, cwd=root, text=True, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command)}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser(description="Run local trained-scene RTL workload matrix")
    parser.add_argument("workloads", nargs="+", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--iverilog-root", type=Path, default=Path(r"D:\IcarusVerilog\iverilog"))
    parser.add_argument("--max-count", type=int, default=64)
    parser.add_argument("--max-pixels", type=int, default=4096)
    parser.add_argument("--write-buffer-depth", type=int, default=2)
    parser.add_argument("--state-entries", type=int, default=2)
    parser.add_argument("--state-window-entries", type=int, choices=(2, 4), default=2)
    parser.add_argument("--state-mshr-count", type=int, choices=(1, 2, 4), default=2)
    parser.add_argument("--response-blend-bypass", type=int, choices=(0, 1), default=0)
    parser.add_argument("--blend-commit-bypass", type=int, choices=(0, 1), default=0)
    parser.add_argument("--operand-isolation", type=int, choices=(0, 1), default=0)
    parser.add_argument("--use-writeback", type=int, choices=(0, 1), default=1)
    parser.add_argument("--writeback-depth", type=int, default=32)
    parser.add_argument("--use-multiwrite", type=int, choices=(0, 1), default=1)
    parser.add_argument("--multiwrite-depth", type=int, default=8)
    parser.add_argument("--multiwrite-forwarding", type=int, choices=(0, 1), default=0)
    parser.add_argument("--lanes", type=int, default=1)
    parser.add_argument("--frame-mode", type=int, choices=(0, 1, 2, 3), default=3)
    parser.add_argument("--write-stress-latency", type=int)
    args = parser.parse_args()
    if args.use_writeback and args.use_multiwrite:
        parser.error("write-back coalescing and multiwrite paths are mutually exclusive")
    if args.lanes <= 0:
        parser.error("--lanes must be positive")
    if not ((args.state_window_entries == 2 and args.state_mshr_count in (1, 2)) or
            (args.state_window_entries == 4 and args.state_mshr_count == 4)):
        parser.error("legal state configurations are window/MSHR 2/1, 2/2, or 4/4")
    root = Path(__file__).resolve().parents[1]
    iverilog = args.iverilog_root / "bin" / "iverilog.exe"
    vvp = args.iverilog_root / "bin" / "vvp.exe"
    executable_tag = (f"wb{args.writeback_depth}" if args.use_writeback else
                      f"mw{args.multiwrite_depth}f{args.multiwrite_forwarding}" if args.use_multiwrite else
                      f"wt{args.write_buffer_depth}")
    executable = root / "tmp" / "iverilog" / (
        f"tb_real_dma_matrix_{executable_tag}_s{args.state_entries}_w{args.state_window_entries}_m{args.state_mshr_count}_b{args.response_blend_bypass}c{args.blend_commit_bypass}o{args.operand_isolation}_l{args.lanes}.vvp"
    )
    executable.parent.mkdir(parents=True, exist_ok=True)
    run([
        str(iverilog), "-g2012", "-DSYNTHESIS", f"-DTB_MAX_COUNT={args.max_count}",
        f"-DTB_MAX_PIXELS={args.max_pixels}", f"-DTB_WRITE_BUFFER_DEPTH={args.write_buffer_depth}",
        f"-DTB_STATE_ENTRIES={args.state_entries}",
        f"-DTB_STATE_WINDOW_ENTRIES={args.state_window_entries}",
        f"-DTB_STATE_MSHR_COUNT={args.state_mshr_count}",
        f"-DTB_RESPONSE_BLEND_BYPASS={args.response_blend_bypass}",
        f"-DTB_BLEND_COMMIT_BYPASS={args.blend_commit_bypass}",
        f"-DTB_OPERAND_ISOLATION={args.operand_isolation}",
        f"-DTB_USE_WRITEBACK={args.use_writeback}",
        f"-DTB_WRITEBACK_DEPTH={args.writeback_depth}",
        f"-DTB_USE_MULTIWRITE={args.use_multiwrite}",
        f"-DTB_MULTIWRITE_DEPTH={args.multiwrite_depth}",
        f"-DTB_MULTIWRITE_FORWARDING={args.multiwrite_forwarding}",
        f"-DTB_LANES={args.lanes}",
        "-I", r"rtl\raster", "-s", "tb_real_dma_workload",
        "-o", str(executable), "-f", r"verification\rtl\system_top_sources.f",
        r"verification\rtl\tb_real_dma_workload.sv",
    ], root)
    profiles = {
        "ideal": {"read_latency": 0, "read_gap": 0, "ready_period": 1, "ready_low": 0, "write_response_latency": 2},
        "limited": {"read_latency": 8, "read_gap": 2, "ready_period": 4, "ready_low": 1, "write_response_latency": 8},
    }
    if args.write_stress_latency is not None:
        if args.write_stress_latency < 0:
            parser.error("--write-stress-latency must be non-negative")
        profiles["write_stress"] = {
            "read_latency": 0, "read_gap": 0, "ready_period": 1, "ready_low": 0,
            "write_response_latency": args.write_stress_latency,
        }
    results: list[dict[str, object]] = []
    equivalence: dict[str, dict[str, object]] = {}
    for workload_value in args.workloads:
        workload = (root / workload_value).resolve() if not workload_value.is_absolute() else workload_value
        manifest = json.loads((workload / "manifest.json").read_text(encoding="utf-8"))
        hashes: dict[str, str] = {}
        for profile_name, profile in profiles.items():
            path_tag = (f"wb{args.writeback_depth}" if args.use_writeback else
                        f"mw{args.multiwrite_depth}f{args.multiwrite_forwarding}" if args.use_multiwrite else
                        f"wt{args.write_buffer_depth}")
            frame = workload / (
                f"frame_state_{path_tag}_w{args.state_window_entries}_m{args.state_mshr_count}_b{args.response_blend_bypass}c{args.blend_commit_bypass}o{args.operand_isolation}_{profile_name}.memh"
            )
            label = f"{manifest['scene']}_{profile_name}"
            output = run([
                str(vvp), str(executable), f"+MEAN={workload / 'mean.memh'}", f"+ATTR={workload / 'attribute.memh'}",
                f"+CAMERA={workload / 'camera.memh'}", f"+FRAME={frame}", f"+LABEL={label}",
                f"+READ_LATENCY={profile['read_latency']}", f"+READ_GAP={profile['read_gap']}",
                f"+READY_PERIOD={profile['ready_period']}", f"+READY_LOW={profile['ready_low']}",
                f"+WRITE_RESPONSE_LATENCY={profile['write_response_latency']}",
                f"+FRAME_MODE={args.frame_mode}",
            ], root)
            match = PERF_RE.search(output)
            if not match:
                raise RuntimeError(f"missing REAL_PERF for {label}\n{output}")
            locality = LOCALITY_RE.search(output)
            if not locality:
                raise RuntimeError(f"missing REAL_WRITE_LOCALITY for {label}\n{output}")
            writeback = WRITEBACK_RE.search(output)
            if not writeback:
                raise RuntimeError(f"missing REAL_WRITEBACK for {label}\n{output}")
            multiwrite = MULTIWRITE_RE.search(output)
            if not multiwrite:
                raise RuntimeError(f"missing REAL_MULTIWRITE for {label}\n{output}")
            stage = STAGE_RE.search(output)
            if not stage:
                raise RuntimeError(f"missing REAL_STAGE for {label}\n{output}")
            backend = BACKEND_RE.search(output)
            if not backend:
                raise RuntimeError(f"missing REAL_BACKEND for {label}\n{output}")
            window_opp = WINDOW_OPP_RE.search(output)
            if not window_opp:
                raise RuntimeError(f"missing REAL_WINDOW_OPP for {label}\n{output}")
            reconfig = RECONFIG_RE.search(output)
            if not reconfig:
                raise RuntimeError(f"missing REAL_RECONFIG for {label}\n{output}")
            blend_bypass = BLEND_BYPASS_RE.search(output)
            if not blend_bypass:
                raise RuntimeError(f"missing REAL_BLEND_BYPASS for {label}\n{output}")
            commit_bypass = COMMIT_BYPASS_RE.search(output)
            if not commit_bypass:
                raise RuntimeError(f"missing REAL_COMMIT_BYPASS for {label}\n{output}")
            operand_isolation = OPERAND_ISOLATION_RE.search(output)
            if not operand_isolation:
                raise RuntimeError(f"missing REAL_OPERAND_ISOLATION for {label}\n{output}")
            stage_values = [int(value) for value in stage.groups()]
            backend_values = [int(value) for value in backend.groups()]
            window_opp_values = [int(value) for value in window_opp.groups()]
            reconfig_values = [int(value, 16) for value in reconfig.groups()[:3]] + [
                int(value) for value in reconfig.groups()[3:]
            ]
            values = [int(value) for value in match.groups()]
            results.append({
                "scene": manifest["scene"], "camera": manifest["camera_index"],
                "gaussians": manifest["gaussian_count"], "resolution": [manifest["width"], manifest["height"]],
                "profile": profile_name, "cycles": values[0], "commits": values[1], "state_misses": values[2],
                "read_stall": values[3], "output_stall": values[4], "state_reads": values[5], "state_writes": values[6],
                "consecutive_same_pixel_commits": int(locality.group(1)),
                "writeback_enabled": bool(int(writeback.group(1))),
                "writeback_depth": int(writeback.group(2)),
                "coalesced_writes": int(writeback.group(3)),
                "forwarded_reads": int(writeback.group(4)),
                "multiwrite_enabled": bool(int(multiwrite.group(1))),
                "multiwrite_depth": int(multiwrite.group(2)),
                "peak_outstanding": int(multiwrite.group(3)),
                "frame_mode": stage_values[0], "physical_lanes": stage_values[1],
                "stage_cycles": {
                    "collect": stage_values[2], "drain": stage_values[3],
                    "group_busy": stage_values[4], "sort_busy": stage_values[5],
                    "attribute_wait": stage_values[6], "projection_busy": stage_values[7],
                    "sh_busy": stage_values[8], "raster_busy": stage_values[9],
                    "projection_raster_overlap": stage_values[10],
                    "sorted_backpressure": stage_values[11], "block_backpressure": stage_values[12],
                    "retire_wait": stage_values[13], "state_cache_busy": stage_values[14],
                    "state_window_wait": stage_values[15],
                    "state_window_same_key": stage_values[16],
                    "state_window_different_key": stage_values[17],
                    "group_active_lanes": stage_values[18],
                    "group_service_stall": stage_values[19],
                },
                "backend_cycles": {
                    "mshr_count": backend_values[0], "blend_window_full": backend_values[1],
                    "mshr_zero": backend_values[2], "mshr_one": backend_values[3],
                    "mshr_two": backend_values[4], "mshr_full_query_block": backend_values[5],
                    "cache_response_block": backend_values[6], "miss_issue_block": backend_values[7],
                    "axi_ar_stall": backend_values[8], "axi_r_stall": backend_values[9],
                    "reader_response_block": backend_values[10],
                },
                "window_opportunity": {
                    "third_candidate": window_opp_values[0], "third_mshr_two": window_opp_values[1],
                    "third_mshr_one": window_opp_values[2], "third_distinct": window_opp_values[3],
                    "third_distinct_mshr_two": window_opp_values[4], "third_raw": window_opp_values[5],
                    "head_need_query": window_opp_values[6], "head_wait_response": window_opp_values[7],
                    "head_need_blend": window_opp_values[8], "head_wait_blend": window_opp_values[9],
                    "head_done_blocked": window_opp_values[10],
                },
                "reconfiguration": {
                    "projection_active_mask": reconfig_values[0],
                    "sh_active_mask": reconfig_values[1],
                    "raster_active_mask": reconfig_values[2],
                    "projection_issues": reconfig_values[3],
                    "sh_issues": reconfig_values[4],
                    "raster_issues": reconfig_values[5],
                    "projection_inactive_issues": reconfig_values[6],
                    "sh_inactive_issues": reconfig_values[7],
                    "raster_inactive_issues": reconfig_values[8],
                },
                "blend_bypass": {
                    "enabled": bool(int(blend_bypass.group(1))),
                    "fires": int(blend_bypass.group(2)),
                },
                "commit_bypass": {
                    "enabled": bool(int(commit_bypass.group(1))),
                    "fires": int(commit_bypass.group(2)),
                },
                "operand_isolation": {
                    "enabled": bool(int(operand_isolation.group(1))),
                    "broadcast_exposures": int(operand_isolation.group(2)),
                    "isolated_exposures": int(operand_isolation.group(3)),
                    "avoided_exposures": int(operand_isolation.group(4)),
                },
            })
            hashes[profile_name] = hashlib.sha256(frame.read_bytes()).hexdigest().upper()
            print(output.strip())
        all_profiles_equal = all(value == hashes["ideal"] for value in hashes.values())
        equivalence[manifest["scene"]] = {
            "ideal_equals_limited": hashes["ideal"] == hashes["limited"],
            "all_profiles_equal": all_profiles_equal, "sha256": hashes["ideal"]
        }
        if not all_profiles_equal:
            raise RuntimeError(f"frame mismatch for {manifest['scene']}: {hashes}")
    report = {
        "report_version": 1, "date": date.today().isoformat(), "simulator": "Icarus Verilog 12",
        "workload_class": "multi-scene trained-attribute RTL micro-workload", "profiles": profiles,
        "write_buffer_depth": args.write_buffer_depth,
        "writeback_enabled": bool(args.use_writeback),
        "writeback_depth": args.writeback_depth,
        "multiwrite_enabled": bool(args.use_multiwrite),
        "multiwrite_depth": args.multiwrite_depth,
        "multiwrite_forwarding": bool(args.multiwrite_forwarding),
        "physical_lanes": args.lanes,
        "frame_mode": args.frame_mode,
        "state_entries": args.state_entries,
        "state_window_entries": args.state_window_entries,
        "state_mshr_count": args.state_mshr_count,
        "response_blend_bypass": bool(args.response_blend_bypass),
        "blend_commit_bypass": bool(args.blend_commit_bypass),
        "operand_isolation": bool(args.operand_isolation),
        "results": results, "equivalence": equivalence,
        "interpretation": "AXI timing profiles must produce bit-identical frame state; cycle and stall changes quantify memory sensitivity.",
        "data_policy": "Local D:/3DGS only; no network upload.",
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(args.report)


if __name__ == "__main__":
    main()
