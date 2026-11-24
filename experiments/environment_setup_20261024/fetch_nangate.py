"""Fetch public, commit-pinned Nangate views from Google's foss-eda-tools mirror."""
import base64, hashlib, json, time, urllib.request
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
COMMIT='954b16e2fcd52994e9d3c8b5af35b5f91d261889'
BASE=f'https://foss-eda-tools.googlesource.com/third_party/freepdk45/+/{COMMIT}/'
DEST=ROOT/'tmp/toolchains/freepdk45_google_954b16e2'
DEST.mkdir(parents=True,exist_ok=True)
items=['LICENSE', *[f'Front_End/Liberty/NLDM/NangateOpenCellLibrary_{c}.lib' for c in ['typical','slow','fast']], 'Front_End/Verilog/NangateOpenCellLibrary.v']
records=[]
for item in items:
    path=DEST/item
    url=BASE+item+'?format=TEXT'
    if not path.is_file():
        path.parent.mkdir(parents=True,exist_ok=True)
        print('FETCH',item,flush=True)
        with urllib.request.urlopen(url,timeout=60) as response:
            raw=response.read()
        data=base64.b64decode(raw,validate=True)
        path.write_bytes(data)
    data=path.read_bytes()
    records.append(dict(path=str(path.relative_to(ROOT)),url=url,bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
    print('SAVED',item,len(data),flush=True)
    (ROOT/'experiments/environment_setup_20261024/nangate_download_manifest.json').write_text(json.dumps(dict(commit=COMMIT,files=records),indent=2)+'\n')
old=ROOT/'tmp/toolchains/freepdk45/NangateOpenCellLibrary_typical.lib'
new=DEST/items[1]
print('TT_IDENTICAL_TO_EXISTING',old.read_bytes()==new.read_bytes(),flush=True)
