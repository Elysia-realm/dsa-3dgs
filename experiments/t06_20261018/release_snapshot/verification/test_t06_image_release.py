"""Current corrected release gates; never accept the old flat-image equivalence."""
import hashlib,json,unittest
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'experiments/t06_20261018'
NAMES=['bonsai','counter','room','kitchen','garden']
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1<<20),b''):h.update(b)
    return h.hexdigest()
def check_sources(test,r):
    for f,h in r['source_sha256'].items():test.assertEqual(sha(ROOT/f),h,f)
class T06CorrectedReleaseTests(unittest.TestCase):
    def test_reused_qsu_boundaries_and_synthesizability(self):
        old=ROOT/'experiments/t06_20261014'
        units=read(old/'units_v2/report.json');check_sources(self,units)
        self.assertEqual(units['status'],'PASS');self.assertEqual(len(units['results']),16)
        for row in units['results']:self.assertEqual(row['status'],'PASS');self.assertIn('PASS T06',row['result'])
        synth=read(old/'synthesis_v2/report.json');check_sources(self,synth)
        self.assertEqual(synth['status'],'PASS');self.assertEqual(len(synth['results']),2)
        self.assertEqual(synth['dfs_entries'],218);self.assertEqual(synth['dual_leaf_payload_bits'],2912)
        self.assertIn('qsu_busy=0 BSU_busy=1',(ROOT/'tmp/t06_abort_before_fix.log').read_text())
    def test_disjoint_common_address_space_evidence(self):
        units=read(BASE/'memory_layout_units/report.json');check_sources(self,units)
        self.assertEqual(units['status'],'PASS');self.assertEqual(len(units['results']),7)
        for kind,count in [('subset',40),('full_render',5)]:
            r=read(BASE/kind/'memory_layout_report.json');check_sources(self,r)
            self.assertEqual(r['status'],'PASS');self.assertEqual(r['cases'],count)
            self.assertTrue(r['address_ranges_disjoint']);self.assertTrue(r['relocation_rgb_unchanged'])
            self.assertIn('verification/rtl/t06_memory_layout.svh',r['source_sha256'])
        for n in NAMES:
            for kind in ['production_v2','oracle']:
                log=(BASE/'full_render'/n/kind/'run.log').read_text()
                self.assertIn('disjoint=1',log)
                self.assertIn('scratch=0000000060000000 output=0000000070000000',log)
    def test_semantic_counterexamples_and_source_layout(self):
        r=read(BASE/'unit_checks/report.json');self.assertEqual(r['status'],'PASS');check_sources(self,r)
        self.assertEqual(r['rtl_clamp_transactions'],8);self.assertEqual(r['python_tests'],8)
        r=read(BASE/'input_encoding_report.json');self.assertEqual(r['status'],'PASS');self.assertEqual(len(r['results']),10)
        for x in r['results']:self.assertGreaterEqual(x['SH_fields_checked'],48*14)
    def test_current_protocol_and_integrated_regression(self):
        p=read(BASE/'protocol/report.json');self.assertEqual(p['status'],'PASS');self.assertEqual(len(p['results']),15);check_sources(self,p)
        log=(ROOT/'tmp/t06_image_fix_regression.log').read_text(errors='replace')
        self.assertEqual(log.count('PASS: tb_'),80);self.assertIn('PASS: all configured',log)
        self.assertIn('PASS: Verilator lint completed',(ROOT/'tmp/t06_image_fix_lint.log').read_text(errors='replace'))
    def test_all_forty_current_real_subsets(self):
        r=read(BASE/'subset/report.json');self.assertEqual(r['status'],'PASS');self.assertEqual(len(r['results']),40)
        self.assertEqual({(x['scene'],x['mode'],x['profile']) for x in r['results']},{(n,m,p) for n in NAMES for m in range(4) for p in ['ideal','limited']})
        for x in r['results']:
            check_sources(self,x);self.assertFalse(x['full_scene']);self.assertEqual(x['width'],128)
            self.assertIn('verification/rtl/tb_t06_memory_workload.sv',x['source_sha256'])
            p=BASE/'subset'/x['scene']/f'm{x["mode"]}_{x["profile"]}'
            self.assertEqual(sha(p/'frame.rgb'),x['rgb_sha256']);self.assertEqual((p/'frame.rgb').read_bytes(),(p.parent/'oracle/frame.rgb').read_bytes())
            self.assertEqual((p/'sorted.txt').read_bytes(),(p.parent/'expected_sorted.txt').read_bytes())
    def test_independent_float_subsets_and_complete_input_hashes(self):
        for root in ['subset','full_render']:
            for n in NAMES:
                folder=BASE/root/n;m=read(folder/'manifest.json');self.assertEqual(m['width'],128)
                for f,h in m['input_sha256'].items():self.assertEqual(sha(folder/f),h,str(folder/f))
        for n in NAMES:
            f=read(BASE/'float_subset'/n/'float_floor_0.30078125_jac_clamp.json')
            self.assertTrue(f['jacobian_fov_clamp']);self.assertLessEqual(f['rtl_mae_rgb8'],2);self.assertLessEqual(f['rtl_active_mae_rgb8'],5)
            # Recompute on NEW DMA bytes, not only the old diagnostic JSON.
            a=np.asarray(Image.open(BASE/'subset'/n/'m0_ideal/frame.png'),dtype=float)
            b=np.asarray(Image.open(BASE/'float_subset'/n/'float_floor_0.30078125_jac_clamp.png'),dtype=float)
            delta=np.abs(a-b);active=np.any((a>0)|(b>0),axis=-1)
            self.assertLessEqual(float(delta.mean()),2);self.assertTrue(active.any())
            self.assertLessEqual(float(delta[active].mean()),5)
    def test_complete_corrected_frames_oracles_and_float_semantics(self):
        r=read(BASE/'full_render/report.json');self.assertEqual(r['status'],'PASS');self.assertEqual(len(r['results']),5)
        for x in r['results']:
            check_sources(self,x);self.assertTrue(x['full_scene']);self.assertTrue(x['independent_sort_rgb_matches']);self.assertEqual(x['width'],128)
            self.assertIn('verification/rtl/tb_t06_memory_workload.sv',x['source_sha256'])
            folder=BASE/'full_render'/x['scene'];prod=folder/'production_v2';oracle=folder/'oracle'
            check_sources(self,read(oracle/'result.json'));self.assertEqual((prod/'frame.rgb').read_bytes(),(oracle/'frame.rgb').read_bytes())
            self.assertEqual((prod/'frame.rgb').read_bytes(),Image.open(prod/'frame.png').tobytes())
            self.assertEqual((prod/'frame.rgb').read_bytes(),bytes(int(v,16) for v in (prod/'rgb.memh').read_text().split()))
            self.assertEqual((prod/'sorted.txt').read_bytes(),(folder/'expected_sorted.txt').read_bytes())
            float_png=BASE/'float_full'/x['scene']/'float_floor_0.30078125_jac_clamp.png'
            a=np.asarray(Image.open(prod/'frame.png'),dtype=np.float64);b=np.asarray(Image.open(float_png),dtype=np.float64)
            self.assertEqual(a.shape,b.shape);self.assertLessEqual(float(np.mean(np.abs(a-b))),5,'large full-frame semantic disagreement '+x['scene'])
        check_sources(self,read(BASE/'float_full/report.json'))
    def test_no_signoff_without_current_visual_review(self):
        state=read(ROOT/'verification/implementation_status.json')
        if state['t06_signed_off']:
            r=read(BASE/'audit.json');self.assertEqual(r['status'],'COMPLETE_FUNCTIONAL')
            visual=read(BASE/'visual_review.json');self.assertEqual(set(visual['reviewed_scenes']),set(NAMES))
            for n,h in visual['current_rgb_hashes'].items():self.assertEqual(sha(BASE/'full_render'/n/'production_v2/frame.rgb'),h)
        else:self.assertNotEqual(state['t06_status'],'COMPLETE')
if __name__=='__main__':unittest.main()
