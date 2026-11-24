import hashlib,json,re,unittest
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'experiments/t05_parallel_20261011'
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

class T05ParallelEvidenceTests(unittest.TestCase):
    def test_complete_selection_and_natural_capacity_coverage(self):
        r=read(BASE/'real/report.json');self.assertEqual(r['status'],'PASS');self.assertEqual(len(r['results']),240)
        expected={(s,n,v,m,p) for s in ['bonsai','counter','room','kitchen','garden'] for n in (8,16)
            for v in ['fold8','pipe8','fold16','pipe16'] if int(v[-2:] if v.endswith('16') else v[-1])>=n for m in range(4) for p in ['ideal','limited']}
        self.assertEqual({(x['scene'],x['subset_capacity'],x['variant'],x['mode'],x['profile']) for x in r['results']},expected)
        for path,value in r['source_sha256'].items():self.assertEqual(sha(BASE/'selection_snapshot'/path),value)
        for scene in ['bonsai','counter','room','kitchen','garden']:
            for n in (8,16):
                folder=BASE/'real'/scene/f'g{n}';manifest=read(folder/'manifest.json')
                self.assertTrue(all(b['group_counts']==[n]*4 for b in manifest['batches']))
                self.assertEqual(sum(b['count'] for b in manifest['batches']),512)
                for p,h in manifest['input_sha256'].items():self.assertEqual(sha(folder/p),h)

    def test_every_selection_rgb_and_sorted_stream(self):
        r=read(BASE/'real/report.json');scene_hashes={}
        for x in r['results']:
            folder=BASE/'real'/x['scene']/f'g{x["subset_capacity"]}'/f'{x["variant"]}_m{x["mode"]}_{x["profile"]}'
            manifest=read(folder.parent/'manifest.json');raw=(folder/'frame.rgb').read_bytes()
            self.assertEqual(sha(folder/'frame.rgb'),x['rgb_sha256'])
            self.assertEqual(raw,bytes(int(v,16) for v in (folder/'rgb.memh').read_text().split()))
            self.assertEqual(Image.open(folder/'frame.png').tobytes(),raw) # width64 -> no row padding
            self.assertEqual([[int(v) for v in line.split()] for line in (folder/'sorted.txt').read_text().splitlines()],manifest['expected_sorted_stream'])
            self.assertIn('error=00000000',(folder/'run.log').read_text())
            scene_hashes.setdefault(x['scene'],set()).add(x['rgb_sha256'])
            if x['pipeline']:
                self.assertEqual(int(x['shared']['G']),512//x['subset_capacity'])
                self.assertGreater(int(x['sort']['fallback']),0) # physical simultaneous stage transfers
                self.assertGreater(int(x['sort']['phase_grants']),0) # input/output overlap
            self.assertGreater(int(x['shared']['P']),0);self.assertGreater(int(x['shared']['R']),0)
        self.assertTrue(all(len(h)==1 for h in scene_hashes.values()))

    def test_current_production_defaults_release(self):
        r=read(BASE/'release/report.json');self.assertEqual(r['status'],'PASS');self.assertEqual(len(r['results']),40)
        for path,h in r['source_sha256'].items():self.assertEqual(sha(ROOT/path),h)
        old=read(BASE/'real/report.json')['results']
        for x in r['results']:
            ref=next(a for a in old if a['scene']==x['scene'] and a['subset_capacity']==16 and a['variant']=='pipe16' and a['mode']==x['mode'] and a['profile']==x['profile'])
            self.assertEqual((x['cycles'],x['rgb_sha256']),(ref['cycles'],ref['rgb_sha256']))
            folder=BASE/'release'/x['scene']/'g16'/f'production16_m{x["mode"]}_{x["profile"]}'
            self.assertIn('T05_RELEASE_DEFAULTS K=16 pipeline=1 shared_R=1 RGB=1',(folder/'run.log').read_text())
            self.assertEqual(sha(folder/'frame.rgb'),x['rgb_sha256'])

    def test_saturated_throughput_and_unit_stability(self):
        units=read(BASE/'units/report.json');self.assertEqual(units['status'],'PASS');self.assertEqual(len(units['results']),4)
        throughput=read(BASE/'throughput/report.json');self.assertEqual(throughput['status'],'PASS')
        self.assertEqual(len(throughput['results']),12)
        for r in throughput['results']:
            if r['pipeline']:
                self.assertEqual(r['steady_max_interval'],r['k'])
                self.assertGreater(r['collect_emit'],0);self.assertGreater(r['multi_stage'],0)
                log=(BASE/'throughput'/f'k{r["k"]}l{r["lanes"]}p1_run.log').read_text()
                self.assertIn('PASS: tb_t05_sorters',log)

    def test_mapping_and_current_default_epoch_switch(self):
        mapping=read(BASE/'mapping/report.json');self.assertEqual(mapping['status'],'PASS');self.assertEqual(len(mapping['results']),8)
        for path,h in mapping['source_sha256'].items():self.assertEqual(sha(ROOT/path),h)
        for r in mapping['results']:
            self.assertEqual(r['unmapped_cells'],[])
            self.assertEqual(sha(BASE/'mapping'/r['name']/r['pdk']/'mapped.v'),r['netlist_sha256'])
        cfg=read(BASE/'release/reconfiguration/report.json');self.assertEqual(cfg['status'],'PASS');self.assertEqual(len(cfg['results']),5)
        for path,h in cfg['source_sha256'].items():self.assertEqual(sha(ROOT/path),h)
        for r in cfg['results']:self.assertGreaterEqual(r['changes'],2)
        self.assertGreater(sum(r['GP']+r['PR']+r['GR'] for r in cfg['results']),0)

if __name__=='__main__':unittest.main()
