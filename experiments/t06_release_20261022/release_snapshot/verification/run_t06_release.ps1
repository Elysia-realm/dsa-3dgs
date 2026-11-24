param([switch]$EvidenceOnly,
  [string]$Python='C:\Users\12104\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
  if (-not $EvidenceOnly) {
    $activeJobs = Get-CimInstance Win32_Process | Where-Object {
      $_.Name -eq 'python.exe' -and $_.CommandLine -match 'scripts[\\/](run_t06_release\.py|run_t06_release_full_order\.py|check_t06_release_repeat\.py|check_t06_release_aux\.py)'
    }
    if ($activeJobs) { throw 'T06 release jobs are already active. Inspect status/logs; do not duplicate or alter their sources.' }
    & $Python scripts/run_t06_release.py
    if ($LASTEXITCODE -ne 0) { throw 'T06 selected-profile real release failed' }
    & $Python scripts/check_t06_release_repeat.py
    if ($LASTEXITCODE -ne 0) { throw 'T06 nonempty repeated-frame release failed' }
    & $Python scripts/check_t06_release_aux.py
    if ($LASTEXITCODE -ne 0) { throw 'T06 auxiliary/protocol checks failed' }
    & $Python scripts/run_t06_release_full_order.py
    if ($LASTEXITCODE -ne 0) { throw 'T06 all-record module ordering failed' }
  }
  & $Python scripts/audit_t06_release.py
  if ($LASTEXITCODE -ne 0) { throw 'T06 release evidence incomplete or failed; not signed off' }
} finally { Pop-Location }
