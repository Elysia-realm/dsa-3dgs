from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path


def nodes(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from nodes(child)


def count_instances(tree: dict) -> Counter:
    modules = {module["addr"]: module for module in tree["modulesp"] if module["type"] == "MODULE"}
    top = next(module for module in modules.values() if module["name"] == "gs_accel_system_top")
    result = Counter()

    def visit(module):
        result[module["origName"]] += 1
        for node in nodes(module.get("stmtsp", [])):
            if node.get("type") == "CELL":
                visit(modules[node["modp"]])

    visit(top)
    return result


def main():
    parser = argparse.ArgumentParser(description="Check elaborated generate branches; NOT synthesis/PPA")
    parser.add_argument("--shared", required=True, type=Path)
    parser.add_argument("--bypass", required=True, type=Path)
    parser.add_argument("--parallel", type=Path)
    parser.add_argument("--streaming", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    shared = count_instances(json.loads(args.shared.read_text(encoding="utf-8")))
    bypass = count_instances(json.loads(args.bypass.read_text(encoding="utf-8")))
    if shared["world_to_camera_core"] != 0 or shared["world_to_camera_shared_mac"] != 1:
        raise RuntimeError("main mean transform was not physically replaced in elaborated hierarchy")
    if bypass["world_to_camera_core"] != 4 or bypass["world_to_camera_shared_mac"] != 0:
        raise RuntimeError("four-lane bypass hierarchy does not match expected local mean transforms")
    if shared["shared_reconfigurable_pe_slice"] != 1:
        raise RuntimeError("production hierarchy must use exactly one shared PE")
    report = {
        "elaboration_pass": True, "synthesis_or_ppa_signoff": False,
        "shared_instances": dict(shared), "bypass_instances": dict(bypass),
        "removed_main_mean_multiplier_operators": 4 * 9,
        "scope": "default four-lane system hierarchy, main XYZ transform only; not area/power savings",
    }
    if args.parallel:
        parallel = count_instances(json.loads(args.parallel.read_text(encoding="utf-8")))
        if parallel["stable_group_sorter_parallel_shared"] != 1 or parallel["stable_group_sorter_shared_compare"] != 0:
            raise RuntimeError("parallel candidate hierarchy does not replace the serial sorter")
        if parallel["shared_reconfigurable_pe_slice"] != 1 or parallel["world_to_camera_core"] != 0:
            raise RuntimeError("parallel candidate must retain main shared P and one shared PE")
        if shared["stable_group_sorter_parallel_shared"] != 0:
            raise RuntimeError("parallel candidate unexpectedly enabled in default hierarchy")
        report["parallel_instances"] = dict(parallel)
        report["parallel_sort_candidate_elaboration_pass"] = True
    if args.streaming:
        streaming = count_instances(json.loads(args.streaming.read_text(encoding="utf-8")))
        if streaming["gaussian_depth_prepass_core"] != 1 or streaming["gaussian_depth_prepass_shared_mac"] != 0:
            raise RuntimeError("streaming candidate must replace only the shared depth prepass")
        if streaming["shared_reconfigurable_pe_slice"] != 1 or streaming["world_to_camera_shared_mac"] != 1:
            raise RuntimeError("streaming candidate must retain the shared G/main-P slice")
        if shared["gaussian_depth_prepass_core"] != 0 or shared["gaussian_depth_prepass_shared_mac"] != 1:
            raise RuntimeError("default hierarchy must retain the area-oriented shared depth prepass")
        report["streaming_instances"] = dict(streaming)
        report["streaming_depth_prepass_candidate_elaboration_pass"] = True
        report["streaming_depth_prepass_restored_multiplier_operators"] = 3
    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({key: shared[key] for key in (
        "world_to_camera_core", "world_to_camera_shared_mac", "shared_reconfigurable_pe_slice")}, indent=2))


if __name__ == "__main__":
    main()
