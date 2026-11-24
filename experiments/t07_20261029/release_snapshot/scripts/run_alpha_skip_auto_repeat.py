"""Reproduce two-epoch automatic-mode evidence for the alpha no-op candidate."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

if __package__:
    from .run_shared_pe_validation import parse_record, semantic_frame_sha256, sha256
else:
    from run_shared_pe_validation import parse_record, semantic_frame_sha256, sha256


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("matrix_report", type=Path)
    parser.add_argument("workload", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--candidate", choices=("alpha_zero_skip", "shape_alpha_skip"), default="alpha_zero_skip")
    parser.add_argument("--vvp", type=Path, default=Path(r"D:\IcarusVerilog\iverilog\bin\vvp.exe"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    matrix_path = args.matrix_report.resolve()
    matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
    if not matrix["functional_pass"] or not {"shared_projection", args.candidate}.issubset(matrix["variants"]):
        raise ValueError("the matrix must contain completed shared and alpha-skip variants")
    for source, digest in matrix["source_sha256"].items():
        if sha256(root / source) != digest:
            raise ValueError(f"stale RTL evidence: {source}")
    if sha256(root / "verification/rtl/tb_real_dma_workload.sv") != matrix["testbench_sha256"]:
        raise ValueError("stale DMA testbench evidence")

    workload = args.workload.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    rows = []
    for variant in ("shared_projection", args.candidate):
        binary = matrix_path.parent / f"{variant}.vvp"
        frame = output / f"{variant}.memh"
        command = [str(args.vvp), str(binary),
                   f"+MEAN={workload / 'mean.memh'}",
                   f"+ATTR={workload / 'attribute.memh'}",
                   f"+CAMERA={workload / 'camera.memh'}",
                   f"+FRAME={frame}", "+AUTO_MODE", "+AUTO_REPEAT_FRAMES=2",
                   "+MAX_TIMEOUT=500000"]
        result = subprocess.run(command, cwd=root, text=True, capture_output=True, timeout=60)
        log = result.stdout + result.stderr
        (output / f"{variant}.log").write_text(log, encoding="utf-8")
        if result.returncode:
            raise RuntimeError(f"{variant} simulator failed; see {output / (variant + '.log')}")
        auto = parse_record(log, "REAL_AUTO")
        skip = parse_record(log, "REAL_ALPHA_SKIP")
        shape = parse_record(log, "REAL_SHAPE")
        continuation = parse_record(log, "REAL_CONTINUATION")
        if auto["image_mismatches"] or auto["recommendation_valid"] != 1:
            raise ValueError(f"{variant} automatic two-epoch image/recommendation failure")
        if skip["enabled"] != int(variant == args.candidate):
            raise ValueError(f"{variant} alpha-skip enable mismatch")
        if shape["enabled"] != int(variant == "shape_alpha_skip"):
            raise ValueError(f"{variant} shape enable mismatch")
        rows.append({"variant": variant, "binary_sha256": sha256(binary), "auto": auto,
                     "alpha_skip": skip, "shape": shape, "epoch": continuation["epoch"],
                     "frame_sha256": semantic_frame_sha256(frame, continuation["epoch"]),
                     "raw_frame_sha256": sha256(frame)})
    shared, candidate = rows
    if shared["alpha_skip"]["skipped"] != 0 or candidate["alpha_skip"]["skipped"] <= 0:
        raise ValueError("automatic mode did not exercise the alpha-skip candidate")
    if shared["frame_sha256"] != candidate["frame_sha256"]:
        raise ValueError("automatic-mode architectural RGB/T images diverged")
    report = {"source_current": True, "functional_pass": True, "ppa_signed_off": False,
              "matrix_report": matrix_path.relative_to(root).as_posix(),
              "workload": workload.relative_to(root).as_posix(),
              "selected_saved_cycles": shared["auto"]["selected_cycles"] - candidate["auto"]["selected_cycles"],
              "rows": rows}
    (output / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"functional_pass": True,
                      "selected_saved_cycles": report["selected_saved_cycles"],
                      "candidate_skipped": candidate["alpha_skip"]["skipped"],
                      "frame_sha256": candidate["frame_sha256"]}, indent=2))


if __name__ == "__main__":
    main()
