import hashlib,json,os,re,subprocess
from pathlib import Path
ROOT=Path('/mnt/d/3DGS');BASE=ROOT/'experiments/environment_setup_20261024';home=Path.home();eda=home/'eda';src=eda/'src-20261024'
(eda/'bin').mkdir(exist_ok=True)
env='''# 3DGS tool environment, configured 2026-10-24.
export GS_EDA_HOME="$HOME/eda"
export CACTI_HOME="$HOME/eda/src-20261024/cacti"
export RAMULATOR_HOME="$HOME/eda/src-20261024/ramulator"
case ":$PATH:" in
  *":$HOME/eda/opt/opensta/bin:"*) ;;
  *) export PATH="$HOME/eda/opt/opensta/bin:$HOME/eda/bin:$PATH" ;;
esac
'''
(eda/'env.sh').write_text(env)
wrappers={
'gs-python':f'#!/usr/bin/env bash\nexec "{eda}/venvs/gsverify/bin/python" "$@"\n',
'ramulator':f'#!/usr/bin/env bash\nexec "{src}/ramulator/ramulator" "$@"\n',
'cacti':f'''#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 2 || "$1" != -infile ]]; then
  echo 'Usage: cacti -infile CONFIG (3DGS wrapper; other interfaces use $CACTI_HOME/cacti directly)' >&2
  exit 2
fi
cfg=$(realpath "$2")
cd "{src}/cacti"
exec ./cacti -infile "$cfg"
'''}
for name,text in wrappers.items():
    p=eda/'bin'/name;p.write_text(text);p.chmod(0o755)
rc=home/'.bashrc';old=rc.read_text();line='[ -f "$HOME/eda/env.sh" ] && source "$HOME/eda/env.sh"'
if line not in old:
    (BASE/'bashrc.before').write_text(old)
    rc.write_text(old+'\n# 3DGS EDA toolchain (2026-10-24)\n'+line+'\n')
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
paths=[eda/'opt/opensta/bin/sta',eda/'opt/cudd-3.0.0/lib/libcudd.a',src/'cacti/cacti',src/'cacti/cacti.upstream',src/'ramulator/ramulator',src/'cacti/io.cc',src/'ramulator/configs/LPDDR4-config.cfg',src/'ramulator/dram.trace',eda/'env.sh',*[(eda/'bin'/n) for n in wrappers]]
binaries=[dict(path=str(p),sha256=sha(p),bytes=p.stat().st_size) for p in paths]
versions={}
for name,cmd in [('os',['cat','/etc/os-release']),('kernel',['uname','-r']),('gcc',['g++','--version']),('cmake',['cmake','--version']),('iverilog',['iverilog','-V']),('verilator',['verilator','--version']),('opensta',[str(eda/'opt/opensta/bin/sta'),'-version']),('python',[str(eda/'venvs/gsverify/bin/python'),'--version'])]:
    p=subprocess.run(cmd,capture_output=True,text=True);versions[name]=dict(command=cmd,exit_code=p.returncode,stdout=p.stdout,stderr=p.stderr)
(BASE/'linux_toolchain_manifest.json').write_text(json.dumps(dict(date='2026-10-24',user=os.getlogin() if False else 'gs3d',source_archives=json.loads((BASE/'source_archives.json').read_text()),binaries=binaries,versions=versions,cacti_patch=json.loads((BASE/'cacti_patch_manifest.json').read_text()),ramulator_compile_flags='CXX=g++ CXXFLAGS="-O3 -std=c++11 -g -Wall -include cstdint"',production_rtl_changed=False,project_signed_off=False),indent=2)+'\n')
for name in ['cacti','ramulator']:
    target=BASE/'tool-inputs'/name;target.mkdir(parents=True,exist_ok=True)
    for rel in (['cache.cfg','io.cc','README'] if name=='cacti' else ['configs/LPDDR4-config.cfg','dram.trace','Makefile','README.md']):
        p=src/name/rel;(target/p.name).write_bytes(p.read_bytes())
# Verify the installed commands from a clean Bash process, explicitly sourcing env.
result=subprocess.run(['bash','-c','source "$HOME/eda/env.sh"; command -v sta cacti ramulator gs-python; sta -version; gs-python -m pip check'],capture_output=True,text=True)
(BASE/'logs/installed-command-check.log').write_text(result.stdout+result.stderr)
assert result.returncode==0
print(result.stdout)
print('LINUX_TOOLCHAIN_MANIFEST_WRITTEN')
