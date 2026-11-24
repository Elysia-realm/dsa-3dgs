from __future__ import annotations

import random
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.rtl_contract import (
    ConfigEpochModel,
    DirectMappedTerminationTableModel,
    ElasticPipelineModel,
    PixelTerminationMaskModel,
    SaturatingCounterBankModel,
    TerminationHierarchyModel,
)


class StreamContractTests(unittest.TestCase):
    def test_random_backpressure_preserves_every_transaction(self):
        rng = random.Random(20260804)
        model = ElasticPipelineModel(stages=4)
        source = list(range(500))
        accepted = []
        committed = []
        source_index = 0
        for _ in range(10000):
            value = source[source_index] if source_index < len(source) else None
            ready, output, valid = model.step(value, output_ready=rng.random() < 0.61)
            if value is not None and ready:
                accepted.append(value)
                source_index += 1
            if valid and output is not None and output not in committed:
                # The output is counted only when the randomized sink accepted
                # it; infer acceptance from disappearance on the next cycle is
                # deliberately avoided by using an always-ready drain below.
                pass
            if source_index == len(source):
                break
        for _ in range(10000):
            _, output, valid = model.step(None, output_ready=True)
            if valid:
                committed.append(output)
            if all(value is None for value in model.pipeline) and not model.skid:
                break
        # Re-run with a sink acceptance trace that is explicit and exhaustive.
        model = ElasticPipelineModel(stages=4)
        source_index = 0
        committed = []
        for cycle in range(20000):
            value = source[source_index] if source_index < len(source) else None
            sink_ready = rng.random() < 0.61 or source_index == len(source)
            ready, output, valid = model.step(value, sink_ready)
            if value is not None and ready:
                source_index += 1
            if valid and sink_ready:
                committed.append(output)
            if source_index == len(source) and len(committed) == len(source):
                break
        self.assertEqual(committed, source)


class ConfigContractTests(unittest.TestCase):
    def test_commit_waits_for_safe_boundary(self):
        model = ConfigEpochModel()
        self.assertFalse(model.step(shadow_write=3, commit=True))
        self.assertEqual(model.active, 0)
        self.assertTrue(model.pending)
        self.assertFalse(model.step(epoch_boundary=True, affected_empty=False))
        self.assertTrue(model.step(epoch_boundary=True, affected_empty=True))
        self.assertEqual(model.active, 3)
        self.assertEqual(model.epoch, 1)

    def test_same_cycle_write_and_commit_is_atomic(self):
        model = ConfigEpochModel()
        self.assertTrue(model.step(shadow_write=2, commit=True, epoch_boundary=True, affected_empty=True))
        self.assertEqual(model.active, 2)

    def test_repeated_pending_commit_sets_sticky_overrun(self):
        model = ConfigEpochModel()
        model.step(commit=True)
        model.step(commit=True)
        self.assertTrue(model.overrun)


class CounterContractTests(unittest.TestCase):
    def test_saturation_clear_and_coherent_snapshot(self):
        model = SaturatingCounterBankModel(count=2, width=3)
        for _ in range(10):
            model.step([True, False])
        self.assertEqual(model.live, [7, 0])
        model.step([False, True], snapshot=True)
        self.assertEqual(model.snapshot, [7, 0])
        self.assertEqual(model.live, [7, 1])
        model.step([True, True], clear=True)
        self.assertEqual(model.live, [0, 0])


class TerminationTableContractTests(unittest.TestCase):
    def test_update_makes_matching_block_and_epoch_terminated(self):
        model = DirectMappedTerminationTableModel(num_banks=4, rows_per_bank=8)
        self.assertFalse(model.query(19, 7))
        model.update(19, 7)
        self.assertTrue(model.query(19, 7))

    def test_epoch_tag_lazy_invalidates_old_state(self):
        model = DirectMappedTerminationTableModel(num_banks=4, rows_per_bank=8)
        model.update(19, 7)
        self.assertFalse(model.query(19, 8))

    def test_capacity_alias_never_causes_false_positive(self):
        model = DirectMappedTerminationTableModel(num_banks=4, rows_per_bank=8)
        first = 3
        alias = first + model.num_banks * model.rows_per_bank
        self.assertEqual(model.address(first), model.address(alias))
        model.update(first, 2)
        self.assertFalse(model.query(alias, 2))
        model.update(alias, 2)
        self.assertFalse(model.query(first, 2))
        self.assertTrue(model.query(alias, 2))

    def test_same_address_update_is_write_through(self):
        model = DirectMappedTerminationTableModel(num_banks=4, rows_per_bank=8)
        self.assertTrue(model.query_update_same_cycle(11, 5, 11, 5))

    def test_random_trace_has_no_false_positive(self):
        rng = random.Random(77)
        model = DirectMappedTerminationTableModel(num_banks=8, rows_per_bank=16)
        exact = set()
        for _ in range(10000):
            block = rng.randrange(4096)
            epoch = rng.randrange(8)
            if rng.random() < 0.35:
                model.update(block, epoch)
                exact.add((block, epoch))
            result = model.query(block, epoch)
            if result:
                self.assertIn((block, epoch), exact)


class PixelMaskContractTests(unittest.TestCase):
    def test_updates_are_monotonic_and_full_pulses_once(self):
        model = PixelTerminationMaskModel(entries=16, pixels=64)
        self.assertFalse(model.update(3, 7, 0xF))
        self.assertEqual(model.query(3, 7), 0xF)
        self.assertFalse(model.update(3, 7, 0xF0))
        self.assertEqual(model.query(3, 7), 0xFF)
        self.assertTrue(model.update(3, 7, model.full_mask ^ 0xFF))
        self.assertFalse(model.update(3, 7, 1))

    def test_epoch_change_starts_with_empty_mask(self):
        model = PixelTerminationMaskModel(entries=16)
        model.update(5, 2, 0xFFFF)
        self.assertEqual(model.query(5, 3), 0)

    def test_capacity_alias_cannot_inherit_mask(self):
        model = PixelTerminationMaskModel(entries=16)
        model.update(5, 2, 0xFFFF)
        alias = 5 + 16
        self.assertEqual(model.query(alias, 2), 0)
        model.update(alias, 2, 1)
        self.assertEqual(model.query(5, 2), 0)

    def test_same_cycle_write_through_returns_merged_mask(self):
        model = PixelTerminationMaskModel(entries=16)
        model.update(1, 4, 0x03)
        mask, pulse = model.query_update_same_cycle(1, 4, 0x0C)
        self.assertEqual(mask, 0x0F)
        self.assertFalse(pulse)

    def test_random_updates_never_clear_a_bit(self):
        rng = random.Random(91)
        model = PixelTerminationMaskModel(entries=32)
        previous = {}
        for _ in range(5000):
            block = rng.randrange(512)
            epoch = rng.randrange(4)
            new_bits = rng.getrandbits(64)
            old = model.query(block, epoch)
            model.update(block, epoch, new_bits)
            current = model.query(block, epoch)
            self.assertEqual(current | old, current)
            previous[(block, epoch)] = current


class TerminationHierarchyContractTests(unittest.TestCase):
    def test_only_first_full_mask_updates_coarse_table(self):
        model = TerminationHierarchyModel(mask_entries=16, rows_per_bank=8)
        self.assertFalse(model.update_pixels(3, 9, 0xFF))
        self.assertFalse(model.block_terminated(3, 9))
        self.assertTrue(model.update_pixels(3, 9, model.pixel.full_mask ^ 0xFF))
        self.assertTrue(model.block_terminated(3, 9))
        self.assertFalse(model.update_pixels(3, 9, 1))

    def test_new_epoch_does_not_inherit_either_level(self):
        model = TerminationHierarchyModel(mask_entries=16, rows_per_bank=8)
        model.update_pixels(5, 2, model.pixel.full_mask)
        self.assertFalse(model.block_terminated(5, 3))
        self.assertEqual(model.pixel.query(5, 3), 0)


class RtlStructureTests(unittest.TestCase):
    def test_expected_modules_and_assertions_exist(self):
        modules = {
            "rtl/common/rv_reg_slice.sv": "module rv_reg_slice",
            "rtl/common/rv_skid_buffer.sv": "module rv_skid_buffer",
            "rtl/control/cfg_epoch_ctrl.sv": "module cfg_epoch_ctrl",
            "rtl/control/gaussian_mode_advisor.sv": "module gaussian_mode_advisor",
            "rtl/control/sat_counter_bank.sv": "module sat_counter_bank",
            "rtl/sort/group_sort_service_gate.sv": "module group_sort_service_gate",
            "rtl/raster/raster_pair_shell.sv": "module raster_pair_shell",
            "rtl/raster/block_termination_bank.sv": "module block_termination_bank",
            "rtl/raster/block_termination_table.sv": "module block_termination_table",
            "rtl/raster/raster_termination_filter.sv": "module raster_termination_filter",
            "rtl/raster/pixel_termination_mask.sv": "module pixel_termination_mask",
            "rtl/raster/alpha_block_float_core.sv": "module alpha_block_float_core",
            "rtl/raster/blend_fixed_core.sv": "module blend_fixed_core",
            "rtl/raster/image_state_store.sv": "module image_state_store",
            "rtl/raster/blend_state_commit.sv": "module blend_state_commit",
            "rtl/memory/sram_1r1w_wrapper.sv": "module sram_1r1w_wrapper",
            "rtl/control/apb_regfile.sv": "module apb_regfile",
            "rtl/gs_accel_top.sv": "module gs_accel_top",
            "rtl/gs_accel_system_top.sv": "module gs_accel_system_top",
        }
        for relative, declaration in modules.items():
            text = (ROOT / relative).read_text(encoding="utf-8")
            self.assertIn(declaration, text)
            self.assertNotIn("#delay", text)
        self.assertIn("assert property", (ROOT / "rtl/common/rv_reg_slice.sv").read_text(encoding="utf-8"))
        self.assertIn("assert property", (ROOT / "rtl/control/cfg_epoch_ctrl.sv").read_text(encoding="utf-8"))

    def test_dynamic_resource_table_has_safe_parameterized_lane_counts(self):
        text = (ROOT / "rtl/control/gaussian_resource_mode_table.sv").read_text(encoding="utf-8")
        for token in ("GROUP_ALL_COUNT", "PROJECTION_HALF_COUNT", "SH_HALF_COUNT",
                      "RASTER_ALL_COUNT", "all physical lane counts must be positive",
                      "active-lane count width cannot represent the physical lane count"):
            self.assertIn(token, text)
        self.assertNotIn("tile_bin", text.lower())

    def test_group_sort_service_gate_preserves_gaussian_wise_ordered_path(self):
        gate = (ROOT / "rtl/sort/group_sort_service_gate.sv").read_text(encoding="utf-8")
        for token in ("PHYSICAL_LANES time slots", "service_grant_o",
                      "service_stall_o", "m_valid_o && !m_ready_i |=>"):
            self.assertIn(token, gate)
        frame = (ROOT / "rtl/gaussian_frame_render_pipeline.sv").read_text(encoding="utf-8")
        self.assertIn("u_group_sort_service", frame)
        self.assertLess(frame.index("depth_group_buffer"), frame.index("group_sort_service_gate"))
        self.assertLess(frame.index("group_sort_service_gate"), frame.index("stable_group_sorter"))
        self.assertNotIn("tile_bin", frame.lower())

    def test_termination_payload_memory_has_no_bulk_data_reset(self):
        text = (ROOT / "rtl/raster/block_termination_bank.sv").read_text(encoding="utf-8")
        reset_clause = text.split("if (!rst_ni)", 1)[1].split("end else", 1)[0]
        self.assertNotIn("tag_mem[index]", reset_clause)
        self.assertNotIn("epoch_mem[index]", reset_clause)
        pixel_text = (ROOT / "rtl/raster/pixel_termination_mask.sv").read_text(encoding="utf-8")
        pixel_reset = pixel_text.split("if (!rst_ni)", 1)[1].split("end else", 1)[0]
        self.assertNotIn("mask_mem[index]", pixel_reset)

    def test_raster_shell_connects_pixel_pulse_to_coarse_update(self):
        text = (ROOT / "rtl/raster/raster_pair_shell.sv").read_text(encoding="utf-8")
        self.assertIn("u_pixel_termination_mask", text)
        self.assertIn(".term_update_valid_i(block_terminated_pulse_o)", text)

    def test_alpha_core_is_psd_by_construction_and_uses_256_entry_lut(self):
        text = (ROOT / "rtl/raster/alpha_block_float_core.sv").read_text(encoding="utf-8")
        self.assertIn("axis0_square", text)
        self.assertIn("axis1_square", text)
        self.assertNotIn("conic01", text)
        lut = (ROOT / "rtl/raster/alpha_exp_lut_256.svh").read_text(encoding="utf-8")
        self.assertEqual(lut.count("8'd"), 256)

    def test_image_state_uses_full_tags_and_frame_controller_forbids_capacity_alias(self):
        text = (ROOT / "rtl/raster/image_state_store.sv").read_text(encoding="utf-8")
        self.assertIn("assert (PIXEL_W >= INDEX_W)", text)
        self.assertIn("tag_mem[query_index] == query_pixel_id_i", text)
        reset_clause = text.split("if (!rst_ni)", 1)[1].split("end else", 1)[0]
        for name in ("tag_mem[index]", "epoch_mem[index]", "r_mem[index]", "t_mem[index]"):
            self.assertNotIn(name, reset_clause)
        frame = (ROOT / "rtl/gaussian_frame_render_pipeline.sv").read_text(encoding="utf-8")
        self.assertIn("configured_pixels>STATE_ENTRIES", frame)
        self.assertIn("error_q[9]<=1'b1", frame)

    def test_system_top_exposes_sticky_done_error_and_maskable_irq(self):
        apb = (ROOT / "rtl/control/apb_regfile.sv").read_text(encoding="utf-8")
        for address in ("12'h02c", "12'h030", "12'h034", "12'h044"):
            self.assertIn(address, apb)
        self.assertIn("status_clear_pulse_o", apb)
        top = (ROOT / "rtl/gs_accel_system_top.sv").read_text(encoding="utf-8")
        self.assertIn("gaussian_frame_render_pipeline", top)
        self.assertIn("assign irq_o=|(irq_pending_q&irq_enable)", top)
        self.assertIn("if(frame_done_pulse_o)", top)
        self.assertIn("error_sticky_q<=error_sticky_q|{7'b0,final_rgb_error_status,4'b0", top)
        self.assertIn("state_read_error_status,write_error_status,attr_dma_error_status", top)
        self.assertIn("dma_error_status,completed_core_error_q}", top)

    def test_system_top_closes_automatic_mode_advisor_at_safe_epoch_boundary(self):
        advisor = (ROOT / "rtl/control/gaussian_mode_advisor.sv").read_text(encoding="utf-8")
        for token in ("sample_enable_i", "HYSTERESIS_WINDOWS", "MIN_RESIDENCE_WINDOWS",
                      "request_outstanding_o", "Preserve an outstanding recommendation"):
            self.assertIn(token, advisor)
        top = (ROOT / "rtl/gs_accel_system_top.sv").read_text(encoding="utf-8")
        for token in ("u_mode_advisor", "advisor_recommendation_ready",
                      "selected_runtime_mode_valid", "advisor_queue_valid_q",
                      ".sample_enable_i(core_frame_busy)",
                      ".runtime_mode_valid_i(selected_runtime_mode_valid)"):
            self.assertIn(token, top)
        frame = (ROOT / "rtl/gaussian_frame_render_pipeline.sv").read_text(encoding="utf-8")
        for token in ("event_group_pressure_o", "event_sort_busy_o",
                      "event_projection_busy_o", "event_raster_busy_o",
                      "event_block_candidate_o", "event_terminated_skip_o"):
            self.assertIn(token, frame)

    def test_mode_advisor_exports_atomic_window_telemetry_and_matrix(self):
        advisor = (ROOT / "rtl/control/gaussian_mode_advisor.sv").read_text(encoding="utf-8")
        for token in ("window_index_o", "window_group_count_o", "window_sort_count_o",
                      "window_projection_count_o", "window_raster_count_o",
                      "window_block_count_o", "window_skip_count_o"):
            self.assertIn(token, advisor)
        apb = (ROOT / "rtl/control/apb_regfile.sv").read_text(encoding="utf-8")
        for address in ("12'h048", "12'h04c", "12'h050", "12'h054",
                        "12'h058", "12'h05c", "12'h060"):
            self.assertIn(address, apb)
        bench = (ROOT / "verification/rtl/tb_gaussian_mode_advisor_workload_matrix.sv").read_text(
            encoding="utf-8"
        )
        for workload_class in ("class=G", "class=P", "class=R", "class=E", "class=BALANCED"):
            self.assertIn(workload_class, bench)
        matrix = (ROOT / "scripts/run_mode_advisor_matrix.py").read_text(encoding="utf-8")
        for token in ("advisor_matrix.csv", "advisor_matrix.json", "MATRIX_RE", '"result": "PASS"'):
            self.assertIn(token, matrix)

    def test_axi_mean_dma_preserves_gaussian_wise_two_pass_contract(self):
        dma = (ROOT / "rtl/dma/axi4_gaussian_mean_read_dma.sv").read_text(encoding="utf-8")
        for token in ("MAX_BURST_BEATS", "bytes_to_boundary", "m_axi_rresp_i",
                      "m_axi_rlast_i", "m_world_x_q16_o", "end_valid_o"):
            self.assertIn(token, dma)
        top = (ROOT / "rtl/gs_accel_system_top.sv").read_text(encoding="utf-8")
        self.assertIn("USE_AXI_MEAN_DMA", top)
        self.assertIn("axi4_gaussian_mean_read_dma", top)
        self.assertIn("gaussian_frame_render_pipeline", top)
        self.assertNotIn("tile_bin", dma.lower())
        apb = (ROOT / "rtl/control/apb_regfile.sv").read_text(encoding="utf-8")
        self.assertIn("12'h038", apb)
        self.assertIn("gaussian_count_o", apb)

    def test_t03_camera_base_drives_versioned_dma_and_safe_continuation(self):
        camera = (ROOT / "rtl/dma/axi4_camera_config_read_dma.sv").read_text(encoding="utf-8")
        for token in ("DESCRIPTOR_TAG=32'h47534301", "BEATS=14", "bytes_to_boundary",
                      "cfg_r00_q20_o", "cfg_depth_pivot2_q16_o", "format_error"):
            self.assertIn(token, camera)
        top = (ROOT / "rtl/gs_accel_system_top.sv").read_text(encoding="utf-8")
        for token in ("USE_AXI_CAMERA_DMA=1'b1", "axi4_camera_config_read_dma",
                      "command_state_q", "camera_descriptor_matches_command",
                      "camera_continuation_matches", "logical_camera_identity_q",
                      ".cfg_r00_q20_i(active_r00_q)"):
            self.assertIn(token, top)
        self.assertIn(".base_addr_i(cmd_camera_base_q)", top)
        self.assertIn("command_state_q==CMD_CAMERA&&!camera_busy", top)
        spec = (ROOT / "docs/命令与相机描述符规格_v1.md").read_text(encoding="utf-8")
        for token in ("0x47534301", "224 Byte", "| 19 |", "| 20 |", "| 21 |"):
            self.assertIn(token, spec)

    def test_sorted_gid_attribute_backend_is_atomic_and_axi_replaceable(self):
        issue = (ROOT / "rtl/sort/ordered_gaussian_attribute_issue.sv").read_text(encoding="utf-8")
        for token in ("attr_req_valid_o", "attr_req_ready_i", "attr_rsp_valid_i",
                      "attr_rsp_ready_o", "attr_data_q<=attr_rsp_data_i"):
            self.assertIn(token, issue)
        axi = (ROOT / "rtl/dma/axi4_gaussian_attribute_read_engine.sv").read_text(encoding="utf-8")
        for token in ("RECORD_BEATS=9", "RECORD_BYTES", "req_gid_i*RECORD_BYTES",
                      "bytes_to_boundary", "record_q[total_index_q*DATA_W+:DATA_W]"):
            self.assertIn(token, axi)
        pipe = (ROOT / "rtl/gaussian_sorted_render_pipeline.sv").read_text(encoding="utf-8")
        self.assertIn("USE_EXTERNAL_ATTR_BACKEND", pipe)
        self.assertIn("gaussian_attribute_sram_backend", pipe)
        top = (ROOT / "rtl/gs_accel_system_top.sv").read_text(encoding="utf-8")
        self.assertIn("USE_AXI_ATTR_DMA=1'b1", top)
        self.assertIn("axi4_gaussian_attribute_read_engine", top)
        self.assertNotIn("tile_bin", axi.lower())

    def test_ordered_pixel_writeback_waits_for_axi_response(self):
        write = (ROOT / "rtl/dma/axi4_pixel_state_write_engine.sv").read_text(encoding="utf-8")
        for token in ("s_pixel_id_i", "m_axi_awvalid_o", "m_axi_wvalid_o",
                      "m_axi_bready_o", "base_addr_i+", "s_pixel_id_i}<<SIZE_CODE"):
            self.assertIn(token, write)
        top = (ROOT / "rtl/gs_accel_system_top.sv").read_text(encoding="utf-8")
        self.assertIn("USE_AXI_PIXEL_WRITE=1'b1", top)
        self.assertIn("core_frame_busy||write_busy||state_read_busy||final_rgb_busy||completion_pending_q", top)
        self.assertIn("(completion_pending_q||core_frame_done)&&!write_busy&&!state_read_busy&&state_cache_idle", top)
        self.assertIn("axi4_pixel_state_write_buffer", top)
        self.assertIn("axi4_pixel_state_writeback_buffer", top)
        self.assertIn("axi4_pixel_state_multiwrite_buffer", top)
        self.assertIn("USE_PIXEL_WRITEBACK_BUFFER", top)
        self.assertIn("USE_PIXEL_MULTIWRITE_BUFFER", top)
        self.assertIn("write_lookup_hit", top)
        buffer = (ROOT / "rtl/dma/axi4_pixel_state_write_buffer.sv").read_text(encoding="utf-8")
        for token in ("axi4_pixel_state_write_engine", "occupancy_o!=0||writer_busy||active_valid_q",
                      "active_valid_q&&active_pixel_q==hazard_pixel_id_i", "pixel_mem[index]==hazard_pixel_id_i"):
            self.assertIn(token, buffer)
        writeback = (ROOT / "rtl/dma/axi4_pixel_state_writeback_buffer.sv").read_text(encoding="utf-8")
        for token in ("axi4_pixel_state_write_engine", "coalesced_count_o",
                      "lookup_hit_o", "active_valid_q", "flush_i"):
            self.assertIn(token, writeback)
        multiwrite = (ROOT / "rtl/dma/axi4_pixel_state_multiwrite_buffer.sv").read_text(encoding="utf-8")
        for token in ("outstanding_o", "peak_outstanding_o", "issue_fire", "b_fire",
                      "valid_q[lookup_index]", "pixel_mem[lookup_index]==hazard_pixel_id_i",
                      "m_axi_awvalid_o=issue_valid&&!aw_done_q",
                      "m_axi_wvalid_o=issue_valid&&!w_done_q"):
            self.assertIn(token, multiwrite)
        for token in ("ENABLE_LOOKUP_FORWARD", "lookup_pixel_id_i", "lookup_hit_o",
                      "lookup_data_o", "response_q+lookup_offset"):
            self.assertIn(token, multiwrite)
        self.assertIn("USE_PIXEL_MULTIWRITE_FORWARDING=1'b0", top)
        self.assertIn(".lookup_hit_o(write_lookup_hit)", top)

    def test_pixel_backing_cache_preserves_epoch_and_write_order(self):
        cache = (ROOT / "rtl/raster/image_state_cache_backend.sv").read_text(encoding="utf-8")
        for token in ("tag_mem", "epoch_mem", "miss_req_valid_o", "miss_rsp_valid_i",
                      "miss_rsp_data_i[70:55]==mshr_epoch_q", "update_valid_i",
                      "mshr_valid_q", "query_tag_i", "response_tag_o"):
            self.assertIn(token, cache)
        read = (ROOT / "rtl/dma/axi4_pixel_state_dual_read_engine.sv").read_text(encoding="utf-8")
        for token in ("req_pixel_id_i", "req_tag_i", "rsp_tag_o", "outstanding_q",
                      "m_axi_arvalid_o", "m_axi_rresp_i", "rid_known", "!m_axi_rlast_i"):
            self.assertIn(token, read)
        top = (ROOT / "rtl/gs_accel_system_top.sv").read_text(encoding="utf-8")
        self.assertIn("USE_STATE_CACHE_BACKEND=1'b1", top)
        self.assertIn("state_miss_req_valid&&!write_lookup_hit&&!write_hazard", top)
        self.assertIn("state_miss_req_ready=write_lookup_hit?!forward_rsp_valid_q", top)
        self.assertIn("forward_rsp_data_q<=write_lookup_data", top)
        self.assertIn("frame_capacity_ok=USE_STATE_CACHE_BACKEND||", top)
        for token in ("STATE_MSHR_COUNT=2", "if(STATE_MSHR_COUNT==2)",
                      "g_dual_state_read", "g_single_state_read",
                      "axi4_pixel_state_read_engine"):
            self.assertIn(token, top)

    def test_real_workload_programs_mode_and_exports_stage_probes(self):
        bench = (ROOT / "verification/rtl/tb_real_dma_workload.sv").read_text(encoding="utf-8")
        self.assertIn("apb_write(12'h008,frame_mode[1:0])", bench)
        self.assertIn("active_mode_o!==frame_mode[1:0]", bench)
        self.assertIn('REAL_STAGE mode=%0d lanes=%0d', bench)
        self.assertIn("group_service_stall_cycles", bench)
        self.assertIn("state_window_different_key_cycles", bench)
        self.assertIn("u_blend_state_commit.pixel_q[", bench)
        matrix = (ROOT / "scripts/run_rtl_workload_matrix.py").read_text(encoding="utf-8")
        for token in ("STAGE_RE", 'parser.add_argument("--lanes"',
                      'parser.add_argument("--frame-mode"', '"stage_cycles"',
                      '"state_window_different_key"'):
            self.assertIn(token, matrix)
        for token in ("BACKEND_RE", "WINDOW_OPP_RE", '"backend_cycles"',
                      '"window_opportunity"', '"third_distinct_mshr_two"'):
            self.assertIn(token, matrix)

    def test_real_workload_supports_automatic_observe_select_probe(self):
        bench = (ROOT / "verification/rtl/tb_real_dma_workload.sv").read_text(encoding="utf-8")
        for token in ('"AUTO_REPEAT_FRAMES=%d"', '"REAL_ADVISOR_WINDOW index=%0d',
                      '"REAL_AUTO observe_mode=%0d', "auto_observe_render_mem",
                      "image_mismatches", "32'h100|frame_mode[1:0]"):
            self.assertIn(token, bench)
        runner = (ROOT / "scripts/run_real_auto_mode_probe.py").read_text(encoding="utf-8")
        for token in ("WINDOW_RE", "AUTO_RE", "advisor_windows.csv", "report.json",
                      '"+AUTO_REPEAT_FRAMES=2"', '"frame_sha256"', '"--msys2-root"',
                      'run_env["PATH"]'):
            self.assertIn(token, runner)

    def test_real_mode_calibration_matrix_covers_fixed_and_automatic_modes(self):
        runner = (ROOT / "scripts/run_real_mode_calibration_matrix.py").read_text(
            encoding="utf-8"
        )
        for token in ("MODE_NAMES", "run_fixed_mode", "for mode in range(4)",
                      "run_real_auto_mode_probe.py", "fixed_hash_equal",
                      "auto_matches_best", "auto_within_one_percent", "summary.csv",
                      "winner_histogram", "all_auto_rgb_t_equal"):
            self.assertIn(token, runner)

    def test_real_workload_supports_sparse_two_batch_continuation(self):
        bench = (ROOT / "verification/rtl/tb_real_dma_workload.sv").read_text(encoding="utf-8")
        for token in ('"MEAN2=%s"', '"ATTR2=%s"', '"GLOBAL_GIDS2=%s"',
                      '"CAMERA2=%s"', "32'h11", "32'h9",
                      "intermediate continuation batch raised done",
                      "continuation changed epoch", "logical_frame_open_q",
                      'REAL_CONTINUATION enabled=%0d'):
            self.assertIn(token, bench)
        self.assertIn("attr_request_gid=attr_record_byte/144", bench)
        self.assertIn("global_gid_mem[attr_lookup_index]==attr_request_gid[31:0]", bench)

    def test_blend_commit_supports_ordered_same_cycle_replacement(self):
        text = (ROOT / "rtl/raster/blend_state_commit.sv").read_text(encoding="utf-8")
        for token in ("Two-entry ordered image-state transaction window",
                      "count_q<(enable_two_entries_i?2:1)", "commit_fire&&count_q",
                      "state_query_tag_o", "head_q", "tail_q",
                      "slot_state_q[head_q]==DONE"):
            self.assertIn(token, text)

    def test_phase_a_state_window_has_tagged_hit_under_miss_and_raw_cam(self):
        cache = (ROOT / "rtl/raster/image_state_cache_backend.sv").read_text(encoding="utf-8")
        for token in ("two tagged MSHRs", "query_hit?(response_space", "mshr_valid_q",
                      "mshr_issued_q", "miss_rsp_tag_i", "response_tag_o<=miss_rsp_tag_i"):
            self.assertIn(token, cache)
        window = (ROOT / "rtl/raster/blend_state_commit.sv").read_text(encoding="utf-8")
        for token in ("head_q", "tail_q", "query_slot=~head_q",
                      "{epoch_q[~head_q],pixel_q[~head_q]}!=",
                      "m_valid_o=count_q!=0&&slot_state_q[head_q]==DONE"):
            self.assertIn(token, window)

    def test_phase_a_and_phase_b_are_physical_generate_options(self):
        raster = (ROOT / "rtl/raster/raster_pair_shell.sv").read_text(encoding="utf-8")
        for token in ("STATE_MSHR_COUNT = 2", "STATE_MSHR_COUNT==2",
                      "image_state_cache_backend_single", "g_state_cache_single"):
            self.assertIn(token, raster)
        single = (ROOT / "rtl/raster/image_state_cache_backend_single.sv").read_text(encoding="utf-8")
        for token in ("one physical", "mshr_pixel_q", "mshr_epoch_q", "mshr_tag_q",
                      "miss_rsp_tag_i==mshr_tag_q", "architected update"):
            self.assertIn(token, single)
        matrix = (ROOT / "scripts/run_rtl_workload_matrix.py").read_text(encoding="utf-8")
        self.assertIn('parser.add_argument("--state-mshr-count"', matrix)
        self.assertIn('"state_mshr_count": args.state_mshr_count', matrix)

    def test_asic_baseline_constraint_is_explicitly_non_signoff(self):
        sdc = (ROOT / "asic/constraints/gs_accel_system_top.sdc").read_text(encoding="utf-8")
        for token in ("create_clock", "clk_i", "rst_ni", "set_clock_uncertainty",
                      "set_input_delay", "set_output_delay", "not signoff"):
            self.assertIn(token, sdc)
        readme = (ROOT / "asic/README.md").read_text(encoding="utf-8")
        for token in ("标准单元 `.lib`", "SRAM 宏", "PVT corner", "VCD 或 SAIF",
                      "当前结果仍未达到 PPA 签核"):
            self.assertIn(token, readme)


if __name__ == "__main__":
    unittest.main()
