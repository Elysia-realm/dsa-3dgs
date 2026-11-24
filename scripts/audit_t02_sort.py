"""Audit the fixed T02 experiment and emit the one-shot engineering decision."""
from __future__ import annotations
import json
from pathlib import Path
from scripts.run_shared_pe_validation import sha256, semantic_frame_sha256, parse_record

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "experiments/t02_20261003"

def main():
    module = json.loads((OUT / "module/report.json").read_text())
    dma = json.loads((OUT / "dma/report.json").read_text())
    mapping = json.loads((OUT / "sorter_mapping/report.json").read_text())
    assert module["functional_pass"] and dma["functional_pass"]
    assert len(module["records"]) == 14 and len(dma["workloads"]) == 4
    for report in (module, dma):
        for rel, digest in report["source_sha256"].items():
            assert sha256(ROOT / rel) == digest, rel
    assert sha256(ROOT / "verification/rtl/tb_real_dma_workload.sv") == dma["testbench_sha256"]
    rows, inputs = [], {}
    for workload in dma["workloads"]:
        name = workload["name"]
        records = workload["records"]
        assert len(records) == 24
        assert {(r["variant"], r["mode"], r["profile"]) for r in records} == {
            (v,m,p) for v in ("bypass","shared_projection","binary_sort") for m in "GPRE" for p in ("ideal","limited")}
        for r in records:
            tag = f'{r["variant"]}_{r["mode"]}_{r["profile"]}'
            frame = OUT / "dma" / name / f"{tag}.memh"
            log = (OUT / "dma" / name / f"{tag}.log").read_text()
            assert "PASS: tb_real_dma_workload" in log
            assert sha256(frame) == r["raw_frame_sha256"]
            assert semantic_frame_sha256(frame, parse_record(log,"REAL_CONTINUATION")["epoch"]) == r["frame_sha256"]
        assert len({r["frame_sha256"] for r in records}) == 1
        for mode in "GPRE":
            for profile in ("ideal", "limited"):
                pair = {r["variant"]:r for r in records if r["mode"]==mode and r["profile"]==profile}
                b, c, bypass = pair["shared_projection"], pair["binary_sort"], pair["bypass"]
                saved = b["perf"]["cycles"]-c["perf"]["cycles"]
                rows.append(dict(workload=name, mode=mode, profile=profile, linear_cycles=b["perf"]["cycles"],
                    binary_cycles=c["perf"]["cycles"], bypass_cycles=bypass["perf"]["cycles"], saved_cycles=saved,
                    saved_percent=100*saved/b["perf"]["cycles"],
                    linear_g_grants=b["shared_pe"]["G"], binary_g_grants=c["shared_pe"]["G"],
                    linear_contention=b["shared_pe"]["competing"], binary_contention=c["shared_pe"]["competing"],
                    linear_state_reads=b["perf"]["state_reads"], binary_state_reads=c["perf"]["state_reads"],
                    linear_state_writes=b["perf"]["state_writes"], binary_state_writes=c["perf"]["state_writes"]))
        for file in ("manifest.json","mean.memh","attribute.memh","camera.memh"):
            p = ROOT / "experiments/rtl_workloads" / name / file
            inputs[p.relative_to(ROOT).as_posix()] = sha256(p)
    def aggregate(rs):
        return dict(runs=len(rs), improved=sum(r["saved_cycles"]>0 for r in rs),
                    equal=sum(r["saved_cycles"]==0 for r in rs), regressed=sum(r["saved_cycles"]<0 for r in rs),
                    mean_saved_percent=sum(r["saved_percent"] for r in rs)/len(rs),
                    min_saved_percent=min(r["saved_percent"] for r in rs), max_saved_percent=max(r["saved_percent"] for r in rs))
    agg = aggregate(rows)
    if agg["regressed"] or agg["mean_saved_percent"] < 1:
        decision = "FREEZE_DEFAULT_OFF_REJECT_PRODUCTION_ENABLE"
        reason = "System regression or low marginal gain; preserve counterexamples and stop this exploration."
    else:
        decision = "RETAIN_OPTIONAL_CANDIDATE_DEFAULT_OFF_PENDING_T05"
        reason = "Meaningful system-sample benefit, but reverse-input regression and no STA; T05 owns final resource configuration."
    # Source changed after T01: verify that the three modified production files
    # were preserved byte-for-byte, and leave all T01 evidence untouched.
    old = json.loads((ROOT / "asic/reports/t01/runs/freepdk45_nangate45/tt_1p10v_25c/shared_baseline/200MHz/summary.json").read_text())
    preserved = {}
    include_hashes = {rel:digest for rel,digest in old["source_manifest"].items() if rel.endswith(".svh")}
    for rel, digest in include_hashes.items():
        assert sha256(ROOT / rel) == digest, rel
    for rel in ("rtl/sort/stable_group_sorter_shared_compare.sv", "rtl/gs_accel_system_top.sv", "rtl/gaussian_frame_render_pipeline.sv"):
        path = OUT / "source_before" / rel
        assert sha256(path) == old["source_manifest"][rel]
        preserved[rel] = sha256(path)
    report = dict(task="T02", task_complete=True, decision=decision, decision_reason=reason,
        default_enabled=False, functional_pass=True, ppa_signed_off=False, sta_executed=False,
        whole_scene_or_target_resolution_signoff=False, sva_executed=False,
        module_configurations=14, module_output_vectors=module["total_output_vectors"],
        dma_runs=96, comparisons=rows, aggregate=agg,
        by_workload={w["name"]:aggregate([r for r in rows if r["workload"]==w["name"]]) for w in dma["workloads"]},
        module_counterexamples=[r for r in module["ideal_comparisons"] if r["saved_cycles"]<0],
        system_counterexamples=[r for r in rows if r["saved_cycles"]<0],
        sorter_mapping=mapping, source_sha256={**dma["source_sha256"], **include_hashes}, input_sha256=inputs,
        testbench_sha256=dma["testbench_sha256"], module_source_sha256=module["source_sha256"],
        t01_preserved_source_sha256=preserved,
        artifacts_sha256={str(p.relative_to(ROOT)):sha256(p) for p in [OUT/"plan.md",OUT/"module/report.json",OUT/"dma/report.json",OUT/"sorter_mapping/report.json"]})
    (OUT / "audit.json").write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    print(json.dumps({"decision":decision, "aggregate":agg,"by_workload":report["by_workload"]},indent=2))

if __name__ == "__main__": main()
