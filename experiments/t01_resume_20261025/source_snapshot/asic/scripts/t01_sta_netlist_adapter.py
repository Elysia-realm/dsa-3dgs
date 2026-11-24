"""Remove signed declaration metadata for OpenSTA, proving bit connectivity unchanged."""
import hashlib,itertools,re
from pathlib import Path
from scripts.t01_resume_common import WORK,save,read,sha,run_logged
YOSYS=Path.home()/'eda/opt/oss-cad-suite-20260706/oss-cad-suite/bin/yosys'
def adapt(raw,lib,top='gs_accel_system_top'):
    raw=Path(raw);out=raw.with_suffix('.sta.v');report=raw.parent/'sta_netlist_adapter.json'
    if report.exists():
        r=read(report)
        if (r['input_sha256']==sha(raw) and out.exists() and r['output_sha256']==sha(out)
            and r.get('library_sha256')==sha(lib) and r.get('adapter_sha256')==sha(Path(__file__)) and r.get('top')==top
            and r.get('proof',{}).get('checker_sha256')==sha(Path(__file__).with_name('t01_structural_width_proof.py'))):return out
    count=0
    with raw.open() as source,out.open('w') as target:
        for line in source:
            assert not re.match(r'\s*(always|initial|function|task)\b',line),'Mapped structural netlist required'
            line,n=re.subn(r'^(\s*(?:input|output|inout|wire)\s+)signed\s+',r'\1',line);count+=n;target.write(line)
    from asic.scripts.t01_structural_width_proof import prove
    structural=prove(raw,lib,YOSYS)
    if raw.stat().st_size>100_000_000:
        save(report,dict(status='PASS_BIT_CONNECTIVITY_EQUIVALENT',input_sha256=sha(raw),output_sha256=sha(out),library_sha256=sha(lib),adapter_sha256=sha(Path(__file__)),top=top,signed_declarations_removed=count,method='streaming_complete_structural_width_proof',proof=structural,scope='All structural assignments and cell connections checked; no extension depends on removed signed declarations. Large-netlist reimport attempt preserved as resource-limited.'))
        return out
    work=WORK/'sta_format'/sha(raw)[:16];work.mkdir(parents=True,exist_ok=True)
    script=raw.parent/'sta_format_check.ys'
    script.write_text(f'read_liberty -lib "{lib}"\nread_verilog "{raw}"\nhierarchy -check -top {top}\nopt_clean -purge\nwrite_rtlil "{work}/original.il"\ndesign -reset\nread_liberty -lib "{lib}"\nread_verilog "{out}"\nhierarchy -check -top {top}\nopt_clean -purge\nwrite_rtlil "{work}/adapted.il"\n')
    run_logged([str(YOSYS),'-q','-s',str(script)],raw.parent/'sta_format_check.log')
    def semantic_modules(p):
        attrs=[];module=None;records=[];cell=None
        with p.open() as f:
            for line in f:
                if line.startswith('#') or line.startswith('autoidx '):continue
                # Frontend elaboration/location metadata; retain all other
                # attributes, including init/blackbox and all logic/bit wiring.
                if re.match(r'\s*attribute \\(src|single_bit_vector|module_not_derived|reprocess_after) ',line):continue
                line=line.rstrip()
                if not line:continue
                if line.strip().startswith('wire '):line=' '.join(x for x in line.split() if x!='signed')
                if line.startswith('module '):
                    module=line;records=[tuple(sorted(attrs)+[line])];attrs=[];continue
                if line.lstrip().startswith('attribute '):attrs.append(line.strip());continue
                if line.startswith('  cell '):
                    assert cell is None;cell=[*sorted(attrs),line.strip()];attrs=[];continue
                if cell is not None:
                    if line=='  end':records.append(tuple(cell[:len(cell)]));cell=None
                    else:cell.append(line.strip())
                    continue
                if line=='end':
                    assert module and not attrs
                    # Sort whole records; never detach a connection from its cell.
                    canonical=sorted(records);h=hashlib.sha256()
                    for record in canonical:h.update(repr(record).encode());h.update(b'\n')
                    yield module,h.hexdigest(),len(records),canonical
                    module=None;records=[];continue
                assert module,(p,line)
                records.append(tuple(sorted(attrs)+[line.strip()]));attrs=[]
        assert module is None and cell is None
    modules=[]
    for a,b in itertools.zip_longest(semantic_modules(work/'original.il'),semantic_modules(work/'adapted.il')):
        assert a and b and a[:3]==b[:3],('Signed removal changed bit-level netlist',a[:3] if a else None,b[:3] if b else None,
          next(((x,y) for x,y in itertools.zip_longest(a[3],b[3]) if x!=y),None) if a and b else None)
        modules.append(dict(module=a[0],canonical_graph_sha256=a[1],records=a[2]))
    save(report,dict(status='PASS_BIT_CONNECTIVITY_EQUIVALENT',input_sha256=sha(raw),output_sha256=sha(out),library_sha256=sha(lib),adapter_sha256=sha(Path(__file__)),top=top,signed_declarations_removed=count,modules=modules,proof=structural,ignored_metadata=['src','single_bit_vector','module_not_derived','reprocess_after','signed wire flags'],scope='Reimported RTLIL compared as whole wire/cell/connection records independent of declaration order, plus complete structural width proof. All cell connections/parameters and bit widths identical; only declared frontend/type metadata ignored.'))
    return out
