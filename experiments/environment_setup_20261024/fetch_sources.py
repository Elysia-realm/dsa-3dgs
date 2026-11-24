"""HTTPS archive fallback when WSL direct GitHub git transport fails."""
import hashlib,json,tarfile,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
dest=ROOT/'tmp/toolchains/linux_sources_20261024';dest.mkdir(parents=True,exist_ok=True)
repos=[('cudd','cuddorg/cudd','refs/tags/3.0.0'),('OpenSTA','parallaxsw/OpenSTA','refs/heads/master'),('cacti','HewlettPackard/cacti','1ffd8dfb10303d306ecd8d215320aea07651e878'),('ramulator','CMU-SAFARI/ramulator','refs/heads/master')]
rows=[]
for name,repo,ref in repos:
    url=f'https://codeload.github.com/{repo}/tar.gz/{ref}'
    path=dest/f'{name}.tar.gz'
    if not path.exists():
        print('FETCH',url,flush=True)
        with urllib.request.urlopen(url,timeout=90) as response:
            data=response.read()
        path.write_bytes(data)
    with tarfile.open(path) as tar:
        head=tar.next();pax=dict(tar.pax_headers)
        if head:pax.update(head.pax_headers)
    row=dict(name=name,repo=repo,requested_ref=ref,url=url,path=str(path.relative_to(ROOT)),bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),pax=pax)
    rows.append(row)
    (ROOT/'experiments/environment_setup_20261024/source_archives.json').write_text(json.dumps(rows,indent=2)+'\n')
    print(json.dumps(row),flush=True)
