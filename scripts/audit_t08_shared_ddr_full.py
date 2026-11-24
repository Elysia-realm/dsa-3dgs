"""Reconstruct attribute line traffic for completed full-model shared-memory pairs."""
from pathlib import Path
import sys
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.run_t08_shared_ddr import OUT
from scripts.t08_common import BASE,SCENES,read,save,sha


def audit(scene):
    d=OUT/'full128'/scene
    comp=read(d/'comparison.json')
    rows={r['format']:r for r in comp['rows']}
    assert len(comp['rows'])==2 and set(rows)=={2,3}
    meta=read(BASE/'inputs/native'/scene/'manifest.json')
    raw,compact=rows[3],rows[2]
    assert raw['hashes']['rgb.memh']==compact['hashes']['rgb.memh']
    records=read(BASE/'dual_precision_full128_20261122/inputs'/scene/'manifest.json')
    folder=d/'f2_t1'
    launch=read(folder/'launch.json')
    attr=Path(next(a[6:] for a in launch['command'] if a.startswith('+ATTR=')))
    assert sha(attr)==records['encoded_sha256']==launch['input_sha256']['ATTR']
    assert records['records']==meta['gaussians']
    # The archived encoder emits nine LF-terminated 32-digit hex words per slot.
    data=np.memmap(attr, mode='r',dtype=np.uint8,shape=(records['records'],9,33))
    assert attr.stat().st_size==data.size and np.all(data[:,0,32]==10)
    ordered=folder/'sorted.txt'
    gids=np.loadtxt(ordered,usecols=1,dtype=np.int64,ndmin=1)
    assert np.all((gids>=0)&(gids<records['records']))
    header=np.zeros(len(gids),dtype=np.int64)
    for pos in range(28,32):
        digit=data[gids,0,pos].astype(np.int64)
        assert np.all(((digit>=48)&(digit<=57))|((digit>=97)&(digit<=102)))
        header=header*16+np.where(digit<=57,digit-48,digit-87)
    assert np.all((header&0x3ff)==0x2c8)
    degree=(header>>11)&3
    beats=np.where((header&0x400)!=0,9,(254+3*(degree+1)**2*np.where(header&0x2000,18,16)+127)//128)
    addr=0x10000000+144*gids

    def touched(start,n,stride):
        return (start+16*n-1)//stride-start//stride+1
    audit_rows=[]
    for fmt in (3,2):
        row=rows[fmt]
        rdir=d/f'f{fmt}_t1'
        assert row['execution']['exit_code']==0 and sha(rdir/'run.log')==row['execution']['log_sha256']
        assert sha(rdir/'model.stats')==row['stats_sha256']
        assert all(sha(rdir/f)==h for f,h in row['hashes'].items())
        assert row['hashes']['sorted.txt']==compact['hashes']['sorted.txt']
        c=row['counters']
        n=9 if fmt==3 else beats
        nb=int(9*len(gids) if fmt==3 else beats.sum())
        ar=int(touched(addr,n,4096).sum() if fmt==3 else (1+touched(addr+16,n-1,4096)).sum())
        lines=int(touched(addr,n,64).sum() if fmt==3 else (1+touched(addr+16,n-1,64)).sum())
        assert (len(gids),nb,ar)==(c['REAL_T08']['requests'],c['REAL_DMA_COUNTS']['attribute_beats'],c['REAL_DMA_COUNTS']['attribute_bursts'])
        audit_rows.append(dict(format=fmt,bytes=16*nb,bursts=ar,lines=lines,all_port_lines=c['REAL_LPDDR']['lines'],cycles=row['cycles']))
    a,b=audit_rows
    shared=int(np.count_nonzero((addr//64)==((addr+16)//64)))
    assert b['lines']-shared==int(touched(addr,beats,64).sum())
    return dict(scene=scene,records=records['records'],issued=len(gids),raw=a,compact=b,
                extra_attr_lines=b['lines']-a['lines'],extra_other_lines=b['all_port_lines']-a['all_port_lines']-(b['lines']-a['lines']),
                duplicate_header_payload_lines=shared,cycle_increase_percent=100*(b['cycles']/a['cycles']-1),
                comparison_sha256=sha(d/'comparison.json'),signed_off=False)


if __name__=='__main__':
    rows=[audit(scene) for scene in SCENES if (OUT/'full128'/scene/'comparison.json').exists()]
    complete=len(rows)==len(SCENES) and (OUT/'full128_report.json').is_file()
    dest=OUT/('full128_audit.json' if complete else 'full128_partial_audit.json')
    save(dest,dict(results=rows,complete=complete,script_sha256=sha(__file__),signed_off=False))
    for r in rows:
        print(r['scene'],r['extra_attr_lines'],r['extra_other_lines'],r['duplicate_header_payload_lines'])
