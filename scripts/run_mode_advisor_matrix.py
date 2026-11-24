from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
from datetime import datetime
from pathlib import Path


MATRIX_RE = re.compile(
    r"ADVISOR_MATRIX class=(G|P|R|E|BALANCED) active=(\d+) winner=(\d+) "
    r"recommended=(\d+) valid=(\d+) window=(\d+) group=(\d+) sort=(\d+) "
    r"projection=(\d+) raster=(\d+) block=(\d+) skip=(\d+)"
)
EXPECTED = {
    "G": {"winner": 0, "valid": 1},
    "P": {"winner": 1, "valid": 1},
    "R": {"winner": 2, "valid": 1},
    "E": {"winner": 3, "valid": 1},
    "BALANCED": {"winner": 0, "valid": 0},
}
FIELDS = (
    "class", "active", "winner", "recommended", "valid", "window",
    "group", "sort", "projection", "raster", "block", "skip",
)


def run(command: list[str], root: Path) -> str:
    result = subprocess.run(command, cwd=root, text=True, capture_output=True, check=False)
    output = result.stdout + result.stderr
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command)}\n{output}")
    return output


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run the deterministic long-window G/P/R/E advisor calibration matrix"
    )
    parser.add_argument(
        "--output-dir", type=Path,
        default=Path("experiments/mode_advisor_matrix/validation_latest"),
    )
    parser.add_argument(
        "--iverilog-root", type=Path, default=Path(r"D:\IcarusVerilog\iverilog")
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    output_dir = args.output_dir if args.output_dir.is_absolute() else root / args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    executable = output_dir / "tb_gaussian_mode_advisor_workload_matrix.vvp"
    iverilog = args.iverilog_root / "bin" / "iverilog.exe"
    vvp = args.iverilog_root / "bin" / "vvp.exe"

    run([
        str(iverilog), "-g2012", "-DSYNTHESIS", "-Wall",
        "-s", "tb_gaussian_mode_advisor_workload_matrix", "-o", str(executable),
        str(root / "rtl/control/gaussian_mode_advisor.sv"),
        str(root / "verification/rtl/tb_gaussian_mode_advisor_workload_matrix.sv"),
    ], root)
    log = run([str(vvp), str(executable)], root)
    (output_dir / "iverilog.log").write_text(log, encoding="utf-8")

    rows: list[dict[str, int | str]] = []
    for match in MATRIX_RE.finditer(log):
        values: dict[str, int | str] = {"class": match.group(1)}
        for field, raw in zip(FIELDS[1:], match.groups()[1:]):
            values[field] = int(raw)
        rows.append(values)

    if {row["class"] for row in rows} != set(EXPECTED):
        raise RuntimeError(f"incomplete matrix rows: {rows}")
    for row in rows:
        expected = EXPECTED[str(row["class"])]
        if row["winner"] != expected["winner"] or row["valid"] != expected["valid"]:
            raise RuntimeError(f"policy mismatch: {row}")
        if row["valid"] and row["recommended"] != row["winner"]:
            raise RuntimeError(f"recommendation/winner mismatch: {row}")

    with (output_dir / "advisor_matrix.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    report = {
        "report_version": 1,
        "generated_at": datetime.now().astimezone().isoformat(),
        "simulator": "Icarus Verilog 12",
        "window_cycles": 64,
        "observed_windows_per_class": 3,
        "hysteresis_windows": 2,
        "minimum_residence_windows": 1,
        "score_margin": 4,
        "mode_encoding": {"G": 0, "P": 1, "R": 2, "E": 3},
        "rows": rows,
        "result": "PASS",
        "interpretation": (
            "Synthetic event-boundary calibration only. System-top tests separately prove that "
            "the same counters are sourced from the real Gaussian pipeline and readable through APB."
        ),
    }
    (output_dir / "advisor_matrix.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
