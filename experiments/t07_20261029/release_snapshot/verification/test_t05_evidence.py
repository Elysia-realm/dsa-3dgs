"""Acceptance checks over real, unit and mapped T05 artifacts."""
import hashlib,json,re,unittest
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'experiments/t05_20261009'
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

class T05EvidenceTests(unittest.TestCase):
    def test_real_matrix_coverage_and_executed_resources(self):
        report=read(OUT/'real/report.json');self.assertEqual(report['status'],'PASS')
        results=report['results'];self.assertEqual(len(results),200)
        expected={(s,v,m,p) for s in ['bonsai','counter','room','kitchen','garden']
                  for v in ['bsu8','bsu16','linear','odd','bsu8_local_r'] for m in range(4) for p in ['ideal','limited']}
        self.assertEqual({(r['scene'],r['variant'],r['mode'],r['profile']) for r in results},expected)
        for r in results:
            with self.subTest(scene=r['scene'],variant=r['variant'],mode=r['mode'],profile=r['profile']):
                self.assertEqual(r['status'],'PASS');self.assertEqual(r['sorted_outputs'],512)
                self.assertEqual(r['P'],512*12)
                if r['variant'] in ('bsu8','bsu16','bsu8_local_r'):
                    k=16 if r['variant']=='bsu16' else 8;stages=10 if k==16 else 6
                    lanes=[4,2,2,1][r['mode']]
                    self.assertEqual(r['G'],64*stages*((k//2+lanes-1)//lanes))
                    fields=dict(re.findall(r'(\w+)=(\d+)',r['sort_work']))
                    self.assertEqual(int(fields['caps']),9+(k<<16))
                    self.assertEqual(int(fields['groups']),64)
                    self.assertEqual(int(fields['phases']),64*stages)
                    self.assertEqual(int(fields['shared'])+int(fields['local']),64*stages*k//2)
                    if r['variant']!='bsu8_local_r':self.assertGreater(r['R'],0)

    def test_archived_sources_and_all_real_input_hashes(self):
        report=read(OUT/'real/report.json')
        for relative,expected in report['source_sha256'].items():
            self.assertEqual(digest(OUT/'source_snapshot'/relative),expected,relative)
        for scene in ['bonsai','counter','room','kitchen','garden']:
            folder=OUT/'real'/scene;m=read(folder/'manifest.json')
            self.assertEqual(digest(Path(m['source_manifest'])),m['source_manifest_sha256'])
            for relative,expected in m['input_sha256'].items():self.assertEqual(digest(folder/relative),expected)
            # Inputs really are shuffled, not CPU's sorted oracle supplied unchanged.
            gids=[int(x,16) for x in (folder/'rtl_batch_0000/global_gid.memh').read_text().split()]
            self.assertNotEqual(gids,[row[1] for row in m['expected_sorted_stream'][:8]])

    def test_every_png_and_sorted_stream_are_exact(self):
        report=read(OUT/'real/report.json');scene_hashes={}
        for r in report['results']:
            folder=OUT/'real'/r['scene']/f"{r['variant']}_m{r['mode']}_{r['profile']}"
            raw=(folder/'frame.rgb').read_bytes()
            self.assertEqual(digest(folder/'frame.rgb'),r['rgb_sha256'])
            self.assertEqual(bytes(int(x,16) for x in (folder/'rgb.memh').read_text().split()),raw)
            image=Image.open(folder/'frame.png');w,h=r['width'],r['height'];stride=(w*3+15)&~15
            self.assertEqual(image.size,(w,h));self.assertEqual(len(raw),stride*h)
            self.assertEqual(image.tobytes(),b''.join(raw[y*stride:y*stride+w*3] for y in range(h)))
            log=(folder/'run.log').read_text();self.assertIn('error=00000000',log);self.assertIn('PASS: tb_real_dma_workload',log)
            expected=read(folder.parent/'manifest.json')['expected_sorted_stream']
            self.assertEqual([[int(x) for x in line.split()] for line in (folder/'sorted.txt').read_text().splitlines()],expected)
            scene_hashes.setdefault(r['scene'],set()).add(r['rgb_sha256'])
        self.assertTrue(all(len(hashes)==1 for hashes in scene_hashes.values()))

    def test_unit_sorters_and_real_mode_switches(self):
        module=read(OUT/'sorters/report.json');self.assertEqual(module['status'],'PASS')
        self.assertEqual({(r['k'],r['kind']) for r in module['results']},{(k,t) for k in (8,16) for t in (0,1,2)})
        for r in module['results']:
            self.assertEqual(r['groups'],660);self.assertEqual(r['status'],'PASS')
        reconfig=read(OUT/'reconfiguration/report.json');self.assertEqual(reconfig['status'],'PASS')
        self.assertEqual(len(reconfig['results']),5)
        for r in reconfig['results']:self.assertGreaterEqual(r['mode_changes'],2)
        self.assertGreater(sum(r['PR'] for r in reconfig['results']),0)
        cross=read(OUT/'simulator_equivalence/report.json');self.assertEqual(cross['status'],'PASS')
        self.assertTrue(cross['state_equal'] and cross['sorted_stream_equal'] and cross['rgb_equal'])

    def test_dual_library_mapping_has_real_netlists_and_no_unknown_cells(self):
        report=read(OUT/'mapping/report.json');self.assertEqual(report['status'],'PASS')
        self.assertEqual(len(report['results']),22)
        for relative,expected in report['source_sha256'].items():self.assertEqual(digest(ROOT/relative),expected)
        for r in report['results']:
            self.assertEqual(r['unmapped_cells'],[]);self.assertGreater(r['area_um2'],0)
            net=OUT/'mapping'/r['name']/r['pdk']/'mapped.v'
            self.assertEqual(digest(net),r['netlist_sha256'])

if __name__=='__main__':unittest.main()
