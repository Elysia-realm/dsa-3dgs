param([switch]$EvidenceOnly,[switch]$Legacy20261018,
  [string]$Python='C:\Users\12104\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
$ErrorActionPreference='Stop'
if (-not $Legacy20261018) {
  & (Join-Path $PSScriptRoot 'run_t06_release.ps1') -EvidenceOnly:$EvidenceOnly -Python $Python
  return
}
# Historical gate retained explicitly. Its source bindings are Oct18 and it
# must not be used to sign the later selected-profile release.
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
  if (-not $EvidenceOnly) {
    & $Python scripts/check_t06_memory_layout.py
    if ($LASTEXITCODE -ne 0) { throw 'T06 physical address guard tests failed' }
    & $Python scripts/check_t06_image_units.py
    if ($LASTEXITCODE -ne 0) { throw 'T06 image semantic unit tests failed' }
    & $Python -c "from pathlib import Path; from scripts import run_t06_protocol_tests as p; p.OUT=Path('experiments/t06_20261018/protocol'); p.main()"
    if ($LASTEXITCODE -ne 0) { throw 'T06 protocol tests failed' }
    cmd /c verification\rtl\run_iverilog.cmd
    if ($LASTEXITCODE -ne 0) { throw 'RTL regression failed' }
    cmd /c verification\rtl\run_verilator_lint.cmd
    if ($LASTEXITCODE -ne 0) { throw 'RTL lint failed' }
  }
  # Large real runs have separate resumable commands. Missing evidence fails
  # below; this entry never silently substitutes a smaller synthetic workload.
  $t06GateDir=Join-Path (Get-Location) 'experiments/t06_20261018/logs'
  New-Item -ItemType Directory -Force -Path $t06GateDir | Out-Null
  $t06GateAttempt=Join-Path $t06GateDir ('python_gate_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff')+'.log')
  & $Python -m unittest verification.test_t06_image_release verification.test_t06_evidence.T06EvidenceTests.test_complete_model_global_order_current_rtl verification.test_t06_projection_reference verification.test_scene_io verification.test_t05_parallel_evidence verification.test_implementation_status -v 2>&1 | Tee-Object -FilePath $t06GateAttempt
  Copy-Item -LiteralPath $t06GateAttempt -Destination (Join-Path $t06GateDir 'python_final.log') -Force
  if ($LASTEXITCODE -ne 0) { throw 'T06 evidence gate incomplete or failed' }
} finally { Pop-Location }
