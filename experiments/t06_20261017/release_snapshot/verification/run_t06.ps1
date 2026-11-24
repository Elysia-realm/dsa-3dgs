param([switch]$EvidenceOnly,
  [string]$Python='C:\Users\12104\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
  if (-not $EvidenceOnly) {
    & $Python scripts/check_t06_image_units.py
    if ($LASTEXITCODE -ne 0) { throw 'T06 image semantic unit tests failed' }
    & $Python -c "from pathlib import Path; from scripts import run_t06_protocol_tests as p; p.OUT=Path('experiments/t06_20261017/protocol'); p.main()"
    if ($LASTEXITCODE -ne 0) { throw 'T06 protocol tests failed' }
    cmd /c verification\rtl\run_iverilog.cmd
    if ($LASTEXITCODE -ne 0) { throw 'RTL regression failed' }
    cmd /c verification\rtl\run_verilator_lint.cmd
    if ($LASTEXITCODE -ne 0) { throw 'RTL lint failed' }
  }
  # Large real runs have separate resumable commands. Missing evidence fails
  # below; this entry never silently substitutes a smaller synthetic workload.
  & $Python -m unittest verification.test_t06_image_release verification.test_t06_evidence.T06EvidenceTests.test_complete_model_global_order_current_rtl verification.test_t06_projection_reference verification.test_scene_io verification.test_t05_parallel_evidence verification.test_implementation_status -v
  if ($LASTEXITCODE -ne 0) { throw 'T06 evidence gate incomplete or failed' }
} finally { Pop-Location }
