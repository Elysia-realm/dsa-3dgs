"""Same accepted deterministic stream, actual shared PE/backend, on/off ablation."""
import argparse
import json
import subprocess
from pathlib import Path

from scripts.run_shared_pe_validation import parse_record, sha256


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    args.output.mkdir(parents=True, exist_ok=False)
    source_sets = {
        "XYZ": ["rtl/common/rv_reg_slice.sv", "rtl/projection/world_to_camera_core.sv",
                "rtl/projection/world_to_camera_shared_mac.sv", "rtl/control/shared_reconfigurable_pe_slice.sv",
                "verification/rtl/tb_world_to_camera_shared_mac.sv"],
        "ATTR": ["rtl/sort/ordered_gaussian_attribute_issue.sv", "verification/rtl/tb_attribute_issue_turnover.sv"],
    }
    records = []
    for kind, sources in source_sets.items():
        for enabled, bypass in ((0, 0), (1, 0), (1, 1)):
            top = "tb_world_to_camera_shared_mac" if kind == "XYZ" else "tb_attribute_issue_turnover"
            tag = f"{kind}_{enabled}_{bypass}"
            binary = args.output / f"{tag}.vvp"
            command = [r"D:\IcarusVerilog\iverilog\bin\iverilog.exe", "-g2012", "-DSYNTHESIS",
                       f"-DTB_{kind}_TURNOVER={enabled}", f"-DTB_ATTR_RESPONSE_BYPASS={bypass}",
                       f"-DTB_XYZ_FIRST_REQUEST_BYPASS={bypass}", "-DTB_XYZ_STREAMING=1", "-s", top, "-o", str(binary), *sources]
            compiled = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=60)
            (args.output / f"{tag}_compile.log").write_text(" ".join(command)+"\n"+compiled.stdout+compiled.stderr, encoding="utf-8")
            if compiled.returncode:
                raise RuntimeError(compiled.stderr)
            simulated = subprocess.run([r"D:\IcarusVerilog\iverilog\bin\vvp.exe", str(binary)], cwd=root, capture_output=True, text=True, timeout=60)
            log = simulated.stdout+simulated.stderr
            (args.output / f"{tag}.log").write_text(log, encoding="utf-8")
            if simulated.returncode or f"PASS: {top}" not in log:
                raise RuntimeError(log)
            for line in log.splitlines():
                if line.startswith(f"{kind}_STREAM "):
                    records.append({"kind": kind, **parse_record(line, f"{kind}_STREAM")})
    report = {"functional_pass": True, "sva_executed": False, "ppa_signed_off": False,
              "source_sha256": {p: sha256(root/p) for sources in source_sets.values() for p in sources}, "records": records}
    (args.output / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(records, indent=2))


if __name__ == "__main__":
    main()
