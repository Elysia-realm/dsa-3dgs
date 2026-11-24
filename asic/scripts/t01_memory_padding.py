"""Define only proven-unconsumed non-power-of-two QSU read-mux padding.

No global setundef and no waiver of check -assert. The exact 38 padding rows are
identified structurally after memory_map. Original RTL and valid rows are unchanged.
"""
import re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.t01_resume_common import BASE,read,save,sha
def define_padding(src,dst,report):
    proof=read(BASE/'hist_padding_proof/proof.json');assert proof['status']=='PASS_POINTER_BOUNDS_INDUCTION'
    assert proof['original_rtl_sha256']==sha(ROOT/'rtl/sort/autonomous_qsu.sv')
    pattern=re.compile(r'^(\$memory\\saved_hist\$rdmux\[0\]\[7\]\[(\d+)\]\$(a|b)\$\d+)$')
    module=None;selected={};changes=[];declared={}
    # Stream module bodies; only one original memory's out-of-range mux inputs change.
    with Path(src).open() as inp,Path(dst).open('w') as out:
        for line in inp:
            if line.startswith('module '):module=line.split(None,1)[1].strip()
            if module and module.endswith('\\autonomous_qsu'):
                s=line.strip().split()
                if s and s[0]=='wire':
                    name=s[-1];m=pattern.match(name)
                    if m:
                        row=2*int(m[2])+(m[3]=='b')
                        if row>=218:
                            assert row<256 and s[1:3]==['width','1712'],s
                            selected[name]=(module,row);declared[name]=False
                if s and s[0]=='connect' and len(s)>=3 and s[1] in selected:
                    assert len(s)==3 and s[2]=="1712'x",('padding input unexpectedly driven',line)
                    changes.append(dict(module=module,net=s[1],row=selected[s[1]][1],before=s[2],after="1712'0"))
                    line=f"  connect {s[1]} 1712'0\n";declared[s[1]]=True
                if line=='end\n':
                    for name,(owner,row) in selected.items():
                        if owner==module and not declared[name]:
                            out.write(f"  connect {name} 1712'0\n");declared[name]=True
                            changes.append(dict(module=module,net=name,row=row,before='undriven',after="1712'0"))
            out.write(line)
            if line=='end\n':module=None
    assert len(changes)==38 and sorted(c['row'] for c in changes)==list(range(218,256)),changes
    save(report,dict(status='DEFINED_PROVEN_UNUSED_PADDING',input_sha256=sha(src),output_sha256=sha(dst),proof_log_sha256=proof['log_sha256'],changes=changes,original_rtl_changed=False))
