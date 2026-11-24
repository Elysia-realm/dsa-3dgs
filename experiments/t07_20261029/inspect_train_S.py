import sys
from pathlib import Path
root=Path('/mnt/d/3DGS');sys.path.insert(0,str(root))
from scripts.run_t07_real import state_values
from scripts.t07_common import BASE,T01,save
d=BASE/'real/full/S/train';old=T01/'real/full/train'
a=state_values(d/'state.memh',1);b=state_values(old/'state.memh',1)
dif=[dict(pixel=i,current=list(x),baseline=list(y)) for i,(x,y) in enumerate(zip(a,b)) if x!=y]
raw=bytes(int(s,16) for s in (d/'rgb.memh').read_text().split())
r=dict(rgb_equal=raw==(old/'frame.rgb').read_bytes(),state_differences=dif,
       only_terminal_T=all(x['current'][0]==x['baseline'][0] and max(x['current'][1],x['baseline'][1])<=7 for x in dif))
save(BASE/'train_S_state_inspection.json',r);print('RGB',r['rgb_equal'],'differences',len(dif),'terminal_only',r['only_terminal_T'],dif[:8])
