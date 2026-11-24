param(
    [switch]$EvidenceOnly,
    [string]$Python = 'C:\Users\12104\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
function Invoke-T05Python([string[]]$TaskArguments) {
    & $Python @TaskArguments
    if ($LASTEXITCODE -ne 0) { throw "T05 failed: $($TaskArguments -join ' ')" }
}
Push-Location $taskRoot
try {
    if (-not $EvidenceOnly) {
        Invoke-T05Python @('scripts/run_t05_sorters.py')
        Invoke-T05Python @('scripts/map_t05_modules.py')
        Invoke-T05Python @('scripts/run_t05_real.py', 'prepare')
        Invoke-T05Python @('scripts/run_t05_real.py', 'build', '--simulator', 'icarus')
        Invoke-T05Python @('scripts/run_t05_real.py', 'build', '--simulator', 'verilator')
        Invoke-T05Python @('scripts/run_t05_real.py', 'run', '--simulator', 'auto')
        Invoke-T05Python @('scripts/run_t05_reconfiguration.py')
        Invoke-T05Python @('scripts/check_t05_simulator_equivalence.py')
        cmd /c verification\rtl\run_iverilog.cmd
        if ($LASTEXITCODE -ne 0) { throw 'RTL regression failed' }
        cmd /c verification\rtl\run_verilator_lint.cmd
        if ($LASTEXITCODE -ne 0) { throw 'Production lint failed' }
    }
    Invoke-T05Python @('-m','unittest','verification.test_implementation_status',
        'verification.test_t05_evidence','verification.test_t04_real_rgb_evidence',
        'verification.test_t04_rgb_frame','verification.test_rtl_contract','-v')
} finally {
    Pop-Location
}
