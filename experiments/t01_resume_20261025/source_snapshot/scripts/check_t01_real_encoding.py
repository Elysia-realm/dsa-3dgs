"""Native-host raw PLY field audit of the exact reused full/subset DMA inputs."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,FULL,OLD,read,save,sha,frozen
from scripts import run_t06_image_release as encoding
def main():
    encoding.BASE=BASE/'encoding';encoding.FULL=FULL;encoding.SUB=OLD/'subset'
    encoding.NAMES=['bonsai','counter','room','train','truck'];encoding.verify_encoding()
    r=read(encoding.BASE/'input_encoding_report.json');assert len(r['results'])==10
    originals={}
    for name in encoding.NAMES:
        p=ROOT/'data'/name/'point_cloud/iteration_30000/point_cloud.ply'
        h=sha(p);m=read(FULL/name/'manifest.json')
        if 'source_ply_sha256' in m:assert h==m['source_ply_sha256'].upper()
        originals[name]={'path':p.relative_to(ROOT).as_posix(),'sha256':h}
    r.update(raw_ply=originals,source_sha256={f:sha(ROOT/f) for f in ['scripts/run_t06_image_release.py','model/io/scene.py','scripts/check_t01_real_encoding.py']},production_source_sha256=frozen(),scope='10 datasets: 5 full + 5 subset; literal channel-major SH fields sampled, encoded inputs and raw PLY hashes verified. Not a full-field exhaustive proof.')
    save(encoding.BASE/'input_encoding_report.json',r)
if __name__=='__main__':main()
