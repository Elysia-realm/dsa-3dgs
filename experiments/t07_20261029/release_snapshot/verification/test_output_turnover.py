import json
import unittest
from pathlib import Path

from scripts.run_shared_pe_validation import sha256
from scripts.compare_shared_pe_validation import compare

ROOT = Path(__file__).resolve().parents[1]
CURRENT = ROOT / "experiments/shared_pe/validation_20260917_shape_resource_guard"
TURNOVER_EVIDENCE = ROOT / "experiments/shared_pe/validation_20260914_xyz_turnover_n32/output_ablation_signed"


class OutputTurnoverTests(unittest.TestCase):
    def test_ablation_current_sources_all_features_exercised(self):
        report = json.loads((TURNOVER_EVIDENCE / "report.json").read_text(encoding="utf-8"))
        self.assertTrue(report["functional_pass"])
        self.assertFalse(report["sva_executed"])
        self.assertFalse(report["ppa_signed_off"])
        for source, digest in report["source_sha256"].items():
            self.assertEqual(sha256(ROOT/source), digest)
        self.assertEqual(len(report["records"]), 12)
        by_axis = {(r["kind"], r["turnover"], r["bypass"], r["stress"]): r for r in report["records"]}
        for kind in ("XYZ", "ATTR"):
            for stress in (0, 1):
                old, turnover, final = (by_axis[kind, t, b, stress] for t, b in ((0, 0), (1, 0), (1, 1)))
                self.assertLess(turnover["cycles"], old["cycles"])
                self.assertLess(final["cycles"], turnover["cycles"])
                self.assertEqual(old["turnovers"], 0)
                if kind == "XYZ":
                    self.assertEqual(final["P"], 1152)
                    self.assertEqual(final["turnovers"], 127)
                    self.assertEqual(final["vectors"], 128)
                    self.assertEqual(final["first_grants"]+final["first_stalls"], 128)
                    if stress:
                        self.assertGreater(final["first_stalls"], 0)
                else:
                    self.assertEqual(final["requests"], 128)
                    self.assertEqual(final["outputs"], 121)
                    self.assertEqual(final["rejected"], 7)
                    self.assertGreater(final["bypasses"], 0)
        self.assertEqual(by_axis["XYZ", 1, 1, 0]["cycles"], 1281)
        self.assertEqual(by_axis["ATTR", 1, 1, 0]["cycles"], 384)

    def test_previous_round_dma_never_trades_work_or_quality_for_cycles(self):
        previous = ROOT / "experiments/shared_pe/validation_20260914_stable_runs_n32/dma_matrix_final/report.json"
        report = compare(previous, CURRENT / "dma_matrix_release/report.json", {"bypass", "shared_projection", "stable_run_sort"})
        self.assertTrue(report["cross_round_functional_pass"])
        self.assertEqual(len(report["records"]), 72)
        self.assertTrue(all(r["saved_cycles"] >= 0 for r in report["records"]))
        self.assertGreater(report["full_shared_improved_runs"], 0)

    def test_historical_extended_scene_caps_and_all_profiles_equal_images(self):
        report = json.loads((CURRENT / "dma_expanded_release/report.json").read_text(encoding="utf-8"))
        self.assertTrue(report["functional_pass"])
        self.assertEqual(report["aggregate"]["runs"], 72)
        self.assertEqual({w["scene"] for w in report["workloads"]}, {"truck", "room", "counter"})
        self.assertNotEqual(sha256(ROOT / "rtl/raster/blend_fixed_core.sv"),
                            report["source_sha256"]["rtl/raster/blend_fixed_core.sv"])
        for workload in report["workloads"]:
            self.assertEqual(len({r["frame_sha256"] for r in workload["records"]}), 1)
            for record in workload["records"]:
                work = record["sort_work"]
                self.assertEqual(work["shared"], record["shared_pe"]["G"] if work["caps"] else 0)
                self.assertLessEqual(work["reverse"], work["fast"])
                self.assertLessEqual(work["fast"], work["groups"])


if __name__ == "__main__":
    unittest.main()
