"""The release gate must reject missing files, hash drift and disabled features."""
import unittest
from scripts.t06_release_common import OLD,profile,assert_command_profile,check_frozen_sources
from scripts.run_t06_perf_optimization import read
from scripts.audit_t06_release import verify_sources

class ReleaseGateTests(unittest.TestCase):
    def test_pinned_selected_profile_matches_executed_candidate(self):
        config=assert_command_profile(read(OLD/'build/H/command.json'))
        self.assertEqual(config,profile()['parameters'])
        self.assertEqual(config['AUTO_QSU_PRECOUNT_CHILDREN'],1)
        self.assertGreater(len(check_frozen_sources()),80)
    def test_disabled_qsu_candidate_rejected(self):
        command=read(OLD/'build/H/command.json');command[-1]=command[-1].replace('-DTB_QSU_PRECOUNT=1','-DTB_QSU_PRECOUNT=0')
        with self.assertRaises(AssertionError):assert_command_profile(command)
    def test_disabled_final_rgb_rejected(self):
        command=read(OLD/'build/H/command.json');command[-1]=command[-1].replace('-DTB_FINAL_RGB=1','-DTB_FINAL_RGB=0')
        with self.assertRaises(AssertionError):assert_command_profile(command)
    def test_source_hash_mismatch_rejected(self):
        with self.assertRaises(AssertionError):verify_sources({'rtl/sort/autonomous_qsu.sv':'0'*64})
    def test_missing_source_rejected(self):
        with self.assertRaises(FileNotFoundError):verify_sources({'rtl/t06_missing_release_source.sv':'0'*64})
    def test_empty_source_manifest_rejected(self):
        with self.assertRaises(AssertionError):verify_sources({})

if __name__=='__main__':unittest.main()
