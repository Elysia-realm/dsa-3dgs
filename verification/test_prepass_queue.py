import hashlib
import json
import unittest
from pathlib import Path

from scripts.compare_shared_pe_validation import compare


ROOT = Path(__file__).resolve().parents[1]
CURRENT = ROOT / "experiments/shared_pe/validation_20260913_queued_prepass_final_n32"
PREVIOUS = ROOT / "experiments/shared_pe/validation_20260913_projection_n32"


class PrepassQueueTests(unittest.TestCase):
    def test_context_ablation_is_current_and_complete(self):
        report = json.loads((CURRENT / "context_ablation/report.json").read_text(encoding="utf-8"))
        self.assertTrue(report["functional_pass"])
        self.assertFalse(report["synthesis_or_ppa_signoff"])
        self.assertFalse(report["sva_executed"])
        for source, digest in report["source_sha256"].items():
            self.assertEqual(hashlib.sha256((ROOT / source).read_bytes()).hexdigest().upper(), digest)
        self.assertEqual([r["contexts"] for r in report["records"]], [1, 3, 4])
        for record in report["records"]:
            self.assertEqual(record["vectors"], 324)
            self.assertEqual(record["grants"], 972)
            self.assertGreater(record["full"], 0)
            self.assertGreater(record["stalls"], 0)
            if record["contexts"] >= 3:
                self.assertLessEqual(record["burst64_cycles"], 200)
                self.assertGreater(record["concurrent_io"], 0)
        self.assertGreater(report["burst64_speedup_context4_vs_context1"], 1.9)

    def test_cross_round_improvement_does_not_hide_bypass_regression(self):
        report = compare(PREVIOUS / "report.json", CURRENT / "report.json")
        self.assertTrue(report["cross_round_functional_pass"])
        self.assertEqual(report["full_shared_improved_runs"], report["full_shared_runs"])
        self.assertEqual(report["full_shared_runs"], 24)
        self.assertLess(report["current_mean_gap_percent"], report["previous_mean_gap_percent"])
        self.assertFalse(report["current_performance_pass"])
        for record in report["records"]:
            if record["variant"] == "bypass":
                self.assertEqual(record["saved_cycles"], 0)
            else:
                self.assertGreater(record["saved_cycles"], 0)
                self.assertLess(record["current_collect"], record["previous_collect"])

    def test_machine_status_uses_new_evidence_not_historical_matrix(self):
        status = json.loads((ROOT / "verification/implementation_status.json").read_text(encoding="utf-8"))
        report_path = ROOT / status["shared_pe_real_validation_report"]
        report = json.loads(report_path.read_text(encoding="utf-8"))
        self.assertIn("shape_resource_guard/dma_matrix_release/report.json", status["shared_pe_real_validation_report"])
        self.assertEqual(status["shared_pe_prepass_context_count"], 4)
        self.assertTrue(status["shared_pe_prepass_abort_drain_guard_implemented"])
        frame = (ROOT / "rtl/gaussian_frame_render_pipeline.sv").read_text(encoding="utf-8")
        self.assertIn("pre_inflight_q==0&&!source_valid_i", frame)
        self.assertEqual(status["shared_pe_production_performance_pass"], report["performance_pass"])
        self.assertAlmostEqual(status["shared_pe_real_mean_overhead_percent"], report["aggregate"]["mean_gap_percent"], places=5)


if __name__ == "__main__":
    unittest.main()
