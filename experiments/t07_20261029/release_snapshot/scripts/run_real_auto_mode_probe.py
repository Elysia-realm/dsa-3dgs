from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import subprocess
from collections import Counter
from datetime import datetime
from pathlib import Path


WINDOW_RE = re.compile(
    r"REAL_ADVISOR_WINDOW index=(\d+) active=(\d+) winner=(\d+) queued_valid=(\d+) "
    r"queued_mode=(\d+) group=(\d+) sort=(\d+) projection=(\d+) raster=(\d+) "
    r"block=(\d+) skip=(\d+)"
)
AUTO_RE = re.compile(
    r"REAL_AUTO observe_mode=(\d+) observe_cycles=(\d+) recommendation_valid=(\d+) "
    r"recommended_mode=(\d+) window_winner=(\d+) observe_windows=(\d+) "
    r"total_windows=(\d+) selected_mode=(\d+) selected_cycles=(\d+) image_mismatches=(\d+)"
)
PERF_RE = re.compile(
    r"REAL_PERF cycles=(\d+) commits=(\d+) state_misses=(\d+) read_stall=(\d+) "
    r"output_stall=(\d+) state_reads=(\d+) state_writes=(\d+)"
)
WINDOW_FIELDS = (
    "index", "active", "winner", "queued_valid", "queued_mode", "group", "sort",
    "projection", "raster", "block", "skip",
)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run one real workload twice to observe and safely apply an automatic G/P/R/E recommendation"
    )
    parser.add_argument("batch", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--executable", type=Path,
        default=Path("tmp/verilator_bonsai1024_range_obj/tb_bonsai1024_range.exe"),
    )
    parser.add_argument("--initial-mode", type=int, choices=(0, 1, 2, 3), default=3)
    parser.add_argument("--max-timeout", type=int, default=4_000_000)
    parser.add_argument("--msys2-root", type=Path, default=Path(r"D:\Tools\msys64"))
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    batch = args.batch if args.batch.is_absolute() else (root / args.batch)
    output_dir = args.output_dir if args.output_dir.is_absolute() else (root / args.output_dir)
    executable = args.executable if args.executable.is_absolute() else (root / args.executable)
    sparse_attribute = batch / "attribute_sparse.memh"
    dense_attribute = batch / "attribute.memh"
    global_gid = batch / "global_gid.memh"
    if sparse_attribute.exists() and global_gid.exists():
        attribute = sparse_attribute
        global_gid_arg = f"+GLOBAL_GIDS={global_gid}"
        attribute_layout = "sparse_global_gid"
    elif dense_attribute.exists():
        attribute = dense_attribute
        global_gid_arg = None
        attribute_layout = "dense_frame_local_gid"
    else:
        raise FileNotFoundError(
            f"expected dense attribute.memh or sparse attribute_sparse.memh/global_gid.memh in {batch}"
        )
    for path in (executable, batch / "mean.memh", attribute, batch / "camera.memh"):
        if not path.exists():
            raise FileNotFoundError(path)

    output_dir.mkdir(parents=True, exist_ok=True)
    frame = output_dir / "frame_state.memh"
    command = [
        str(executable), f"+MEAN={batch / 'mean.memh'}",
        f"+ATTR={attribute}", f"+CAMERA={batch / 'camera.memh'}",
        f"+FRAME={frame}", "+LABEL=real_auto_mode_probe", "+AUTO_MODE",
        "+AUTO_REPEAT_FRAMES=2", f"+FRAME_MODE={args.initial_mode}",
        f"+MAX_TIMEOUT={args.max_timeout}",
    ]
    if global_gid_arg is not None:
        command.append(global_gid_arg)
    run_env = os.environ.copy()
    ucrt64_bin = args.msys2_root / "ucrt64" / "bin"
    if ucrt64_bin.is_dir():
        run_env["PATH"] = str(ucrt64_bin.resolve()) + os.pathsep + run_env.get("PATH", "")
    result = subprocess.run(
        command, cwd=root, text=True, capture_output=True, check=False, env=run_env
    )
    log = result.stdout + result.stderr
    (output_dir / "verilator.log").write_text(log, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"real automatic-mode probe failed ({result.returncode})\n{log[-8000:]}")

    windows = [
        {field: int(value) for field, value in zip(WINDOW_FIELDS, match.groups())}
        for match in WINDOW_RE.finditer(log)
    ]
    auto_match = AUTO_RE.search(log)
    perf_match = PERF_RE.search(log)
    if not windows or auto_match is None or perf_match is None or "PASS: tb_real_dma_workload" not in log:
        raise RuntimeError("probe log is missing structured advisor/performance records")

    auto_keys = (
        "observe_mode", "observe_cycles", "recommendation_valid", "recommended_mode",
        "window_winner", "observe_windows", "total_windows", "selected_mode",
        "selected_cycles", "image_mismatches",
    )
    auto = {key: int(value) for key, value in zip(auto_keys, auto_match.groups())}
    if auto["recommendation_valid"] and auto["selected_mode"] != auto["recommended_mode"]:
        raise RuntimeError(f"recommendation was not selected: {auto}")
    if auto["image_mismatches"]:
        raise RuntimeError(f"automatic selection changed rendered RGB/T: {auto}")

    perf_keys = (
        "cycles", "commits", "state_misses", "read_stall", "output_stall",
        "state_reads", "state_writes",
    )
    selected_perf = {key: int(value) for key, value in zip(perf_keys, perf_match.groups())}
    with (output_dir / "advisor_windows.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=WINDOW_FIELDS)
        writer.writeheader()
        writer.writerows(windows)

    if auto["total_windows"] != len(windows):
        raise RuntimeError(f"window trace count does not match RTL summary: {auto}")
    if not 0 < auto["observe_windows"] <= len(windows):
        raise RuntimeError(f"invalid observe-frame window count: {auto}")
    observe_windows = windows[:auto["observe_windows"]]
    selected_windows = windows[auto["observe_windows"]:]

    def winner_histogram(rows: list[dict[str, int]]) -> dict[str, int]:
        counts = Counter(row["winner"] for row in rows)
        return {str(mode): counts[mode] for mode in range(4)}

    first_queued = next((row for row in observe_windows if row["queued_valid"]), None)
    cycle_savings = auto["observe_cycles"] - auto["selected_cycles"]
    cycle_reduction_percent = (
        100.0 * cycle_savings / auto["observe_cycles"] if auto["observe_cycles"] else 0.0
    )
    report = {
        "report_version": 2,
        "generated_at": datetime.now().astimezone().isoformat(),
        "batch": str(batch.resolve()),
        "attribute_layout": attribute_layout,
        "executable": str(executable.resolve()),
        "initial_mode": args.initial_mode,
        "auto": auto,
        "mode_names": {"0": "G", "1": "P", "2": "R", "3": "E"},
        "selected_vs_observe": {
            "cycle_savings": cycle_savings,
            "cycle_reduction_percent": round(cycle_reduction_percent, 6),
        },
        "selected_frame_perf": selected_perf,
        "window_count": len(windows),
        "winner_histogram": {
            "observe_frame": winner_histogram(observe_windows),
            "selected_frame": winner_histogram(selected_windows),
            "all": winner_histogram(windows),
        },
        "first_queued_window": first_queued,
        "frame_sha256": hashlib.sha256(frame.read_bytes()).hexdigest().upper(),
        "result": "PASS",
        "interpretation": (
            "The first real frame observes the workload; the recommendation, when valid, is applied only "
            "at the next new epoch. RGB/T equality is checked inside the RTL testbench across both frames."
        ),
    }
    (output_dir / "report.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
