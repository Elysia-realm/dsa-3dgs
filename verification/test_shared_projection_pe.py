import hashlib
import json
import unittest
from pathlib import Path

from scripts.check_shared_pe_elaboration import count_instances
from scripts.run_shared_pe_validation import parse_record


ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "experiments/shared_pe/validation_20260917_shape_resource_guard/dma_matrix_release"


class SharedProjectionPeTests(unittest.TestCase):
    def test_telemetry_parser_handles_uppercase_and_underscores(self):
        self.assertEqual(parse_record("REAL_SHARED_PE G=2 P=9 G_stall=3 competing=4\n", "REAL_SHARED_PE"),
                         {"G": 2, "P": 9, "G_stall": 3, "competing": 4})

    def test_missing_telemetry_is_not_a_zero_result(self):
        with self.assertRaises(ValueError):
            parse_record("PASS: unrelated", "REAL_SHARED_PE")

    def test_elaboration_counter_counts_instances_not_module_definitions(self):
        tree = {"modulesp": [
            {"type": "MODULE", "addr": "top", "name": "gs_accel_system_top", "origName": "gs_accel_system_top",
             "stmtsp": [{"type": "CELL", "modp": "pe"}, {"type": "CELL", "modp": "pe"}]},
            {"type": "MODULE", "addr": "pe", "name": "pe", "origName": "pe", "stmtsp": []},
        ]}
        self.assertEqual(count_instances(tree)["pe"], 2)

    def test_mean_adapter_has_dependencies_bypass_and_idle_guard(self):
        adapter = (ROOT / "rtl/projection/world_to_camera_shared_mac.sv").read_text(encoding="utf-8")
        array = (ROOT / "rtl/projection/raw_gaussian_projection_array.sv").read_text(encoding="utf-8")
        lane = (ROOT / "rtl/projection/raw_gaussian_projection_lane.sv").read_text(encoding="utf-8")
        self.assertIn("acc_valid_q[issue_axis_q]", adapter)
        self.assertIn("all_idle_o=scheduler_idle&&!mean_busy", array)
        self.assertIn("MEAN_IS_CAMERA(USE_SHARED_PROJECTION_PE)", array)
        self.assertIn("if(MEAN_IS_CAMERA)", lane)
        self.assertIn("world_to_camera_core", lane)

    def test_elaboration_evidence_is_not_ppa_signoff(self):
        report = json.loads((REPORT_DIR.parent / "elaboration_report.json").read_text(encoding="utf-8"))
        self.assertTrue(report["elaboration_pass"])
        self.assertFalse(report["synthesis_or_ppa_signoff"])
        self.assertEqual(report["shared_instances"].get("world_to_camera_core", 0), 0)
        self.assertEqual(report["bypass_instances"]["world_to_camera_core"], 4)
        self.assertEqual(report["shared_instances"]["shared_reconfigurable_pe_slice"], 1)

    def test_historical_matrix_has_96_equal_runs_and_production_contention(self):
        report = json.loads((REPORT_DIR / "report.json").read_text(encoding="utf-8"))
        self.assertTrue(report["functional_pass"])
        self.assertTrue(report["production_contention_observed"])
        self.assertFalse(report["performance_pass"])
        self.assertEqual(report["aggregate"]["runs"], 96)
        # This immutable September 17 baseline predates the optional R client.
        # A current-source claim belongs to the new R-client report below.
        self.assertNotEqual(hashlib.sha256((ROOT / "rtl/raster/blend_fixed_core.sv").read_bytes()).hexdigest().upper(),
                            report["source_sha256"]["rtl/raster/blend_fixed_core.sv"])
        self.assertNotEqual(hashlib.sha256((ROOT / "verification/rtl/tb_real_dma_workload.sv").read_bytes()).hexdigest().upper(),
                            report["testbench_sha256"])
        for workload in report["workloads"]:
            self.assertEqual(len(workload["records"]), 32)
            self.assertEqual(len({r["frame_sha256"] for r in workload["records"]}), 1)


if __name__ == "__main__":
    unittest.main()
