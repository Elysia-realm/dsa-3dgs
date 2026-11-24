"""Structural library compatibility check; not a timing or PPA signoff."""
import hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'experiments/environment_setup_20261024'
LIBDIR=ROOT/'tmp/toolchains/freepdk45_google_954b16e2/Front_End/Liberty/NLDM'

def groups(text,kind):
    out={}
    for m in re.finditer(r'\b'+kind+r'\s*\(\s*([^)]*?)\s*\)\s*\{',text):
        i=m.end();start=i;depth=1;quoted=False;escape=False
        while depth:
            c=text[i];i+=1
            if quoted:
                if escape:escape=False
                elif c=='\\':escape=True
                elif c=='"':quoted=False
            elif c=='"':quoted=True
            elif c=='{':depth+=1
            elif c=='}':depth-=1
        key=m.group(1).strip('" ')
        if key in out:raise ValueError(f'duplicate {kind}: {key}')
        out[key]=text[start:i-1]
    return out

def parse(path):
    text=re.sub(r'/\*.*?\*/','',path.read_text(),flags=re.S)
    cells=groups(text,'cell');signature={}
    for name,body in cells.items():
        pins={}
        for pin,pbody in groups(body,'pin').items():
            attrs={}
            for field in ['direction','function','three_state','clock']:
                match=re.search(r'\b'+field+r'\s*:\s*([^;]+);',pbody)
                attrs[field]=match.group(1).strip() if match else None
            pins[pin]=attrs
        signature[name]={'pins':pins,'ff':groups(body,'ff'),'latch':groups(body,'latch')}
    metadata={}
    for field in ['nom_voltage','nom_temperature','time_unit','leakage_power_unit']:
        match=re.search(r'\b'+field+r'\s*:\s*([^;]+);',text)
        metadata[field]=match.group(1).strip() if match else None
    return cells,signature,metadata

old=ROOT/'tmp/toolchains/freepdk45/NangateOpenCellLibrary_typical.lib'
oc,os,om=parse(old)
rows=[];signatures={};bodies={}
for corner in ['typical','slow','fast']:
    p=LIBDIR/f'NangateOpenCellLibrary_{corner}.lib'
    cells,sig,metadata=parse(p);signatures[corner]=sig;bodies[corner]=cells
    rows.append(dict(corner=corner,path=p.relative_to(ROOT).as_posix(),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),cells=len(cells),metadata=metadata))
tt=signatures['typical']
all_same=all(signatures[c]==tt for c in ['slow','fast'])
common=set(oc)&set(bodies['typical'])
old_same=all(oc[c]==bodies['typical'][c] for c in common)
extra=sorted(set(oc)-set(tt))
used_tap=[]
for p in (ROOT/'asic/reports/t01/runs/freepdk45_nangate45').rglob('gs_accel_system_top_mapped.v'):
    if re.search(r'\bTAPCELL_X1\b',p.read_text()):used_tap.append(p.relative_to(ROOT).as_posix())
report=dict(status='PASS' if all_same and old_same and extra==['TAPCELL_X1'] and not used_tap else 'REVIEW_REQUIRED',
 scope='Nangate45 cross-corner cell/pin/function/ff/latch compatibility and old TT common-cell text identity; no full-top STA',
 libraries=rows,cross_corner_signatures_identical=all_same,old_tt_common_cell_bodies_identical=old_same,
 old_tt_extra_cells=extra,tap_cell_used_in_old_mapped_netlists=used_tap,
 source_commit='954b16e2fcd52994e9d3c8b5af35b5f91d261889')
(BASE/'nangate_compatibility_audit.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
assert report['status']=='PASS'
