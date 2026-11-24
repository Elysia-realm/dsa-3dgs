"""Current corrected release gates; never accept the old flat-image equivalence."""
import hashlib,json,unittest
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'experiments/t06_20261017'
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
    def test_complete_corrected_frames_oracles_and_float_semantics(self):
        r=read(BASE/'full_render/report.json');self.assertEqual(r['status'],'PASS');self.assertEqual(len(r['results']),5)
        for x in r['results']:
            check_sources(self,x);self.assertTrue(x['full_scene']);self.assertTrue(x['independent_sort_rgb_matches']);self.assertEqual(x['width'],128)
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
