import hashlib
import itertools
import json
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.parallel_group_sort_model import sort_group
from scripts.compare_shared_pe_validation import compare
from scripts.audit_stable_run_validation import audit


ROOT = Path(__file__).resolve().parents[1]
CURRENT = ROOT / "experiments/shared_pe/validation_20260917_shape_resource_guard"


class ParallelGroupSortTests(unittest.TestCase):
    def test_algorithm_exhaustive_permutations_up_to_seven(self):
        for length in range(1, 8):
            for values in itertools.permutations(range(length)):
                records = [(v, 0, 0, i) for i, v in enumerate(values)]
                expected = sorted(records, key=lambda r: r[:3])
                for lanes in (1, 2, 4):
                    self.assertEqual(sort_group(records, lanes)[0], expected)

    def test_algorithm_exhaustive_duplicate_keys_preserves_payload_arrival(self):
        for values in itertools.product((-1, 0, 1), repeat=6):
            records = [(v, 0, 0, i) for i, v in enumerate(values)]
            for lanes in (1, 2, 4):
                self.assertEqual(sort_group(records, lanes)[0], sorted(records, key=lambda r: r[:3]))

    def test_one_quiet_phase_and_one_quiet_batch_are_not_convergence(self):
        records = [(v, 0, 0, i) for i, v in enumerate((0, 2, 1, 3))]
        result, phases = sort_group(records, 4)
        self.assertEqual(result, sorted(records, key=lambda r: r[:3]))
        self.assertGreater(phases, 1)
        records = [(v, 0, 0, i) for i, v in enumerate([*range(14), 15, 14])]
        self.assertEqual(sort_group(records, 4)[0], sorted(records, key=lambda r: r[:3]))
        with self.assertRaises(ValueError):
            sort_group(records, 0)

    def test_rtl_ablation_current_and_same_input_streams(self):
        report = json.loads((CURRENT / "sorter_ablation_checked/report.json").read_text(encoding="utf-8"))
        self.assertTrue(report["functional_pass"])
        self.assertFalse(report["synthesis_or_ppa_signoff"])
        self.assertFalse(report["sva_executed"])
        for source, digest in report["source_sha256"].items():
            self.assertEqual(hashlib.sha256((ROOT / source).read_bytes()).hexdigest().upper(), digest)
        self.assertEqual(len(report["records"]), 42)
        for i in range(0, 42, 7):
            before, old, fallback, batch, phase, monotonic, after = report["records"][i:i+7]
            self.assertEqual(before["capacity"], after["capacity"])
            self.assertEqual(before["vectors"], after["vectors"])
            self.assertEqual(after["groups"], 540+4*after["capacity"])
            self.assertEqual(after["vectors"], old["vectors"])
            self.assertEqual(after["vectors"], fallback["vectors"])
            self.assertEqual(after["reverse1"], before["reverse1"])
            self.assertGreater(after["serial_groups"], 0)
            self.assertEqual(len(after["cases"]), after["groups"])
            if after["capacity"] >= 8:
                self.assertGreater(after["local_compares"], 0)
                self.assertGreater(after["parallel_batches"], 0)
                self.assertLess(after["sorted4"], before["sorted4"])
                self.assertGreater(after["forwarded_grants"], 0)
                self.assertGreater(after["forwarded_stalls"], 0)
                self.assertGreater(after["collect_compares"], 0)
                self.assertGreater(after["fast_groups"], 0)
                self.assertGreater(after["reverse_groups"], 0)
                self.assertLess(after["cycles"], fallback["cycles"])
            if after["capacity"] == 16:
                self.assertEqual(after["reverse4"], 32)
                self.assertLess(after["reverse4"], before["reverse4"])
            if after["capacity"] == 32:
                self.assertEqual(after["reverse4"], 64)
                self.assertLess(after["reverse4"], before["reverse4"])

    def test_candidate_keeps_production_defaults_and_precise_shared_scope(self):
        status = json.loads((ROOT / "verification/implementation_status.json").read_text(encoding="utf-8"))
        self.assertTrue(status["parallel_group_sort_candidate_implemented"])
        self.assertTrue(status["parallel_group_sort_candidate_system_parameter_integrated"])
        self.assertFalse(status["parallel_group_sort_integrated"])
        self.assertFalse(status["parallel_group_sort_candidate_default_enabled"])
        self.assertFalse(status["parallel_group_sort_candidate_is_fully_shared_pe_array"])
        self.assertFalse(status["parallel_group_sort_candidate_ppa_signed_off"])
        self.assertTrue(status["parallel_group_sort_candidate_local_counters_apb_integrated"])
        self.assertEqual(status["parallel_group_sort_gate2_status"], "PARTIAL")
        for path in ("rtl/gs_accel_system_top.sv", "rtl/gaussian_frame_render_pipeline.sv"):
            self.assertIn("USE_PARALLEL_GROUP_SORT=1'b0", (ROOT / path).read_text(encoding="utf-8"))

    def test_candidate_elaboration_replaces_sorter_but_not_shared_pe(self):
        report = json.loads((CURRENT / "elaboration_report.json").read_text(encoding="utf-8"))
        self.assertTrue(report["parallel_sort_candidate_elaboration_pass"])
        self.assertEqual(report["parallel_instances"]["stable_group_sorter_parallel_shared"], 1)
        self.assertEqual(report["parallel_instances"]["shared_reconfigurable_pe_slice"], 1)
        self.assertEqual(report["shared_instances"].get("stable_group_sorter_parallel_shared", 0), 0)

    def test_candidate_matrix_all_images_and_work_unchanged_not_bypass_pass(self):
        report = json.loads((CURRENT / "dma_matrix_release/report.json").read_text(encoding="utf-8"))
        candidate = report["stable_run_sort_candidate"]
        self.assertTrue(candidate["functional_pass"])
        self.assertEqual(candidate["runs"], 24)
        self.assertFalse(candidate["default_enabled"])
        self.assertFalse(candidate["performance_vs_bypass_pass"])
        status = json.loads((ROOT / "verification/implementation_status.json").read_text(encoding="utf-8"))
        self.assertEqual(status["parallel_group_sort_candidate_real_variant"], candidate["variant"])
        self.assertEqual(status["parallel_group_sort_candidate_improved_vs_serial_runs"], candidate["improved_vs_serial_runs"])
        self.assertEqual(status["parallel_group_sort_candidate_contended_runs"], candidate["contended_runs"])
        self.assertEqual(status["parallel_group_sort_candidate_regressed_vs_serial_runs"],
                         candidate["runs"] - candidate["non_regressing_vs_serial_runs"])
        self.assertAlmostEqual(status["parallel_group_sort_candidate_mean_overhead_vs_bypass_percent"],
                               candidate["mean_gap_vs_bypass_percent"], places=5)
        self.assertAlmostEqual(status["parallel_group_sort_candidate_max_overhead_vs_bypass_percent"],
                               candidate["max_gap_vs_bypass_percent"], places=5)
        self.assertEqual(status["parallel_group_sort_candidate_performance_all_modes_vs_serial_pass"],
                         candidate["non_regressing_vs_serial_runs"] == candidate["runs"])
        self.assertEqual(status["parallel_group_sort_candidate_equal_vs_serial_runs"],
                         candidate["non_regressing_vs_serial_runs"] - candidate["improved_vs_serial_runs"])
        self.assertTrue(status["parallel_group_sort_candidate_adversarial_performance_pass"])
        for workload in report["workloads"]:
            references = {(r["mode"], r["profile"]): r for r in workload["records"] if r["variant"] == "shared_projection"}
            for record in workload["records"]:
                if record["variant"] == "stable_run_sort":
                    before = references[(record["mode"], record["profile"])]
                    for field in ("commits", "state_reads", "state_writes"):
                        self.assertEqual(before["perf"][field], record["perf"][field])
                    self.assertEqual(before["shared_pe"]["P"], record["shared_pe"]["P"])
                    self.assertEqual(before["shared_pe"]["main_mac"], record["shared_pe"]["main_mac"])
                    self.assertEqual(before["frame_sha256"], record["frame_sha256"])
                    self.assertEqual(record["sort_work"]["shared"], record["shared_pe"]["G"])
        comparisons = candidate["comparisons"]
        self.assertTrue(all(r["saved_cycles"] > 0 for r in comparisons if r["mode"] == "G"))
        self.assertTrue(all(r["saved_cycles"] >= 0 for r in comparisons))
        self.assertTrue(all(r["saved_cycles"] == 0 for r in comparisons if r["mode"] == "E"))
        baseline = compare(ROOT / "experiments/shared_pe/validation_20260913_phase_sort_n32/dma_matrix/report.json",
                           CURRENT / "dma_matrix_release/report.json",
                           {"bypass", "shared_projection"})
        self.assertTrue(baseline["cross_round_functional_pass"])
        self.assertEqual(len(baseline["records"]), 48)
        self.assertTrue(all(r["saved_cycles"] >= 0 for r in baseline["records"]))

    def test_budget_one_fallback_oracle_is_stable_exhaustively(self):
        for values in itertools.product((-1, 0, 1), repeat=6):
            records = [(v, i%2, 0, i) for i, v in enumerate(values)]
            actual, phases = sort_group(records, 1, serial_fallback=True)
            self.assertEqual(actual, sorted(records, key=lambda r: r[:3]))
            self.assertEqual(phases, 0)

    def test_forwarding_scope_and_single_storage_contract(self):
        source = (ROOT / "rtl/sort/stable_group_sorter_parallel_shared.sv").read_text(encoding="utf-8")
        self.assertEqual(source.count("depth_q[CAPACITY]"), 1)
        self.assertIn("request_base=batch_chain?", source)
        self.assertIn("ENABLE_SERIAL_FALLBACK&&cfg_active_lanes_i<=1", source)
        self.assertIn("Post-swap source selection", source)
        self.assertIn("phase_chain&&batch_swap[j]", source)
        status = json.loads((ROOT / "verification/implementation_status.json").read_text(encoding="utf-8"))
        self.assertTrue(status["parallel_group_sort_candidate_serial_fallback_implemented"])
        self.assertTrue(status["parallel_group_sort_candidate_batch_forwarding_implemented"])
        self.assertTrue(status["parallel_group_sort_candidate_phase_forwarding_implemented"])

    def test_phase_forwarding_does_not_omit_comparison_swap_or_phase_work(self):
        report = json.loads((CURRENT / "sorter_ablation_checked/report.json").read_text(encoding="utf-8"))
        self.assertTrue(report["module_hardware_counters_monitor_pass"])
        for i in range(0, 42, 7):
            batch, phase = report["records"][i+3:i+5]
            for field in ("grants", "local_compares", "swaps", "phases", "groups", "serial_groups", "vectors"):
                self.assertEqual(batch[field], phase[field])
            if phase["capacity"] >= 3:
                self.assertGreater(phase["phase_grants"], 0)
                self.assertGreater(phase["phase_stalls"], 0)
                self.assertLess(phase["cycles"], batch["cycles"])
        self.assertTrue(report["performance_all_non_stress_cases_vs_serial_pass"])
        status = json.loads((ROOT / "verification/implementation_status.json").read_text(encoding="utf-8"))
        cases = report["non_stress_case_comparisons"]
        self.assertEqual(status["parallel_group_sort_candidate_non_stress_cases_total"], len(cases))
        self.assertEqual(status["parallel_group_sort_candidate_non_stress_cases_non_regressing"],
                         sum(r["saved_cycles"] >= 0 for r in cases))
        self.assertEqual(status["parallel_group_sort_candidate_adversarial_performance_pass"],
                         report["performance_all_non_stress_cases_vs_serial_pass"])
        self.assertTrue(all(r["saved_cycles"] >= 0 for r in report["non_stress_case_comparisons"]))

    def test_work_counters_connected_to_candidate_system_snapshot(self):
        status = json.loads((ROOT / "verification/implementation_status.json").read_text(encoding="utf-8"))
        self.assertTrue(status["parallel_group_sort_candidate_module_work_counters_implemented"])
        self.assertTrue(status["parallel_group_sort_candidate_local_counters_apb_integrated"])
        frame = (ROOT / "rtl/gaussian_frame_render_pipeline.sv").read_text(encoding="utf-8")
        self.assertIn(".perf_shared_compares_o(sort_work_totals_o[0+:32])", frame)
        self.assertIn(".perf_shifts_o(sort_work_totals_o[256+:32])", frame)
        system = (ROOT / "rtl/gs_accel_system_top.sv").read_text(encoding="utf-8")
        self.assertIn("sort_work_totals[32*i+:32]-sort_work_base_q[32*i+:32]", system)

    def test_monotonic_oracle_strict_reverse_and_equal_key_stability(self):
        keys = ((-1, 0, 0), (-1, 1, 0), (0, 0, 0), (0, 0, 1), (1, 0, 0))
        for values in itertools.product(keys, repeat=6):
            records = [(*key, i) for i, key in enumerate(values)]
            for lanes in (2, 4):
                actual, _ = sort_group(records, lanes, monotonic_fastpath=True)
                self.assertEqual(actual, sorted(records, key=lambda r: r[:3]))
        records = [(2, 0, 0, 0), (2, 0, 0, 1), (1, 0, 0, 2)]
        self.assertGreater(sort_group(records, 2, monotonic_fastpath=True)[1], 0)

    def test_previous_case_scope_and_expanded_tail_cases_do_not_regress(self):
        report = json.loads((CURRENT / "sorter_ablation_checked/report.json").read_text(encoding="utf-8"))
        old_scope = [r for r in report["non_stress_case_comparisons"] if r["kind"] < 10]
        self.assertEqual(len(old_scope), 134)
        self.assertTrue(all(r["saved_cycles"] >= 0 for r in old_scope))
        self.assertEqual(sum(r["saved_cycles"] < 0 for r in report["non_stress_case_comparisons"]), 0)

    def test_real_snapshots_expose_collect_work_without_claiming_latency_gain(self):
        report = json.loads((CURRENT / "dma_matrix_release/report.json").read_text(encoding="utf-8"))
        hits = 0
        for workload in report["workloads"]:
            before = {(r["mode"], r["profile"]): r for r in workload["records"] if r["variant"] == "monotonic_sort"}
            for record in workload["records"]:
                if record["variant"] != "stable_run_sort":
                    continue
                old = before[(record["mode"], record["profile"])]
                work = record["sort_work"]
                self.assertEqual(work["caps"], 7)
                self.assertEqual(work["sequence"], 1)
                self.assertEqual(work["shared"], record["shared_pe"]["G"])
                self.assertEqual(work["local"]-work["collect"], old["sort_work"]["local"]-old["sort_work"]["collect"])
                self.assertLessEqual(work["collect"], old["sort_work"]["collect"])
                self.assertEqual(record["perf"]["cycles"], old["perf"]["cycles"])
                self.assertEqual(work["shifts"], old["sort_work"]["shifts"])
                hits += work["fast"]
                if record["mode"] != "E":
                    self.assertGreater(work["collect"], 0)
        self.assertEqual(hits, 0)

    def test_stable_runs_and_tail_insertion_oracle_exhaustive(self):
        keys = ((-1, 0, 0), (-1, 1, 0), (0, 0, 0), (0, 0, 1), (1, 0, 0))
        for values in itertools.product(keys, repeat=6):
            records = [(*key, i) for i, key in enumerate(values)]
            for lanes in (2, 4):
                actual, _ = sort_group(records, lanes, monotonic_fastpath=True, stable_run_fastpath=True)
                self.assertEqual(actual, sorted(records, key=lambda r: r[:3]))
        for tail in range(-1, 10):
            records = [(v, 0, 0, i) for i, v in enumerate([8, 8, 6, 6, 4, 4, 2, tail])]
            actual, phases = sort_group(records, 2, monotonic_fastpath=True, stable_run_fastpath=True)
            self.assertEqual(actual, sorted(records, key=lambda r: r[:3]))
            self.assertEqual(phases, 0)

    def test_historical_round_audit_scope_and_immutable_baselines(self):
        with self.assertRaisesRegex(ValueError, "stale source evidence: rtl/raster/blend_fixed_core.sv"):
            audit(ROOT, CURRENT, "dma_matrix_release")
        report = json.loads((CURRENT / "sort_round_audit.json").read_text(encoding="utf-8"))
        self.assertTrue(report["source_current"])  # true at capture, not current now
        self.assertEqual(report["non_stress_non_regressing"], 374)
        self.assertEqual(report["non_stress_regressions"], [])
        self.assertEqual(report["real_dma_runs"], 96)
        self.assertGreater(report["real_candidate_improved_vs_previous_candidate_runs"], 0)
        self.assertEqual(report["real_candidate_improved_vs_same_round_monotonic_runs"], 0)
        self.assertGreater(report["real_collect_removed"], 0)
        self.assertFalse(report["universal_non_regression_signed_off"])
        self.assertFalse(report["energy_area_frequency_signed_off"])
        self.assertEqual(len(report["previous_baselines"]["records"]), 72)
        self.assertTrue(all(r["saved_cycles"] >= 0 for r in report["previous_baselines"]["records"]))

    def test_round_audit_rejects_stale_source_digest(self):
        with patch("scripts.audit_stable_run_validation.sha256", return_value="STALE"):
            with self.assertRaisesRegex(ValueError, "stale source"):
                audit(ROOT, CURRENT, "dma_matrix_release")


if __name__ == "__main__":
    unittest.main()
