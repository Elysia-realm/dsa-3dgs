import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ROUND = ROOT / "experiments/shared_pe/validation_20260915_streaming_prepass_n32"


class StreamingDepthPrepassEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.audit = json.loads((ROUND / "round_audit.json").read_text(encoding="utf-8"))
        cls.elaboration = json.loads((ROUND / "elaboration_report.json").read_text(encoding="utf-8"))

    def test_six_scene_ab_is_bit_exact_and_always_improves_shared(self):
        self.assertTrue(self.audit["functional_pass"])
        self.assertEqual(self.audit["runs"], 48)
        self.assertEqual(self.audit["scenes"], 6)
        self.assertEqual(self.audit["improved_vs_shared_runs"], 48)
        self.assertEqual(self.audit["non_regressing_vs_shared_runs"], 48)
        self.assertEqual(self.audit["ideal_saved_cycles"], [33])
        self.assertEqual(self.audit["limited_saved_cycles"], [4])

    def test_only_collect_prepass_work_is_replaced(self):
        self.assertEqual(self.audit["removed_shared_prepass_grants_per_n32_run"], 96)
        for row in self.audit["rows"]:
            self.assertEqual(row["shared_p_grants"] - row["streaming_p_grants"], 96)
            self.assertEqual(row["main_xyz_mac_grants"], 288)
            self.assertEqual(row["shared_collect_cycles"] - row["streaming_collect_cycles"],
                             row["saved_cycles"])

    def test_candidate_is_not_promoted_without_ppa(self):
        self.assertFalse(self.audit["default_enabled"])
        self.assertFalse(self.audit["synthesis_or_ppa_signoff"])
        self.assertFalse(self.audit["performance_vs_bypass_pass"])
        self.assertEqual(self.audit["restored_local_multiplier_operators"], 3)
        status = json.loads((ROOT / "verification/implementation_status.json").read_text(encoding="utf-8"))
        self.assertTrue(status["streaming_depth_prepass_candidate_implemented"])
        self.assertTrue(status["streaming_depth_prepass_candidate_performance_vs_shared_pass"])
        self.assertFalse(status["streaming_depth_prepass_candidate_default_enabled"])
        self.assertFalse(status["streaming_depth_prepass_candidate_performance_vs_bypass_pass"])
        self.assertFalse(status["streaming_depth_prepass_candidate_ppa_signed_off"])
        self.assertEqual(status["streaming_depth_prepass_candidate_report"],
                         "experiments/shared_pe/validation_20260915_streaming_prepass_n32/round_audit.json")

    def test_elaboration_keeps_shared_sort_and_main_projection(self):
        self.assertTrue(self.elaboration["streaming_depth_prepass_candidate_elaboration_pass"])
        stream = self.elaboration["streaming_instances"]
        self.assertEqual(stream.get("gaussian_depth_prepass_core"), 1)
        self.assertEqual(stream.get("gaussian_depth_prepass_shared_mac", 0), 0)
        self.assertEqual(stream.get("shared_reconfigurable_pe_slice"), 1)
        self.assertEqual(stream.get("world_to_camera_shared_mac"), 1)


if __name__ == "__main__":
    unittest.main()
