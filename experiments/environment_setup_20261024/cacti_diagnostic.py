import difflib,json,math,re,subprocess
from pathlib import Path
BASE=Path('/mnt/d/3DGS/experiments/environment_setup_20261024')
source=Path.home()/'eda/src-20261024/cacti'
original=(source/'cache.cfg').read_text()
# Use the local parser repair, explicit DDR3 diagnostic IO values and valid keys.
# Ancillary DDR3 IO is NOT this project's LPDDR4 model.
changes={
 '-size (bytes) 131072':'-size (bytes) 65536',
 '-associativity 2':'-associativity 1',
 '-technology (u) 0.090':'-technology (u) 0.045',
 '-output/input bus width 512':'-output/input bus width 128',
 '-operating temperature (K) 360':'-operating temperature (K) 300',
 '-cache type "cache"':'-cache type "ram"',
 '-Add ECC - "true"':'-Add ECC - "false"',
 '-dram_type "DDR3"':'-dram type "DDR3"',
 '-bus_freq 800 MHz':'-bus_freq 400 MHz',
 '-tflight_value':'-tflight_value 1.0',
}
text=original
for old,new in changes.items():
    text,n=re.subn(r'^'+re.escape(old),lambda m:new,text,flags=re.M)
    assert n==1,(old,n)
cfg=BASE/'cacti_sram_diagnostic.cfg';cfg.write_text(text)
(BASE/'cacti_config_diff.txt').write_text(''.join(difflib.unified_diff(original.splitlines(True),text.splitlines(True),fromfile='upstream/cache.cfg',tofile='cacti_sram_diagnostic.cfg')))
result=subprocess.run([str(source/'cacti'),'-infile',str(cfg)],cwd=source,capture_output=True,text=True)
log=result.stdout+result.stderr
(BASE/'logs/cacti-sram-diagnostic-patched.log').write_text(log)
fields={}
for name,pattern in {
 'access_ns':r'Access time \(ns\):\s*([\d.eE+-]+)',
 'cycle_ns':r'Cycle time \(ns\):\s*([\d.eE+-]+)',
 'read_nJ':r'Total dynamic read energy per access \(nJ\):\s*([\d.eE+-]+)',
 'write_nJ':r'Total dynamic write energy per access \(nJ\):\s*([\d.eE+-]+)',
 'leakage_mW':r'Total leakage power of a bank \(mW\):\s*([\d.eE+-]+)',
}.items():
    match=re.search(pattern,log);assert match,name
    fields[name]=float(match[1]);assert math.isfinite(fields[name]) and fields[name]>0
assert result.returncode==0
assert not re.search(r'\b(?:nan|inf)\b',log,re.I)
assert re.search(r'io_type\s*:\s*DDR3',log)
report=dict(status='PASS_SRAM_TOOL_DIAGNOSTIC_ONLY',configuration='64KiB, 128-bit bus, one RW port, 45nm generic model, 300K, no ECC',metrics=fields,upstream_default_example_limitation='DDR3 IO area inf: fields ron_value/rtt_value/tflight_value are used but not parsed upstream. Local parser patch and explicit config close this diagnostic failure. Original LPDDR2 attempt also exposed MemCAD DDR3/DDR4-only assertion and is preserved as failed.',ancillary_io='DDR3 diagnostic at 400MHz with ron=34 ohm, rtt=10000 ohm, tflight=1ns; not project LPDDR4 validation',project_macro_model=False)
(BASE/'cacti_diagnostic_report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
