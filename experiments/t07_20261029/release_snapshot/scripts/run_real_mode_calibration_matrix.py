from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path


PERF_RE = re.compile(
    r"REAL_PERF cycles=(\d+) commits=(\d+) state_misses=(\d+) read_stall=(\d+) "
    r"output_stall=(\d+) state_reads=(\d+) state_writes=(\d+)"
)
STAGE_MODE_RE = re.compile(r"REAL_STAGE mode=(\d+)")
MODE_NAMES = {0: "G", 1: "P", 2: "R", 3: "E"}
PERF_FIELDS = (
    "cycles", "commits", "state_misses", "read_stall", "output_stall",
    "state_reads", "state_writes",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def workload_files(workload: Path) -> tuple[Path, Path | None, str]:
    sparse_attribute = workload / "attribute_sparse.memh"
    global_gid = workload / "global_gid.memh"
    dense_attribute = workload / "attribute.memh"
    if sparse_attribute.exists() and global_gid.exists():
        return sparse_attribute, global_gid, "sparse_global_gid"
    if dense_attribute.exists():
        return dense_attribute, None, "dense_frame_local_gid"
    raise FileNotFoundError(f"no supported attribute layout in {workload}")


def run_fixed_mode(
    root: Path,
    executable: Path,
    workload: Path,
    mode: int,
    output_dir: Path,
    max_timeout: int,
    run_env: dict[str, str],
) -> dict[str, object]:
    attribute, global_gid, attribute_layout = workload_files(workload)
    frame = output_dir / f"fixed_{MODE_NAMES[mode]}_frame_state.memh"
    log_path = output_dir / f"fixed_{MODE_NAMES[mode]}.log"
    command = [
        str(executable), f"+MEAN={workload / 'mean.memh'}", f"+ATTR={attribute}",
        f"+CAMERA={workload / 'camera.memh'}", f"+FRAME={frame}",
        f"+LABEL=calibration_{workload.name}_{MODE_NAMES[mode]}", f"+FRAME_MODE={mode}",
        f"+MAX_TIMEOUT={max_timeout}",
    ]
    if global_gid is not None:
        command.append(f"+GLOBAL_GIDS={global_gid}")
    result = subprocess.run(
        command, cwd=root, text=True, capture_output=True, check=False, env=run_env
    )
    log = result.stdout + result.stderr
    log_path.write_text(log, encoding="utf-8")
    if result.returncode or "PASS: tb_real_dma_workload" not in log:
        raise RuntimeError(
            f"fixed {MODE_NAMES[mode]} failed for {workload.name} ({result.returncode})\n{log[-8000:]}"
        )
    perf_match = PERF_RE.search(log)
    stage_match = STAGE_MODE_RE.search(log)
    if perf_match is None or stage_match is None:
        raise RuntimeError(f"missing structured fixed-mode records in {log_path}")
    active_mode = int(stage_match.group(1))
    if active_mode != mode:
        raise RuntimeError(f"requested mode {mode}, observed mode {active_mode} in {log_path}")
    perf = {key: int(value) for key, value in zip(PERF_FIELDS, perf_match.groups())}
    return {
        "mode": mode,
        "mode_name": MODE_NAMES[mode],
        "attribute_layout": attribute_layout,
        "perf": perf,
        "frame_sha256": sha256(frame),
        "log": str(log_path.resolve()),
        "frame": str(frame.resolve()),
    }


def write_reports(output_dir: Path, report: dict[str, object]) -> None:
    results = report["workloads"]
    rows: list[dict[str, object]] = []
    for item in results:
        fixed = item["fixed_modes"]
        histogram = item["auto"]["winner_histogram"]["observe_frame"]
        rows.append({
            "workload": item["workload"],
            "scene": item["scene"],
            "camera_index": item["camera_index"],
            "gaussian_count": item["gaussian_count"],
            "g_cycles": fixed["G"]["perf"]["cycles"],
            "p_cycles": fixed["P"]["perf"]["cycles"],
            "r_cycles": fixed["R"]["perf"]["cycles"],
            "e_cycles": fixed["E"]["perf"]["cycles"],
            "best_fixed_mode": item["best_fixed_mode"],
            "best_fixed_cycles": item["best_fixed_cycles"],
            "auto_recommendation_valid": item["auto"]["auto"]["recommendation_valid"],
            "auto_recommended_mode": item["auto_recommended_mode"] or "",
            "auto_selected_mode": item["auto_selected_mode"],
            "auto_selected_runtime_cycles": item["auto_selected_runtime_cycles"],
            "selected_fixed_cycles": item["selected_fixed_cycles"],
            "auto_runtime_overhead_cycles": item["auto_runtime_overhead_cycles"],
            "auto_gap_cycles": item["auto_gap_cycles"],
            "auto_gap_percent": item["auto_gap_percent"],
            "auto_matches_best": int(item["auto_matches_best"]),
            "auto_within_one_percent": int(item["auto_within_one_percent"]),
            "first_queued_window": item["first_queued_window"],
            "observe_g_windows": histogram["0"],
            "observe_p_windows": histogram["1"],
            "observe_r_windows": histogram["2"],
            "observe_e_windows": histogram["3"],
            "fixed_hash_equal": int(item["fixed_hash_equal"]),
            "auto_image_mismatches": item["auto"]["auto"]["image_mismatches"],
        })
    csv_path = output_dir / "summary.csv"
    if rows:
        with csv_path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    (output_dir / "report.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Calibrate fixed G/P/R/E and automatic selection across real RTL workloads"
    )
    parser.add_argument("workloads", nargs="*", type=Path)
    parser.add_argument("--workload-root", type=Path, default=Path("experiments/rtl_workloads"))
    parser.add_argument("--pattern", default="*_cammid_n32_d64")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--executable", type=Path,
        default=Path("tmp/verilator_bonsai1024_range_obj/tb_bonsai1024_range.exe"),
    )
    parser.add_argument("--msys2-root", type=Path, default=Path(r"D:\Tools\msys64"))
    parser.add_argument("--max-timeout", type=int, default=4_000_000)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    executable = args.executable if args.executable.is_absolute() else root / args.executable
    output_dir = args.output_dir if args.output_dir.is_absolute() else root / args.output_dir
    workload_root = args.workload_root if args.workload_root.is_absolute() else root / args.workload_root
    if args.workloads:
        workloads = [path if path.is_absolute() else root / path for path in args.workloads]
    else:
        workloads = sorted(path for path in workload_root.glob(args.pattern) if path.is_dir())
    if not executable.exists():
        raise FileNotFoundError(executable)
    if not workloads:
        raise RuntimeError("no workloads selected")
    output_dir.mkdir(parents=True, exist_ok=True)

    run_env = os.environ.copy()
    ucrt64_bin = args.msys2_root / "ucrt64" / "bin"
    if ucrt64_bin.is_dir():
        run_env["PATH"] = str(ucrt64_bin.resolve()) + os.pathsep + run_env.get("PATH", "")

    report: dict[str, object] = {
        "report_version": 1,
        "generated_at": datetime.now().astimezone().isoformat(),
        "executable": str(executable.resolve()),
        "executable_sha256": sha256(executable),
        "mode_names": {str(key): value for key, value in MODE_NAMES.items()},
        "workloads": [],
    }
    for workload in workloads:
        for required in (workload / "mean.memh", workload / "camera.memh"):
            if not required.exists():
                raise FileNotFoundError(required)
        manifest_path = workload / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
        workload_output = output_dir / workload.name
        workload_output.mkdir(parents=True, exist_ok=True)
        fixed_results = {
            MODE_NAMES[mode]: run_fixed_mode(
                root, executable, workload, mode, workload_output, args.max_timeout, run_env
            )
            for mode in range(4)
        }
        fixed_hashes = {entry["frame_sha256"] for entry in fixed_results.values()}
        if len(fixed_hashes) != 1:
            raise RuntimeError(f"fixed modes changed framebuffer for {workload.name}: {fixed_hashes}")

        auto_output = workload_output / "auto"
        auto_command = [
            sys.executable, str(root / "scripts/run_real_auto_mode_probe.py"), str(workload),
            "--output-dir", str(auto_output), "--executable", str(executable),
            "--initial-mode", "3", "--max-timeout", str(args.max_timeout),
            "--msys2-root", str(args.msys2_root),
        ]
        auto_result = subprocess.run(
            auto_command, cwd=root, text=True, capture_output=True, check=False, env=run_env
        )
        (workload_output / "auto_runner.log").write_text(
            auto_result.stdout + auto_result.stderr, encoding="utf-8"
        )
        if auto_result.returncode:
            raise RuntimeError(
                f"automatic probe failed for {workload.name} ({auto_result.returncode})\n"
                f"{(auto_result.stdout + auto_result.stderr)[-8000:]}"
            )
        auto = json.loads((auto_output / "report.json").read_text(encoding="utf-8"))
        fixed_cycles = {
            name: entry["perf"]["cycles"] for name, entry in fixed_results.items()
        }
        best_fixed_mode = min(fixed_cycles, key=fixed_cycles.get)
        best_fixed_cycles = fixed_cycles[best_fixed_mode]
        selected_mode = MODE_NAMES[auto["auto"]["selected_mode"]]
        selected_runtime_cycles = auto["auto"]["selected_cycles"]
        selected_fixed_cycles = fixed_cycles[selected_mode]
        gap_cycles = selected_fixed_cycles - best_fixed_cycles
        gap_percent = 100.0 * gap_cycles / best_fixed_cycles if best_fixed_cycles else 0.0
        recommendation_valid = bool(auto["auto"]["recommendation_valid"])
        recommended_mode = (
            MODE_NAMES[auto["auto"]["recommended_mode"]] if recommendation_valid else None
        )
        first_queued = auto["first_queued_window"]
        item = {
            "workload": workload.name,
            "path": str(workload.resolve()),
            "scene": manifest.get("scene", workload.name.split("_")[0]),
            "camera_index": manifest.get("camera_index"),
            "gaussian_count": manifest.get("gaussian_count"),
            "fixed_modes": fixed_results,
            "fixed_hash_equal": True,
            "fixed_frame_sha256": next(iter(fixed_hashes)),
            "best_fixed_mode": best_fixed_mode,
            "best_fixed_cycles": best_fixed_cycles,
            "auto": auto,
            "auto_recommended_mode": recommended_mode,
            "auto_selected_mode": selected_mode,
            "auto_selected_runtime_cycles": selected_runtime_cycles,
            "selected_fixed_cycles": selected_fixed_cycles,
            "auto_runtime_overhead_cycles": selected_runtime_cycles - selected_fixed_cycles,
            "auto_gap_cycles": gap_cycles,
            "auto_gap_percent": round(gap_percent, 6),
            "auto_matches_best": selected_mode == best_fixed_mode,
            "auto_within_one_percent": gap_percent <= 1.0,
            "first_queued_window": first_queued["index"] if first_queued else None,
        }
        report["workloads"].append(item)
        write_reports(output_dir, report)
        print(
            f"{workload.name}: best={best_fixed_mode}/{best_fixed_cycles} "
            f"selected={selected_mode}/{selected_fixed_cycles} gap={gap_percent:.3f}% "
            f"runtime={selected_runtime_cycles}"
        )

    items = report["workloads"]
    recommendation_counts = Counter(
        item["auto_recommended_mode"] for item in items if item["auto_recommended_mode"] is not None
    )
    best_counts = Counter(item["best_fixed_mode"] for item in items)
    gaps = [item["auto_gap_percent"] for item in items]
    report["aggregate"] = {
        "workload_count": len(items),
        "best_fixed_mode_histogram": {name: best_counts[name] for name in MODE_NAMES.values()},
        "auto_recommendation_histogram": {
            name: recommendation_counts[name] for name in MODE_NAMES.values()
        },
        "no_recommendation_count": sum(
            item["auto_recommended_mode"] is None for item in items
        ),
        "auto_matches_best_count": sum(item["auto_matches_best"] for item in items),
        "auto_within_one_percent_count": sum(item["auto_within_one_percent"] for item in items),
        "mean_auto_gap_percent": round(sum(gaps) / len(gaps), 6),
        "max_auto_gap_percent": round(max(gaps), 6),
        "all_fixed_frame_hashes_equal_per_workload": all(
            item["fixed_hash_equal"] for item in items
        ),
        "all_auto_rgb_t_equal": all(
            item["auto"]["auto"]["image_mismatches"] == 0 for item in items
        ),
    }
    report["result"] = "PASS"
    report["interpretation"] = (
        "Each workload is rendered in fixed G/P/R/E modes and in a two-frame automatic probe. "
        "Fixed-mode frame states must be byte-identical; automatic RGB/T equality is checked inside RTL."
    )
    write_reports(output_dir, report)
    print(json.dumps(report["aggregate"], indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
