"""Immutable R-blend candidate evidence from before alpha-zero skip integration."""

import json
import unittest
from pathlib import Path

from scripts.run_shared_pe_validation import sha256


ROOT = Path(__file__).resolve().parents[1]
REPORTS = (
    ROOT / "experiments/shared_raster_pe_20260917_n4_bypass/report.json",
    ROOT / "experiments/shared_raster_pe_20260917_n32/report.json",
)


class SharedRasterPeTests(unittest.TestCase):
    def test_default_paths_match_immutable_pre_r_baselines(self):
        old_root = ROOT / "experiments/shared_pe/validation_20260917_shape_resource_guard"
        historical = [json.loads((old_root / name / "report.json").read_text(encoding="utf-8"))
                      for name in ("dma_matrix_release", "dma_seven_new_scenes")]
        old = {(w["name"], r["variant"], r["mode"], r["profile"]): r
               for report in historical for w in report["workloads"] for r in w["records"]}
        current = json.loads(REPORTS[1].read_text(encoding="utf-8"))
        count = 0
        for workload in current["workloads"]:
            for record in workload["records"]:
                if record["variant"] not in ("bypass", "shared_projection"):
                    continue
                prior = old[(workload["name"], record["variant"], record["mode"], record["profile"])]
                self.assertEqual(record["perf"]["cycles"], prior["perf"]["cycles"])
                self.assertEqual(record["raw_frame_sha256"], prior["raw_frame_sha256"])
                self.assertEqual(record["frame_sha256"], prior["frame_sha256"])
                count += 1
        self.assertEqual(count, 48)

    def test_historical_reports_are_bit_exact_and_r_is_real(self):
        for path, scenes, runs in zip(REPORTS, (1, 3), (24, 72)):
            with self.subTest(path=path):
                report = json.loads(path.read_text(encoding="utf-8"))
                self.assertTrue(report["functional_pass"])
                self.assertEqual(report["aggregate"]["runs"], runs)
                self.assertEqual(len(report["workloads"]), scenes)
                self.assertNotEqual(sha256(ROOT / "rtl/raster/raster_pair_shell.sv"),
                                    report["source_sha256"]["rtl/raster/raster_pair_shell.sv"])
                self.assertNotEqual(sha256(ROOT / "verification/rtl/tb_real_dma_workload.sv"),
                                    report["testbench_sha256"])
                candidate = report["shared_raster_blend_candidate"]
                self.assertTrue(candidate["functional_pass"])
                self.assertFalse(candidate["default_enabled"])
                self.assertFalse(candidate["synthesis_or_ppa_signoff"])
                self.assertGreater(candidate["r_grants"], 0)
                self.assertEqual(candidate["non_regressing_vs_local_runs"], 0)
                for workload in report["workloads"]:
                    self.assertEqual(len({r["frame_sha256"] for r in workload["records"]}), 1)


if __name__ == "__main__":
    unittest.main()
