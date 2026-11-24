from pathlib import Path
import hashlib,json,numpy as np
from PIL import Image
root=Path('/mnt/d/3DGS')
old=root/'experiments/t06_20261018/float_full/bonsai/float_floor_0.30078125_jac_clamp.png'
new=root/'experiments/t01_resume_20261025/fresh_float/bonsai/float_floor_0.30078125_jac_clamp.png'
rows=[]
for p in [old,new]:
    im=Image.open(p);a=np.array(im)
    rows.append(dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),bytes=p.stat().st_size,mode=im.mode,shape=a.shape,pixels_sha256=hashlib.sha256(a.tobytes()).hexdigest(),info=im.info))
a=np.array(Image.open(old));b=np.array(Image.open(new));d=abs(a.astype(float)-b)
r=dict(files=rows,changed_channels=int((d!=0).sum()),max_abs=float(d.max()),mae=float(d.mean()))
print(json.dumps(r,indent=2));new.parent.parent.joinpath('initial_difference.json').write_text(json.dumps(r,indent=2))
