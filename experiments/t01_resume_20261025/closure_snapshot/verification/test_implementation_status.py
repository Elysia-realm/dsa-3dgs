from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ImplementationStatusTests(unittest.TestCase):
    def setUp(self):
        self.status = json.loads(
            (ROOT / "verification/implementation_status.json").read_text(encoding="utf-8")
        )

    def test_only_system_top_is_the_production_filelist_top(self):
        sources = (ROOT / "verification/rtl/system_top_sources.f").read_text(encoding="utf-8")
        self.assertEqual(self.status["production_top"], "gs_accel_system_top")
        self.assertIn("rtl/gs_accel_system_top.sv", sources)
        self.assertNotIn("rtl/gs_accel_top.sv", sources)
        self.assertIn("gs_accel_top", self.status["legacy_compatibility_tops"])

    def test_t03_camera_descriptor_path_is_machine_readable(self):
        top = (ROOT / "rtl/gs_accel_system_top.sv").read_text(encoding="utf-8")
        sources = (ROOT / "verification/rtl/system_top_sources.f").read_text(
            encoding="utf-8"
        )
        self.assertTrue(self.status["camera_descriptor_dma_integrated"])
        self.assertTrue(self.status["camera_base_register_consumed_by_dma"])
        self.assertEqual(self.status["t03_status"], "COMPLETE")
        self.assertTrue(self.status["t03_signed_off"])
        self.assertEqual(self.status["t03_camera_descriptor_version"], 1)
        self.assertEqual(self.status["t03_camera_descriptor_bytes"], 224)
        # T03 remains signed as later tasks finish; do not pin the project
        # cursor forever to the historical T06 checkpoint. An explicitly
        # scheduled recovery round may precede the next functional task.
        expected_functional=next((f'T{i:02d}' for i in range(6,14)
                            if not self.status.get(f't{i:02d}_signed_off',False)),None)
        expected_next = expected_functional
        resume = self.status.get("execution_resume_plan", {})
        if resume.get("status") in {"PLANNED", "IN_PROGRESS"}:
            self.assertEqual(resume["return_to_task"], expected_functional)
            self.assertEqual(self.status["next_functional_task"], expected_functional)
            self.assertRegex(resume["task"], r"^T\d{2}$")
            self.assertIn(f'{resume["task"].lower()}_signed_off', self.status)
            self.assertFalse(self.status[f'{resume["task"].lower()}_signed_off'])
            self.assertTrue((ROOT / self.status["execution_checklist"]).is_file())
            expected_next = resume["task"]
        self.assertEqual(self.status["next_execution_task"], expected_next)
        self.assertIn(".base_addr_i(cmd_camera_base_q)", top)
        self.assertIn("axi4_camera_config_read_dma", top)
        self.assertIn("rtl/dma/axi4_camera_config_read_dma.sv", sources)

    def test_t04_final_rgb_dma_is_machine_readable(self):
        top = (ROOT / "rtl/gs_accel_system_top.sv").read_text(encoding="utf-8")
        sources = (ROOT / "verification/rtl/system_top_sources.f").read_text(
            encoding="utf-8"
        )
        self.assertEqual(self.status["t04_status"], "COMPLETE")
        self.assertTrue(self.status["t04_signed_off"])
        self.assertTrue(self.status["t04_production_final_rgb_dma_default_enabled"])
        self.assertEqual(self.status["t04_output_format_version"], 1)
        self.assertTrue(self.status["t04_4k_boundary_safe"])
        self.assertTrue(self.status["t04_done_after_final_b_response"])
        self.assertEqual(self.status["t04_error_status_bits"], [22, 23, 24])
        self.assertIn("USE_FINAL_RGB_DMA=1'b1", top)
        self.assertIn("axi4_final_rgb_frame_dma", top)
        self.assertIn("rtl/dma/axi4_final_rgb_frame_dma.sv", sources)
        self.assertTrue(self.status["t04_revalidation_complete"])
        self.assertGreaterEqual(len(self.status["t04_real_rgb_scenes"]), 5)
        self.assertEqual(self.status["t04_real_rgb_runs_failed"], 0)
        self.assertEqual(self.status["t04_real_rgb_byte_mismatches"], 0)
        self.assertTrue(self.status["t04_real_rgb_uses_cpu_sorted_continuation_batches"])
        self.assertFalse(self.status["t04_real_rgb_full_scene_quality_signed_off"])

    def test_real_scene_completion_requires_five_distinct_scenes(self):
        policy = self.status["real_scene_completion_policy"]
        data_scenes = sorted(path.name for path in (ROOT / "data").iterdir() if path.is_dir())
        checklist = (ROOT / "docs/毕业设计剩余任务执行清单_2026-09-20.md").read_text(
            encoding="utf-8"
        )
        self.assertEqual(policy["minimum_distinct_scenes_for_completion"], 5)
        self.assertTrue(policy["all_selected_scenes_must_pass"])
        self.assertEqual(policy["available_scene_count"], len(data_scenes))
        self.assertEqual(policy["available_scenes"], data_scenes)
        self.assertTrue(policy["t10_full_scope_unchanged"])
        self.assertEqual(policy["t10_required_scene_count"], 13)
        self.assertEqual(policy["t10_min_views_per_scene"], 5)
        self.assertIn("至少 **5 个不同场景**", checklist)
        self.assertIn("单场景结果只可作为冒烟、调试或局部诊断", checklist)

    def test_t05_signed_scope_and_default_resources(self):
        top=(ROOT/'rtl/gs_accel_system_top.sv').read_text(encoding='utf-8')
        self.assertTrue(self.status['t05_signed_off'])
        self.assertEqual(self.status['t05_status'],'COMPLETE')
        self.assertEqual(self.status['t05_selected_bsu_capacity'],16)
        self.assertEqual(self.status['t05_supported_bsu_capacities'],[8,16])
        self.assertEqual(self.status['t05_real_validation_runs'],40)
        self.assertEqual(self.status['t05_selection_runs'],240)
        self.assertTrue(self.status['t05_collect_sort_emit_overlap_verified'])
        self.assertFalse(self.status['t05_full_chip_ppa_signed_off'])
        self.assertFalse(self.status['t05_real_validation_full_scene'])
        self.assertTrue(self.status['t05_real_validation_cpu_ordered_batch_boundaries'])
        self.assertIn("USE_BITONIC_SORT=1'b1",top)
        self.assertIn("BSU_PIPELINED=1'b1",top)
        self.assertIn("SORT_CAPACITY=16",top)
        self.assertIn("USE_SHARED_RASTER_PE=1'b1",top)

    def test_shared_pe_production_scope_is_precisely_declared(self):
        pe = (ROOT / "rtl/control/shared_reconfigurable_pe_slice.sv").read_text(
            encoding="utf-8"
        )
        frame = (ROOT / "rtl/gaussian_frame_render_pipeline.sv").read_text(
            encoding="utf-8"
        )
        self.assertTrue(self.status["shared_pe_slice_implemented"])
        self.assertTrue(self.status["shared_pe_integrated_into_production_path"])
        self.assertTrue(self.status["shared_pe_group_compare_client_integrated"])
        self.assertTrue(self.status["shared_pe_depth_prepass_mac_client_integrated"])
        self.assertTrue(self.status["shared_pe_main_projection_mac_client_integrated"])
        self.assertTrue(self.status["shared_pe_raster_mac_client_integrated"])
        self.assertEqual(self.status["shared_pe_gate1_status"], "COMPLETE_FUNCTIONAL")
        self.assertEqual(self.status["shared_pe_production_client_count"], 3)
        self.assertTrue(self.status["shared_pe_cross_client_contention_observed"])
        self.assertFalse(self.status["shared_pe_production_performance_pass"])
        # Preserve historical latency ceilings without rejecting real gains.
        self.assertGreater(self.status["shared_pe_dma_micro_bypass_cycles"], 0)
        self.assertLessEqual(self.status["shared_pe_dma_micro_bypass_cycles"], 602)
        self.assertLessEqual(self.status["shared_pe_dma_micro_enabled_cycles"], 621)
        self.assertGreater(self.status["shared_pe_dma_micro_enabled_cycles"], self.status["shared_pe_dma_micro_bypass_cycles"])
        self.assertIn("module shared_reconfigurable_pe_slice", pe)
        # Packed P dot3 retains a shared scalar multiplier; the two additional
        # products are P-only. Do not confuse the packed bus with a 96-bit MAC.
        self.assertIn("selected_product=$signed(selected_lhs[ARITH_W-1:0])*$signed(selected_rhs[ARITH_W-1:0])", pe)
        self.assertIn("parameter bit P_DOT3=1'b0", pe)
        self.assertIn("selected_client==CLIENT_P&&selected_op_mac", pe)
        self.assertIn("assign product1=$signed(p_lhs_i[63:32])*$signed(p_rhs_i[63:32])", pe)
        self.assertIn("assign product2=$signed(p_lhs_i[95:64])*$signed(p_rhs_i[95:64])", pe)
        self.assertIn("selected_less=key_less", pe)
        self.assertIn("shared_reconfigurable_pe_slice", frame)
        self.assertIn("stable_group_sorter_shared_compare", frame)
        self.assertIn("gaussian_depth_prepass_shared_mac", frame)
        self.assertIn("group_weight_o(group_weight)", frame)
        self.assertIn("shared_math_owner_o(shared_math_owner)", frame)
        self.assertIn("mode_commit_pulse_o", frame)
        self.assertIn("USE_SHARED_PROJECTION_PE(USE_SHARED_PE&&USE_SHARED_PROJECTION_PE)", frame)

    def test_automatic_strategy_status_matches_real_report(self):
        report = json.loads(
            (
                ROOT
                / "experiments/real_mode_calibration/validation_20260911_13scenes_n32/report.json"
            ).read_text(encoding="utf-8")
        )["aggregate"]
        self.assertTrue(self.status["automatic_mode_functional_pass"])
        self.assertFalse(self.status["automatic_mode_performance_pass"])
        self.assertFalse(self.status["automatic_mode_performance_report_matches_current_rtl"])
        self.assertEqual(report["auto_matches_best_count"], 0)
        self.assertEqual(report["auto_within_one_percent_count"], 12)
        self.assertEqual(report["workload_count"], 13)
        self.assertEqual(
            self.status["automatic_mode_exact_oracle"], {"passed": 0, "total": 13}
        )
        self.assertEqual(
            self.status["automatic_mode_within_one_percent"],
            {"passed": 12, "total": 13},
        )

    def test_final_quality_and_ppa_are_not_marked_complete(self):
        self.assertFalse(self.status["ground_truth_quality_signed_off"])
        self.assertFalse(self.status["ppa_signed_off"])
        self.assertFalse(self.status["full_scene_global_sort_is_software_preprocessed"])
        self.assertTrue(self.status["legacy_pre_t06_global_sort_is_software_preprocessed"])
        self.assertFalse(self.status["t06_cpu_sort_pivot_batch_allowed"])
        self.assertTrue(self.status["parallel_group_sort_integrated"])
        self.assertFalse(self.status["t05_full_chip_ppa_signed_off"])

    def test_t00_contract_is_signed_and_executable(self):
        contract = (ROOT / self.status["t00_contract_path"]).read_text(encoding="utf-8")
        self.assertEqual(self.status["t00_contract_status"], "COMPLETE")
        self.assertTrue(self.status["t00_contract_signed_off"])
        self.assertEqual(self.status["t00_external_decisions_pending"], [])
        self.assertEqual(self.status["t00_asic_signoff_level"], "standard_cell_logic_synthesis_sta_area_activity_power")
        self.assertFalse(self.status["t00_physical_design_required"])
        self.assertEqual(self.status["t00_target_pdks"], ["ICsprout55", "FreePDK45"])
        self.assertEqual(self.status["t00_pvt_corners"], ["ss", "tt", "ff"])
        self.assertEqual(self.status["t00_frequency_mhz"]["pass_min"], 200)
        self.assertEqual(self.status["t00_frame_rate_fps_min"], 30)
        self.assertEqual(self.status["t00_formal_workload"]["min_total_frames"], 65)
        self.assertEqual(self.status["t00_ppa_limits"]["area_mm2_max"], 4.0)
        self.assertEqual(self.status["t00_ppa_limits"]["core_power_w_max"], 1.0)
        self.assertIn("T00 于 2026-09-29 签核完成", contract)
        self.assertIn("PSNR 下降 ≤0.5 dB", contract)


if __name__ == "__main__":
    unittest.main()
