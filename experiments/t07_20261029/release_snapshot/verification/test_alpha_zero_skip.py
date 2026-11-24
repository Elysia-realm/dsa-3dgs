"""Arithmetic identity and current-source evidence for the alpha no-op skip."""

import json
import random
import unittest
from pathlib import Path

from model.fixed.blend import blend_codes
from scripts.audit_alpha_zero_skip_validation import audit
from scripts.run_shared_pe_validation import semantic_frame_sha256, sha256


ROOT = Path(__file__).resolve().parents[1]
N32 = ROOT / "experiments/alpha_zero_skip_20260917_n32_13scene/report.json"
N128 = ROOT / "experiments/alpha_zero_skip_20260917_n128_train/report.json"
AUTO = ROOT / "experiments/alpha_zero_skip_20260917_auto_repeat_train/report.json"


class AlphaZeroSkipTests(unittest.TestCase):
    def test_zeroed_alpha_blend_is_identity_on_valid_pixel_states(self):
        rng = random.Random(0xA17A5A1)
        for _ in range(10000):
            rgb = tuple(rng.randrange(4097) for _ in range(3))
            old_t = rng.randrange(65536)
            color = tuple(rng.randrange(4097) for _ in range(3))
            result = blend_codes(rgb, old_t, color, 0)
            self.assertEqual(result.rgb_q12, rgb)
            self.assertEqual(result.transmittance_q16, old_t)
            self.assertFalse(result.newly_terminated)

    def test_current_source_dma_evidence(self):
        report = audit(ROOT, [N32, N128])
        self.assertEqual(report["scenes"], 15)
        self.assertEqual(report["candidate_runs"], 120)
        self.assertTrue(report["functional_pass"])
        self.assertFalse(report["default_enabled"])
        self.assertFalse(report["synthesis_or_ppa_signoff"])
        self.assertGreater(report["skipped_pixels"], 0)
        self.assertEqual(report["improved_vs_shared_runs"], report["candidate_runs"])

    def test_default_paths_preserve_prior_three_scene_baseline(self):
        previous = json.loads((ROOT / "experiments/shared_raster_pe_20260917_n32/report.json")
                              .read_text(encoding="utf-8"))
        current = json.loads(N32.read_text(encoding="utf-8"))
        old = {(workload["name"], record["variant"], record["mode"], record["profile"]): record
               for workload in previous["workloads"] for record in workload["records"]
               if record["variant"] in ("bypass", "shared_projection")}
        compared = 0
        for workload in current["workloads"]:
            for record in workload["records"]:
                key = workload["name"], record["variant"], record["mode"], record["profile"]
                if key in old:
                    self.assertEqual(record["perf"]["cycles"], old[key]["perf"]["cycles"])
                    self.assertEqual(record["frame_sha256"], old[key]["frame_sha256"])
                    self.assertEqual(record["raw_frame_sha256"], old[key]["raw_frame_sha256"])
                    compared += 1
        self.assertEqual(compared, 48)

    def test_auto_two_epoch_evidence(self):
        report = json.loads(AUTO.read_text(encoding="utf-8"))
        self.assertTrue(report["source_current"])
        self.assertTrue(report["functional_pass"])
        self.assertFalse(report["ppa_signed_off"])
        shared, candidate = report["rows"]
        self.assertEqual(shared["frame_sha256"], candidate["frame_sha256"])
        self.assertEqual(shared["auto"]["image_mismatches"], 0)
        self.assertEqual(candidate["auto"]["image_mismatches"], 0)
        self.assertEqual(shared["alpha_skip"]["skipped"], 0)
        self.assertGreater(candidate["alpha_skip"]["skipped"], 0)
        self.assertGreater(report["selected_saved_cycles"], 0)
        for row in report["rows"]:
            self.assertEqual(row["binary_sha256"],
                             sha256(N32.parent / f"{row['variant']}.vvp"))
            self.assertEqual(row["frame_sha256"], semantic_frame_sha256(
                AUTO.parent / f"{row['variant']}.memh", row["epoch"]))

    def test_implementation_status_matches_current_audit(self):
        status = json.loads((ROOT / "verification/implementation_status.json")
                            .read_text(encoding="utf-8"))
        report = audit(ROOT, [N32, N128])
        self.assertEqual(status["alpha_zero_skip_candidate_real_runs"], report["candidate_runs"])
        self.assertEqual(status["alpha_zero_skip_candidate_improved_vs_shared_runs"],
                         report["improved_vs_shared_runs"])
        self.assertEqual(status["alpha_zero_skip_candidate_skipped_pixels"], report["skipped_pixels"])
        self.assertEqual(status["alpha_zero_skip_candidate_removed_state_reads"],
                         report["removed_state_reads"])
        self.assertEqual(status["alpha_zero_skip_candidate_removed_state_writes"],
                         report["removed_state_writes"])
        self.assertFalse(status["alpha_zero_skip_candidate_default_enabled"])
        self.assertFalse(status["alpha_zero_skip_candidate_ppa_signed_off"])


if __name__ == "__main__":
    unittest.main()
