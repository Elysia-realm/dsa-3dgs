#!/usr/bin/env python3
"""Verify the four T01 mapping results still match their source/lib/netlist."""
import json
from pathlib import Path
from run_t01_synthesis import sha256_file

root = Path(__file__).resolve().parents[2]
out = root / "asic/reports/t01"
paths = sorted((out / "runs").glob("*/*/*/*/summary.json"))
assert len(paths) == 4, f"Expected two PDKs x two configurations; found {len(paths)}"
checks = []
for path in paths:
    s = json.loads(path.read_text())
    assert s["status"] == "MAPPED_WITH_MEMORY_ABSTRACTION_STA_PENDING", path
    assert not s["mapped"]["unknown_cell_types"], path
    assert s["mapped"]["explicit_non_library_cells"] == {"image_state_cache_backend": 1}, path
    assert sha256_file(root / s["mapped"]["netlist"]) == s["mapped"]["netlist_sha256"], path
    assert sha256_file(Path(s["library"]["path"])) == s["library"]["sha256"], path
    assert s.get("source_manifest"), path
    for rel, digest in s["source_manifest"].items():
        assert sha256_file(root / rel) == digest, rel
    for key in ["synthesis_log", "premap_log", "mapping_log", "rom_recovery_log"]:
        rel = s["artifacts"].get(key)
        if rel:
            assert "End of script." in (root / rel).read_text(errors="replace"), rel
    checks.append(dict(pdk=s["pdk"], variant=s["variant"], integrity="PASS", area_um2=s["mapped"]["standard_cell_area_um2"], sta="NOT_EXECUTED"))
for pdk in {c["pdk"] for c in checks}:
    pair = [json.loads(p.read_text()) for p in paths if json.loads(p.read_text())["pdk"] == pdk]
    assert {s["variant"] for s in pair} == {"shared_baseline", "alpha_only"}
    for key in ["source_manifest", "library", "clock_mhz", "memory_abstraction"]:
        assert pair[0][key] == pair[1][key], (pdk, key)
assert "PASS: tb_covariance2d_cholesky_encoder" in (out / "validation/encoder_run.log").read_text()
status = json.loads((root / "verification/implementation_status.json").read_text(encoding="utf-8"))
assert not status["t01_signed_off"] and not status["ppa_signed_off"] and not status["t01_sta_executed"]
result = dict(status="PASS", scope="Artifact integrity and same-condition mapping; not STA or PPA signoff", runs=checks)
(out / "validation/evidence_audit.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, indent=2))
