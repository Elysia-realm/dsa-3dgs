param(
    [Parameter(Mandatory = $true)][string]$IndexDir,
    [Parameter(Mandatory = $true)][int]$FirstBatch,
    [Parameter(Mandatory = $true)][int]$LastBatch,
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [string]$StateIn = "",
    [string]$Executable = "",
    [int]$MaxTimeoutPerBatch = 2000000,
    [int]$FrameMode = 3
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$indexRoot = [System.IO.Path]::GetFullPath($IndexDir)
$outputRoot = [System.IO.Path]::GetFullPath($OutputDir)
if (-not $Executable) {
    $Executable = Join-Path $root "tmp\verilator_bonsai1024_range_obj\tb_bonsai1024_range.exe"
}
$Executable = [System.IO.Path]::GetFullPath($Executable)
if (-not (Test-Path -LiteralPath $Executable)) { throw "Verilator model not found: $Executable" }
if ($FirstBatch -lt 0 -or $LastBatch -lt $FirstBatch) { throw "invalid batch range" }
foreach ($batchIndex in $FirstBatch..$LastBatch) {
    $batch = Join-Path $indexRoot ("rtl_batch_{0:D4}" -f $batchIndex)
    foreach ($name in "mean.memh", "attribute_sparse.memh", "global_gid.memh", "camera.memh") {
        if (-not (Test-Path -LiteralPath (Join-Path $batch $name))) {
            throw "missing batch input: $(Join-Path $batch $name)"
        }
    }
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$frame = Join-Path $outputRoot "frame_state.memh"
$log = Join-Path $outputRoot "verilator.log"
$status = Join-Path $outputRoot "status.json"
$env:PATH = "D:\Tools\msys64\ucrt64\bin;" + $env:PATH
$arguments = @(
    "+BATCH_ROOT=$($indexRoot.Replace('\','/'))",
    "+BATCH_FIRST=$FirstBatch", "+BATCH_LAST=$LastBatch",
    "+FRAME=$frame", "+LABEL=full_frame_batches_${FirstBatch}_${LastBatch}",
    "+FRAME_MODE=$FrameMode", "+MAX_TIMEOUT=$($MaxTimeoutPerBatch * ($LastBatch - $FirstBatch + 1))"
)
if ($StateIn) {
    $statePath = [System.IO.Path]::GetFullPath($StateIn)
    if (-not (Test-Path -LiteralPath $statePath)) { throw "checkpoint state not found: $statePath" }
    $arguments += "+STATE_IN=$statePath"
}
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
& $Executable @arguments *> $log
$exitCode = $LASTEXITCODE
$stopwatch.Stop()
$frameSha = if (Test-Path -LiteralPath $frame) { (Get-FileHash -Algorithm SHA256 $frame).Hash } else { $null }
[ordered]@{
    exit_code = $exitCode
    first_batch = $FirstBatch
    last_batch = $LastBatch
    state_in = if ($StateIn) { [System.IO.Path]::GetFullPath($StateIn) } else { $null }
    frame = $frame
    frame_sha256 = $frameSha
    wall_seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
    completed = (Get-Date -Format o)
} | ConvertTo-Json | Set-Content -LiteralPath $status -Encoding utf8
Get-Content -Raw -LiteralPath $status
exit $exitCode
