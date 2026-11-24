param([switch]$EvidenceOnly,
  [string]$Python='C:\Users\12104\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
  if (-not $EvidenceOnly) {
    & $Python scripts/run_t06_qsu_units.py
    if ($LASTEXITCODE -ne 0) { throw 'T06 unit tests failed' }
    & $Python scripts/run_t06_protocol_tests.py
    if ($LASTEXITCODE -ne 0) { throw 'T06 protocol tests failed' }
    & $Python scripts/check_t06_synthesis.py
    if ($LASTEXITCODE -ne 0) { throw 'T06 synthesis checks failed' }
    cmd /c verification\rtl\run_iverilog.cmd
    if ($LASTEXITCODE -ne 0) { throw 'RTL regression failed' }
    cmd /c verification\rtl\run_verilator_lint.cmd
    if ($LASTEXITCODE -ne 0) { throw 'RTL lint failed' }
  }
  # Large real runs have separate resumable commands. Missing evidence fails
  # below; this entry never silently substitutes a smaller synthetic workload.
  & $Python -m unittest verification.test_t06_evidence verification.test_t05_parallel_evidence verification.test_implementation_status -v
  if ($LASTEXITCODE -ne 0) { throw 'T06 evidence gate incomplete or failed' }
} finally { Pop-Location }
