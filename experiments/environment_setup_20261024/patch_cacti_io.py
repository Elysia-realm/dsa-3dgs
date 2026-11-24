"""Small local config-parser repair; SRAM modeling algorithms are unchanged."""
import difflib,hashlib,json,shutil
from pathlib import Path
BASE=Path('/mnt/d/3DGS/experiments/environment_setup_20261024')
SRC=Path.home()/'eda/src-20261024/cacti'
path=SRC/'io.cc';old=path.read_text()
assert 'GS_CONFIG_IO_FIELDS' not in old
shutil.copy2(SRC/'cacti',SRC/'cacti.upstream')
(BASE/'cacti-io.cc.before').write_text(old)
new=old.replace('#include <sstream>','#include <sstream>\n#include <cmath>',1)
anchor=' cl_vertical (true)\n{\n\n}'
assert anchor in new
new=new.replace(anchor,' cl_vertical (true)\n{\n  // GS_CONFIG_IO_FIELDS: reject missing IO parameters instead of using indeterminate values.\n  ron_value = rtt_value = tflight_value = -1.0;\n}',1)
anchor='  while(fscanf(fp, "%[^\\n]\\n", line) != EOF) {\n'
assert anchor in new
extra='\n'
for name,comparison in [('ron_value','<= 0'),('rtt_value','<= 0'),('tflight_value','< 0')]:
    extra+=f'''    if (!strncmp("-{name}", line, strlen("-{name}"))) {{
      if (sscanf(line, "-{name} %lf", &{name}) != 1 ||
          !std::isfinite({name}) || {name} {comparison}) {{
        cerr << "Invalid -{name} in CACTI configuration" << endl;
        exit(1);
      }}
      continue;
    }}
'''
new=new.replace(anchor,anchor+extra,1)
anchor='  fclose(fp);'
assert anchor in new
new=new.replace(anchor,anchor+'''
  if ((io_type == DDR3 || io_type == DDR4) &&
      (!(ron_value > 0) || !(rtt_value > 0) || !(tflight_value >= 0))) {
    cerr << "DDR3/DDR4 IO requires explicit ron_value, rtt_value and tflight_value" << endl;
    exit(1);
  }
''',1)
path.write_text(new)
(BASE/'cacti_config_parser.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/io.cc',tofile='b/io.cc')))
(BASE/'cacti_patch_manifest.json').write_text(json.dumps(dict(upstream_commit='1ffd8dfb10303d306ecd8d215320aea07651e878',file='io.cc',before_sha256=hashlib.sha256(old.encode()).hexdigest(),after_sha256=hashlib.sha256(new.encode()).hexdigest(),scope='Parse/validate three missing external IO configuration fields; no SRAM algorithm changes'),indent=2)+'\n')
print('CACTI_CONFIG_PARSER_PATCH_APPLIED')
