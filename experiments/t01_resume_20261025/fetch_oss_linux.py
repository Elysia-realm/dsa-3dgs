import hashlib,json,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
url='https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-07-06/oss-cad-suite-linux-x64-20260706.tgz'
dest=ROOT/'tmp/toolchains/oss-cad-suite-linux-x64-20260706.tgz'
if not dest.exists():
    temp=dest.with_suffix('.download')
    with urllib.request.urlopen(url,timeout=120) as response,temp.open('wb') as f:
        print('HTTP',response.status,'LENGTH',response.headers.get('Content-Length'),flush=True)
        while data:=response.read(1024*1024):f.write(data)
    temp.replace(dest)
h=hashlib.sha256()
with dest.open('rb') as f:
    for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
row=dict(url=url,path=str(dest),bytes=dest.stat().st_size,sha256=h.hexdigest())
(ROOT/'experiments/t01_resume_20261025/oss_linux_archive.json').write_text(json.dumps(row,indent=2))
print(json.dumps(row),flush=True)
