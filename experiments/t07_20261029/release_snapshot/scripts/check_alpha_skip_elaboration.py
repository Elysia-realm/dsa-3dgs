"""Count reachable elaborated AST operators; these are NOT mapped ASIC cells."""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

if __package__:
    from .check_shared_pe_elaboration import count_instances, nodes
    from .run_shared_pe_validation import sha256
else:
    from check_shared_pe_elaboration import count_instances, nodes
    from run_shared_pe_validation import sha256


def inspect(path: Path) -> dict:
    tree = json.loads(path.read_text(encoding="utf-8"))
    modules = {m["addr"]: m for m in tree["modulesp"] if m["type"] == "MODULE"}
    counts = Counter()

    def visit(module):
        for node in nodes(module.get("stmtsp", [])):
            counts[node.get("type")] += 1
            if node.get("type") == "CELL":
                visit(modules[node["modp"]])

    visit(next(m for m in modules.values() if m["name"] == "gs_accel_system_top"))
    instances = count_instances(tree)
    return {"tree_sha256": sha256(path),
            "signed_multiply_ast_nodes": counts["MULS"], "unsigned_multiply_ast_nodes": counts["MUL"],
            "shared_pe_instances": instances["shared_reconfigurable_pe_slice"],
            "shape_reject_instances": instances["gaussian_shape_block_reject"]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for variant in ("default", "alpha", "combined"):
        parser.add_argument(f"--{variant}", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    records = {name: inspect(getattr(args, name)) for name in ("default", "alpha", "combined")}
    default, alpha, combined = (records[name] for name in ("default", "alpha", "combined"))
    for field in ("signed_multiply_ast_nodes", "unsigned_multiply_ast_nodes"):
        if alpha[field] != default[field]:
            raise ValueError("alpha skip unexpectedly changed multiply AST count")
    if combined["signed_multiply_ast_nodes"] != alpha["signed_multiply_ast_nodes"] + 1:
        raise ValueError("combined shape multiplier AST delta was not one")
    if combined["unsigned_multiply_ast_nodes"] != alpha["unsigned_multiply_ast_nodes"]:
        raise ValueError("combined unsigned multiply AST delta was nonzero")
    if [records[v]["shape_reject_instances"] for v in records] != [0, 0, 1]:
        raise ValueError("unexpected shape generate resources")
    if any(r["shared_pe_instances"] != 1 for r in records.values()):
        raise ValueError("unexpected shared PE instance count")
    root = Path(__file__).resolve().parents[1]
    sources = (root / "verification/rtl/system_top_sources.f").read_text().splitlines()
    source_hashes = {s: sha256(root / s) for s in sources if s.strip()}
    source_hashes.update({p.relative_to(root).as_posix(): sha256(p) for p in (root / "rtl").rglob("*.svh")})
    report = {"elaboration_pass": True, "ppa_signed_off": False, "source_sha256": source_hashes,
              "scope": "Default system parameters; reachable instance-weighted elaborated AST. Includes function bodies and constant arithmetic; counts are not physical multiplier/cell counts.",
              "variants": records}
    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(records, indent=2))


if __name__ == "__main__":
    main()
