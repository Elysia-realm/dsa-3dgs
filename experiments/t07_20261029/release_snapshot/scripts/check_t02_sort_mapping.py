"""Bounded sorter-only mapping: old/default/candidate, not chip PPA or STA."""
import json
import sys
from pathlib import Path
from asic.scripts.run_t01_synthesis import run_yosys, quote, sha256_file

root = Path(__file__).resolve().parents[1]
out = root / "experiments/t02_20261003/sorter_mapping"
out.mkdir(exist_ok=True)
yosys = root / "tmp/toolchains/oss-cad-suite-20260706/oss-cad-suite/bin/yosys.exe"
lib = root / "tmp/toolchains/freepdk45/NangateOpenCellLibrary_typical.lib"
results = []
for tag, source, enabled in [
    ("before", "experiments/t02_20261003/source_before/rtl/sort/stable_group_sorter_shared_compare.sv", None),
    ("linear", "rtl/sort/stable_group_sorter_shared_compare.sv", 0),
    ("binary", "rtl/sort/stable_group_sorter_shared_compare.sv", 1),
]:
    stat = out / f"{tag}.json"
    script = out / f"{tag}.ys"
    commands = [f"read_verilog -sv -DSYNTHESIS {quote(root/source)}"]
    if enabled is not None:
        commands += [f"chparam -set ENABLE_BINARY_SEARCH {enabled} stable_group_sorter_shared_compare"]
    commands += ["synth -top stable_group_sorter_shared_compare -nofsm",
                 f"read_liberty -lib {quote(lib)}",
                 f"dfflibmap -liberty {quote(lib)}", f"abc -liberty {quote(lib)}", "clean", "check -assert",
                 f"tee -o {quote(stat)} stat -json -liberty {quote(lib)} -top stable_group_sorter_shared_compare",
                 f"write_verilog -noattr -noexpr {quote(out / (tag+'.v'))}"]
    if "--report-only" not in sys.argv:
        script.write_text("\n".join(commands)+"\n")
        code, elapsed = run_yosys(yosys, script, out / f"{tag}.log", root)
    else:
        code, elapsed = 0, None
    if code: raise RuntimeError(tag)
    data = json.loads(stat.read_text())
    m = data["design"]
    results.append(dict(variant=tag, area_um2=m["area"], cell_count=m["num_cells"],
                        cell_types=m["num_cells_by_type"], source_sha256=sha256_file(root/source), seconds=elapsed))
    print(tag, results[-1]["area_um2"], flush=True)
report = dict(scope="isolated sorter CAPACITY=8, default key/payload widths, external shared comparator excluded",
              library_sha256=sha256_file(lib), sta_executed=False, chip_ppa_signoff=False,
              disabled_candidate_same_cell_histogram=results[0]["cell_types"] == results[1]["cell_types"],
              disabled_candidate_area_delta_um2=results[1]["area_um2"]-results[0]["area_um2"],
              candidate_area_delta_um2=results[2]["area_um2"]-results[1]["area_um2"],
              results=results)
(out / "report.json").write_text(json.dumps(report, indent=2)+"\n")
