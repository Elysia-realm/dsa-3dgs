"""Strict release gates: missing/partial full-scene evidence is a failure, not PASS."""
import hashlib,json,random,re,unittest
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'experiments/t06_20261014'
SCENES=['bonsai','counter','room','kitchen','garden']
COUNTS={'bonsai':1244819,'counter':1222956,'room':1593376,'kitchen':1852335,'garden':5834784}
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1<<20),b''):h.update(b)
    return h.hexdigest()
class T06EvidenceTests(unittest.TestCase):
    def check_sources(self,mapping,base=ROOT):
        for f,h in mapping.items():self.assertEqual(sha(base/f),h,str(base/f))
    def test_units_and_atomic_leaf_fault_regression(self):
        r=read(BASE/'units_v2/report.json');self.assertEqual(r['status'],'PASS');self.assertEqual(len(r['results']),16)
        self.check_sources(r['source_sha256'])
        p=read(BASE/'protocol_v2/report.json');self.assertEqual(p['status'],'PASS');self.assertEqual(len(p['results']),15)
        self.check_sources(p['source_sha256'])
        for row in p['results']:self.assertIn('PASS T06',(BASE/'protocol_v2'/row['log']).read_text())
        before=(ROOT/'tmp/t06_abort_before_fix.log').read_text()
        self.assertIn('qsu_busy=0 BSU_busy=1',before)
    def test_autonomous_subset_release_all_modes_and_axi(self):
        r=read(BASE/'release_subset/latest_run.json');self.assertEqual(r['status'],'PASS');self.assertEqual(len(r['results']),40)
        expected={(n,m,p) for n in SCENES for m in range(4) for p in ['ideal','limited']}
        self.assertEqual({(x['scene'],x['mode'],x['profile']) for x in r['results']},expected)
        order=list(range(512));random.Random(60614).shuffle(order)
        for name in SCENES:
            folder=BASE/'release_subset'/name;m=read(folder/'manifest.json')
            self.assertFalse(m['full_scene']);self.assertEqual(m['gaussians'],512)
            for f,h in m['input_sha256'].items():self.assertEqual(sha(folder/f),h)
            words=[int(x,16) for x in (folder/'mean.memh').read_text().split()]
            self.assertEqual([w&0xffffffff for w in words],order)
            camera=[int(x,16) for x in (folder/'camera.memh').read_text().split()]
            self.assertEqual(camera[22:25],[0,0,0])
        for x in r['results']:
            self.check_sources(x['source_sha256'])
            folder=BASE/'release_subset'/x['scene']/f'pipe1_m{x["mode"]}_{x["profile"]}'
            cmd=read(folder/'command.json');self.assertIn('+AUTO_QSU',cmd);self.assertFalse(any('BATCH_ROOT' in a for a in cmd))
            trace=[[int(v) for v in line.split()] for line in (folder/'sorted.txt').read_text().splitlines()]
            self.assertEqual(trace,read(folder.parent/'manifest.json')['expected_sorted_stream'])
            self.assertEqual(x['qsu']['input'],512);self.assertGreater(x['qsu']['partitions'],0)
            self.assertEqual(x['qsu']['reads'],x['qsu']['axi_reads']);self.assertEqual(x['qsu']['writes'],x['qsu']['axi_writes'])
            raw=(folder/'frame.rgb').read_bytes();self.assertEqual(sha(folder/'frame.rgb'),x['rgb_sha256'])
            self.assertEqual(raw,bytes(int(v,16) for v in (folder/'rgb.memh').read_text().split()))
            self.assertEqual(Image.open(folder/'frame.png').tobytes(),raw)
            self.assertIn('error=00000000',(folder/'run.log').read_text())
    def test_complete_model_global_order_current_rtl(self):
        for name in SCENES:
            folder=BASE/'full_order'/name;m=read(folder/'manifest.json');r=read(folder/'result_v2.json')
            self.assertEqual(r['status'],'PASS');self.assertEqual(r['gaussians'],COUNTS[name]);self.assertTrue(m['full_scene'])
            self.check_sources(r['source_sha256']);self.assertEqual(sha(folder/'input.memh'),m['input_sha256'])
            self.assertEqual(sha(folder/'expected.memh'),m['expected_sha256'])
            self.assertIn(f'PASS T06 n={COUNTS[name]}',(folder/'run_v2.log').read_text())
    def test_complete_production_frames_and_independent_rgb_oracle(self):
        for name in SCENES:
            folder=BASE/'full_render'/name;m=read(folder/'manifest.json');run=folder/'production_v2'
            r=read(run/'result.json');self.assertIn(r['status'],['PASS_DATAPATH_PENDING_IMAGE_ORACLE','PASS'])
            self.assertEqual(r['gaussians'],COUNTS[name]);self.assertTrue(r['full_scene']);self.check_sources(r['source_sha256'])
            self.assertEqual(r['visible'],m['visible']);self.assertEqual(r['qsu']['input'],m['visible'])
            self.assertEqual((run/'sorted.txt').read_bytes(),(folder/'expected_sorted.txt').read_bytes())
            for f,h in m['input_sha256'].items():self.assertEqual(sha(folder/f),h)
            self.assertEqual(sha(folder/'expected_sorted.txt'),m['oracle_sha256'])
            oracle=read(folder/'oracle/result.json');self.assertEqual(oracle['status'],'PASS_ORACLE');self.assertFalse(oracle['autonomous'])
            self.check_sources(oracle['source_sha256'],BASE/'pre_leaf_buffer_snapshot')
            raw=(run/'frame.rgb').read_bytes();self.assertEqual(sha(run/'frame.rgb'),r['rgb_sha256'])
            self.assertEqual(raw,(folder/'oracle/frame.rgb').read_bytes())
            self.assertEqual(raw,bytes(int(v,16) for v in (run/'rgb.memh').read_text().split()))
            self.assertEqual(Image.open(run/'frame.png').tobytes(),raw)
            self.assertIn('error=00000000',(run/'run.log').read_text())
            log=(run/'run.log').read_text()
            bsu={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',next(line for line in log.splitlines() if line.startswith('REAL_SORT_WORK')))}
            n=r['qsu']['leaves'];self.assertEqual(bsu['caps'],0x00100019)
            self.assertEqual((bsu['shared'],bsu['local'],bsu['phases'],bsu['groups']),(n,79*n,10*n,n))
            self.assertGreater(bsu['phase_grants'],0);self.assertGreater(bsu['fallback'],0)
    def test_synthesis_and_integrated_regressions(self):
        r=read(BASE/'synthesis_v2/report.json');self.assertEqual(r['status'],'PASS');self.assertEqual(len(r['results']),2)
        self.check_sources(r['source_sha256'])
        for x in r['results']:self.assertEqual(sha(BASE/'synthesis_v2'/f'{x["module"]}.il'),x['rtlil_sha256'])
        log=(ROOT/'tmp/t06_release_regression.log').read_text(errors='replace')
        self.assertEqual(log.count('PASS: tb_'),80);self.assertIn('PASS: all configured',log)
        self.assertIn('PASS: Verilator lint completed',(ROOT/'tmp/t06_release_lint.log').read_text(errors='replace'))
    def test_signoff_never_claimed_for_partial_evidence(self):
        state=read(ROOT/'verification/implementation_status.json')
        if state['t06_signed_off']:
            audit=read(ROOT/state['t06_audit_report']);self.assertEqual(audit['status'],'COMPLETE_FUNCTIONAL')
            self.assertEqual(audit['full_model_autonomous_frames'],5);self.assertEqual(audit['full_model_rgb_oracle_matches'],5)
        else:self.assertNotEqual(state['t06_status'],'COMPLETE')
if __name__=='__main__':unittest.main()
