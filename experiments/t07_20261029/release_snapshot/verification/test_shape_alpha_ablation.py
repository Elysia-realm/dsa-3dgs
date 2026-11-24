"""Evidence and corruption checks for the five-way shape/alpha interaction."""
import json
import tempfile
import unittest
from pathlib import Path

from scripts.audit_shape_alpha_ablation import audit
from scripts.run_shared_pe_validation import semantic_frame_sha256, sha256


ROOT = Path(__file__).resolve().parents[1]
REPORTS = [ROOT / f"experiments/shape_alpha_20260919_{size}/report.json" for size in ("n32", "n128")]


class ShapeAlphaAblationTests(unittest.TestCase):
    def test_current_source_five_way_equivalence_and_accounting(self):
        result = audit(ROOT, REPORTS)
        self.assertEqual(result["workloads"], 5)
        self.assertEqual(result["aggregate"]["runs"], 40)
        self.assertTrue(result["functional_pass"])
        self.assertFalse(result["ppa_signed_off"])
        self.assertGreater(result["aggregate"]["removed_alpha_tasks"], 0)

    def test_corrupt_overlap_accounting_is_rejected(self):
        report = json.loads(REPORTS[0].read_text(encoding="utf-8"))
        row = next(r for r in report["workloads"][0]["records"] if r["variant"] == "shape_alpha_skip")
        row["alpha_skip"]["skipped"] += 1
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "corrupt.json"
            path.write_text(json.dumps(report), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "overlap accounting"):
                audit(ROOT, [path])

    def test_same_source_baselines_reproduced(self):
        previous_paths = [ROOT / "experiments/alpha_zero_skip_20260917_n32_13scene/report.json",
                          ROOT / "experiments/alpha_zero_skip_20260917_n128_train/report.json"]
        old = {}
        for path in previous_paths:
            report = json.loads(path.read_text(encoding="utf-8"))
            old.update({(w["name"], r["variant"], r["mode"], r["profile"]): r
                        for w in report["workloads"] for r in w["records"]})
        count = 0
        for path in REPORTS:
            report = json.loads(path.read_text(encoding="utf-8"))
            for workload in report["workloads"]:
                for row in workload["records"]:
                    key = workload["name"], row["variant"], row["mode"], row["profile"]
                    if key in old:
                        self.assertEqual(row["perf"], old[key]["perf"])
                        self.assertEqual(row["frame_sha256"], old[key]["frame_sha256"])
                        self.assertEqual(row["raw_frame_sha256"], old[key]["raw_frame_sha256"])
                        count += 1
        self.assertEqual(count, 120)

    def test_structure_evidence_has_current_sources(self):
        report = json.loads((ROOT / "experiments/shape_alpha_20260919_structure.json").read_text())
        for source, digest in report["source_sha256"].items():
            self.assertEqual(sha256(ROOT / source), digest)
        default, alpha, combined = (report["variants"][v] for v in ("default", "alpha", "combined"))
        self.assertEqual(default["signed_multiply_ast_nodes"], alpha["signed_multiply_ast_nodes"])
        self.assertEqual(default["unsigned_multiply_ast_nodes"], alpha["unsigned_multiply_ast_nodes"])
        self.assertEqual(combined["signed_multiply_ast_nodes"], alpha["signed_multiply_ast_nodes"] + 1)
        self.assertFalse(report["ppa_signed_off"])

    def test_combined_auto_mode_across_two_epochs(self):
        path = ROOT / "experiments/shape_alpha_20260919_auto_repeat/report.json"
        report = json.loads(path.read_text())
        self.assertTrue(report["functional_pass"])
        shared, combined = report["rows"]
        self.assertEqual(shared["frame_sha256"], combined["frame_sha256"])
        self.assertEqual(combined["epoch"], 2)
        self.assertEqual(combined["auto"]["image_mismatches"], 0)
        self.assertGreater(combined["shape"]["rejected_blocks"], 0)
        self.assertGreater(combined["alpha_skip"]["skipped"], 0)
        for row in report["rows"]:
            self.assertEqual(row["frame_sha256"], semantic_frame_sha256(
                path.parent / f"{row['variant']}.memh", row["epoch"]))
            self.assertEqual(row["binary_sha256"], sha256(REPORTS[0].parent / f"{row['variant']}.vvp"))


if __name__ == "__main__":
    unittest.main()
