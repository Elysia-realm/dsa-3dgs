#!/usr/bin/env python3
"""Reproducible T01 synthesis and first target-library mapping.

The production source list is used verbatim except that the inferred image
state cache implementation is replaced by a documented T01 black-box boundary.
Its storage and omitted control cost are reported separately and remain T11
work; no unknown cell is silently included as zero area.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


TOP = "gs_accel_system_top"
FORMAL_FILELIST = Path("verification/rtl/system_top_sources.f")
MEMORY_SOURCE = "rtl/raster/image_state_cache_backend.sv"
MEMORY_STUB = "asic/stubs/image_state_cache_backend_blackbox.sv"
MEMORY_BLACKBOX_TYPE = "image_state_cache_backend"


def yosys_path(path: Path) -> str:
    return path.resolve().as_posix()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def source_files(root: Path) -> tuple[list[Path], list[dict[str, str]]]:
    paths: list[Path] = []
    substitutions: list[dict[str, str]] = []
    for line in (root / FORMAL_FILELIST).read_text(encoding="utf-8-sig").splitlines():
        item = line.strip()
        if not item or item.startswith("#"):
            continue
        effective = MEMORY_STUB if item == MEMORY_SOURCE else item
        if effective != item:
            substitutions.append({"formal_source": item, "effective_source": effective})
        path = root / effective
        if not path.is_file():
            raise FileNotFoundError(path)
        paths.append(path)
    return paths, substitutions


def source_digest(paths: list[Path], variant: str) -> str:
    digest = hashlib.sha256()
    digest.update(f"{TOP}\0{variant}\0".encode())
    for path in paths:
        digest.update(path.as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest().upper()


def tool_environment(yosys: Path) -> dict[str, str]:
    env = os.environ.copy()
    bin_dir = yosys.resolve().parent
    suite_root = bin_dir.parent
    lib_dir = suite_root / "lib"
    env["YOSYSHQ_ROOT"] = str(suite_root) + os.sep
    env["PATH"] = os.pathsep.join([str(bin_dir), str(lib_dir), env.get("PATH", "")])
    return env


def run_yosys(yosys: Path, script: Path, log: Path, root: Path) -> tuple[int, float]:
    started = time.monotonic()
    with log.open("w", encoding="utf-8", errors="replace") as stream:
        result = subprocess.run(
            [str(yosys.resolve()), "-s", str(script.resolve())],
            cwd=root,
            env=tool_environment(yosys),
            stdout=stream,
            stderr=subprocess.STDOUT,
            check=False,
        )
    return result.returncode, time.monotonic() - started


def quote(path: Path) -> str:
    return f'"{yosys_path(path)}"'


def write_generic_script(
    root: Path, paths: list[Path], variant: str, output: Path, stats: Path, script: Path
) -> None:
    alpha = 1 if variant == "alpha_only" else 0
    commands = [
        "read_verilog -sv -DSYNTHESIS -I{} {}".format(
            yosys_path(root / "rtl/raster"), " ".join(quote(path) for path in paths)
        ),
        f"chparam -set ENABLE_ALPHA_ZERO_SKIP {alpha} {TOP}",
        f"hierarchy -check -top {TOP}",
        # Hierarchy is retained because full flattening makes the wide iterative
        # divider/sqrt registers prohibitively slow to optimize in Yosys.
        f"synth -top {TOP} -nofsm -run begin:fine",
        "check",
        f"tee -o {quote(stats)} stat -json -top {TOP} -hierarchy",
        f"write_rtlil {quote(output)}",
    ]
    script.write_text("\n".join(commands) + "\n", encoding="ascii")


def write_mapping_script(
    premap: Path,
    liberty: Path,
    constraint: Path,
    abc_script: Path,
    period_ps: int,
    stats: Path,
    netlist: Path,
    script: Path,
) -> None:
    commands = [
        f"read_rtlil {quote(premap)}",
        # Coarse synthesis retains the exponential LUT ROM. Map it explicitly
        # so no generic memory cell receives zero area in the report.
        "memory_map",
        "techmap",
        "opt -fast",
        f"read_liberty -lib {quote(liberty)}",
        f"dfflibmap -liberty {quote(liberty)}",
        f"abc -script {quote(abc_script)} -liberty {quote(liberty)} "
        f"-constr {quote(constraint)} -D {period_ps}",
        "clean",
        "check",
        f"tee -o {quote(stats)} stat -json -liberty {quote(liberty)} -top {TOP} -hierarchy",
        f"stat -liberty {quote(liberty)} -top {TOP} -hierarchy",
        f"write_verilog -noattr -noexpr -nodec {quote(netlist)}",
    ]
    script.write_text("\n".join(commands) + "\n", encoding="ascii")


def write_premap_script(generic: Path, premap: Path, stats: Path, script: Path) -> None:
    commands = [
        f"read_rtlil {quote(generic)}",
        "techmap",
        "opt -fast",
        "check",
        f"tee -o {quote(stats)} stat -json -top {TOP} -hierarchy",
        f"write_rtlil {quote(premap)}",
    ]
    script.write_text("\n".join(commands) + "\n", encoding="ascii")


def liberty_cells(path: Path) -> set[str]:
    cells: set[str] = set()
    pattern = re.compile(r"^\s*cell\s*\(\s*([^\s)]+)\s*\)")
    with path.open("r", encoding="utf-8", errors="ignore") as stream:
        for line in stream:
            match = pattern.match(line)
            if match:
                cells.add(match.group(1).strip('"'))
    return cells


def parse_delays(log: Path) -> list[float]:
    text = log.read_text(encoding="utf-8", errors="replace")
    return [float(value) for value in re.findall(r"Delay\s*=\s*([0-9.]+)\s*ps", text)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--yosys", type=Path, required=True)
    parser.add_argument("--liberty", type=Path, required=True)
    parser.add_argument("--pdk", required=True)
    parser.add_argument("--corner", required=True)
    parser.add_argument("--variant", choices=("shared_baseline", "alpha_only"), required=True)
    parser.add_argument("--clock-mhz", type=float, default=200.0)
    parser.add_argument("--driver-cell", required=True)
    parser.add_argument("--output-load-ff", type=float, required=True)
    parser.add_argument("--output-root", type=Path, default=Path("asic/reports/t01/runs"))
    parser.add_argument("--force-generic", action="store_true")
    parser.add_argument("--report-only", action="store_true",
                        help="Re-read completed run artifacts without rerunning tools")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    yosys = args.yosys.resolve()
    liberty = args.liberty.resolve()
    if not yosys.is_file() or not liberty.is_file():
        parser.error("--yosys and --liberty must name existing files")
    if args.clock_mhz <= 0:
        parser.error("--clock-mhz must be positive")

    paths, substitutions = source_files(root)
    digest = source_digest(paths, args.variant)
    audit_paths = sorted(set(paths + list((root / "rtl").rglob("*.svh")) + [root / FORMAL_FILELIST]))
    source_manifest = {
        path.relative_to(root).as_posix(): sha256_file(path) for path in audit_paths
    }
    base = (root / args.output_root).resolve()
    generic_dir = base / "generic" / args.variant
    run_dir = base / args.pdk / args.corner / args.variant / f"{args.clock_mhz:g}MHz"
    generic_dir.mkdir(parents=True, exist_ok=True)
    run_dir.mkdir(parents=True, exist_ok=True)

    generic = generic_dir / "generic.il"
    generic_meta = generic_dir / "metadata.json"
    generic_stats = generic_dir / "generic_stat.json"
    generic_script = generic_dir / "synthesis.ys"
    generic_log = generic_dir / "synthesis.log"
    cache_valid = False
    if generic.is_file() and generic_meta.is_file() and not args.force_generic:
        cache = json.loads(generic_meta.read_text(encoding="utf-8"))
        cache_valid = cache.get("source_digest_sha256") == digest
        cache_valid = cache_valid and cache.get("generic_rtlil_sha256") == sha256_file(generic)
        if "source_manifest" in cache:
            cache_valid = cache_valid and cache["source_manifest"] == source_manifest
        else:
            # Existing breakpoint predates the include-file manifest. Refuse
            # reuse if any dependency was edited after that synthesis.
            cache_valid = cache_valid and all(p.stat().st_mtime_ns <= generic.stat().st_mtime_ns for p in audit_paths)

    synthesis_seconds = 0.0
    if args.report_only and not cache_valid:
        parser.error("report-only requires a matching generic source cache")
    if not cache_valid:
        write_generic_script(root, paths, args.variant, generic, generic_stats, generic_script)
        code, synthesis_seconds = run_yosys(yosys, generic_script, generic_log, root)
        if code:
            print(f"generic synthesis failed; see {generic_log}", file=sys.stderr)
            return code
        generic_meta.write_text(
            json.dumps(
                {
                    "top": TOP,
                    "variant": args.variant,
                    "source_digest_sha256": digest,
                    "source_manifest": source_manifest,
                    "formal_filelist": FORMAL_FILELIST.as_posix(),
                    "substitutions": substitutions,
                    "generic_rtlil_sha256": sha256_file(generic),
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )

    premap = generic_dir / "premap.il"
    premap_stats = generic_dir / "premap_stat.json"
    premap_script = generic_dir / "premap.ys"
    premap_log = generic_dir / "premap.log"
    premap_seconds = 0.0
    if not args.report_only and (not premap.is_file() or not cache_valid or args.force_generic):
        write_premap_script(generic, premap, premap_stats, premap_script)
        code, premap_seconds = run_yosys(yosys, premap_script, premap_log, root)
        if code:
            print(f"technology-independent premap failed; see {premap_log}", file=sys.stderr)
            return code

    period_ps = round(1_000_000.0 / args.clock_mhz)
    constraint = run_dir / "abc.constr"
    if not args.report_only: constraint.write_text(
        f"set_driving_cell {args.driver_cell}\nset_load {args.output_load_ff:g}\n",
        encoding="ascii",
    )
    # T01 needs early design feedback.  This bounded script avoids the much
    # slower iterative &fraig/&nf flow; final T12 can spend more effort after
    # the RTL and memory architecture are frozen.
    abc_script = run_dir / "abc_fast.script"
    if not args.report_only: abc_script.write_text(
        "\n".join(
            [
                "strash",
                "dc2",
                "map",
                # ABC map can retain dangling nodes that buffer rejects.
                "cleanup",
                "buffer",
                f"upsize -D {period_ps}",
                f"dnsize -D {period_ps}",
                "stime -p",
            ]
        )
        + "\n",
        encoding="ascii",
    )
    mapping_script = run_dir / "mapping.ys"
    mapping_log = run_dir / "mapping.log"
    mapped_stats = run_dir / "mapped_stat.json"
    netlist = run_dir / "gs_accel_system_top_mapped.v"
    summary_file = run_dir / "summary.json"
    prior_runtime = {}
    if args.report_only and summary_file.is_file():
        prior_runtime = json.loads(summary_file.read_text(encoding="utf-8")).get("runtime_seconds", {})
    if not args.report_only and summary_file.exists():
        summary_file.unlink()
    if not args.report_only: write_mapping_script(
        premap,
        liberty,
        constraint,
        abc_script,
        period_ps,
        mapped_stats,
        netlist,
        mapping_script,
    )
    code, mapping_seconds = (0, 0.0) if args.report_only else run_yosys(yosys, mapping_script, mapping_log, root)
    if code:
        print(f"mapping failed; see {mapping_log}", file=sys.stderr)
        return code

    recovery_log = run_dir / "rom_mapping.log"
    recovery_used = recovery_log.exists() and recovery_log.stat().st_mtime_ns > mapping_log.stat().st_mtime_ns
    for completed_log in [mapping_log] + ([recovery_log] if recovery_used else []):
        if "End of script." not in completed_log.read_text(encoding="utf-8", errors="replace"):
            raise RuntimeError(f"Incomplete run log: {completed_log}")

    stats = json.loads(mapped_stats.read_text(encoding="utf-8"))
    design = stats.get("design", stats.get("modules", {}).get("design", {}))
    def metric(value, key="count"):
        return float(value[key]) if isinstance(value, dict) else value
    cell_counts = {
        name: int(metric(value))
        for name, value in design.get("num_cells_by_type", {}).items()
    }
    known = liberty_cells(liberty)
    def is_memory_blackbox(cell_type: str) -> bool:
        return cell_type == MEMORY_BLACKBOX_TYPE or cell_type.endswith(
            "\\" + MEMORY_BLACKBOX_TYPE
        )

    unknown = {
        cell_type: count
        for cell_type, count in cell_counts.items()
        if cell_type not in known and not is_memory_blackbox(cell_type)
    }
    memory_blackboxes = {
        name: count for name, count in cell_counts.items() if is_memory_blackbox(name)
    }
    delays = parse_delays(mapping_log)
    if recovery_used:
        delays += parse_delays(recovery_log)
    area_um2 = design.get("area", metric(design.get("num_cells"), "area") if isinstance(design.get("num_cells"), dict) else None)
    area_mm2 = area_um2 / 1_000_000.0 if isinstance(area_um2, (int, float)) else None
    if not design or area_mm2 is None or area_mm2 <= 0 or not delays:
        raise RuntimeError("Missing mapped area/design or ABC timing evidence")
    summary = {
        "schema_version": 1,
        "task": "T01",
        "status": "MAPPED_WITH_MEMORY_ABSTRACTION_STA_PENDING" if not unknown else "INCOMPLETE_UNKNOWN_CELLS",
        "top": TOP,
        "variant": args.variant,
        "pdk": args.pdk,
        "corner": args.corner,
        "clock_mhz": args.clock_mhz,
        "period_ps": period_ps,
        "tool": {
            "yosys_path": str(yosys),
            "yosys_version": stats.get("creator"),
        },
        "library": {
            "path": str(liberty),
            "sha256": sha256_file(liberty),
            "cell_types": len(known),
            "driver_cell": args.driver_cell,
            "output_load_ff": args.output_load_ff,
        },
        "source_digest_sha256": digest,
        "source_manifest": source_manifest,
        "formal_filelist": FORMAL_FILELIST.as_posix(),
        "source_substitutions": substitutions,
        "mapped": {
            "cell_count": metric(design.get("num_cells")),
            "standard_cell_area_um2": area_um2,
            "standard_cell_area_mm2": area_mm2,
            "sequential_area_um2": metric(design.get("sequential_area"), "area"),
            "unknown_cell_types": unknown,
            "explicit_non_library_cells": memory_blackboxes,
            "netlist": str(netlist.relative_to(root)),
            "netlist_sha256": sha256_file(netlist),
        },
        "timing": {
            "method": "ABC fast-map NLDM module-local combinational timing proxy; not SDC-aware top-level STA",
            "module_delay_samples": len(delays),
            "worst_module_delay_ps": max(delays) if delays else None,
            "target_period_ps": period_ps,
            "proxy_meets_target": bool(delays) and max(delays) <= period_ps,
        },
        "memory_abstraction": {
            "module": MEMORY_BLACKBOX_TYPE,
            "entries": 4096,
            "estimated_array_bits_excluding_control": 4096 * (32 + 16 + 13 * 3 + 16 + 1),
            "estimated_array_kib": 4096 * (32 + 16 + 13 * 3 + 16 + 1) / 8 / 1024,
            "area_included": False,
            "control_area_included": False,
            "final_owner": "T11",
        },
        "artifacts": {
            "generic_rtlil": str(generic.relative_to(root)),
            "premap_rtlil": str(premap.relative_to(root)),
            "generic_stats": str(generic_stats.relative_to(root)),
            "premap_stats": str(premap_stats.relative_to(root)),
            "synthesis_script": str(generic_script.relative_to(root)),
            "synthesis_log": str(generic_log.relative_to(root)),
            "premap_script": str(premap_script.relative_to(root)),
            "premap_log": str(premap_log.relative_to(root)),
            "mapping_script": str(mapping_script.relative_to(root)),
            "mapping_log": str(mapping_log.relative_to(root)),
            "mapped_stats": str(mapped_stats.relative_to(root)),
            "rom_recovery_log": str(recovery_log.relative_to(root)) if recovery_used else None,
        },
        "runtime_seconds": {
            "generic_synthesis": synthesis_seconds,
            "technology_independent_premap": premap_seconds,
            "mapping": mapping_seconds,
            "generic_cache_reused": cache_valid,
        },
    }
    if args.report_only and prior_runtime:
        summary["runtime_seconds"] = prior_runtime
    summary_file.write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8"
    )
    cache = json.loads(generic_meta.read_text(encoding="utf-8"))
    cache["source_manifest"] = source_manifest
    generic_meta.write_text(json.dumps(cache, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0 if not unknown else 2


if __name__ == "__main__":
    raise SystemExit(main())
