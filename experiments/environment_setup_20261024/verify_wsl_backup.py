"""Check exported tar structure and critical installed payload hashes, without restoring."""
import hashlib,json,tarfile
from pathlib import Path
BASE=Path(__file__).resolve().parent
backup=json.loads((BASE/'wsl_backup_manifest.json').read_text(encoding='utf-8-sig'))
manifest=json.loads((BASE/'linux_toolchain_manifest.json').read_text())
expected={x['path'].lstrip('/'):x['sha256'] for x in manifest['binaries']}
required={'etc/passwd','etc/os-release','home/gs3d/.bashrc','home/gs3d/eda/venvs/gsverify/pyvenv.cfg'}
found=set();checked=[];count=0
with tarfile.open(backup['path'],'r:') as archive:
    for member in archive:
        count+=1
        name=member.name.removeprefix('./').lstrip('/')
        if name in required:found.add(name)
        if name in expected:
            stream=archive.extractfile(member);assert stream is not None,name
            h=hashlib.sha256()
            for chunk in iter(lambda:stream.read(1024*1024),b''):h.update(chunk)
            assert h.hexdigest()==expected[name],name
            checked.append(name)
assert required<=found,required-found
assert set(expected)==set(checked),set(expected)-set(checked)
report=dict(status='PASS_TAR_STRUCTURE_AND_CRITICAL_PAYLOAD_HASHES',archive=backup['path'],members=count,verified_payloads=checked,required_files_found=sorted(found),boot_restore_test_executed=False)
(BASE/'wsl_backup_verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
