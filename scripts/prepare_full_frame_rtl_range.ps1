param(
    [Parameter(Mandatory = $true)][string]$IndexDir,
    [Parameter(Mandatory = $true)][int]$FirstBatch,
    [Parameter(Mandatory = $true)][int]$LastBatch,
    [string]$ScenePly = "",
    [string]$Python = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$pythonExe = $Python
if (-not $pythonExe) {
    $bundledPython = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
    if (Test-Path -LiteralPath $bundledPython) {
        $pythonExe = $bundledPython
    } else {
        $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
        if ($pythonCommand) { $pythonExe = $pythonCommand.Source }
    }
}
$builder = Join-Path $root "scripts\build_full_frame_rtl_batch.py"
$indexRoot = [System.IO.Path]::GetFullPath($IndexDir)
if (-not $pythonExe -or -not (Test-Path -LiteralPath $pythonExe)) {
    throw "Python not found; pass -Python with an explicit python.exe path"
}
if ($FirstBatch -lt 0 -or $LastBatch -lt $FirstBatch) {
    throw "invalid inclusive batch range $FirstBatch..$LastBatch"
}

$manifest = Get-Content -Raw -LiteralPath (Join-Path $indexRoot "manifest.json") | ConvertFrom-Json
if ($LastBatch -ge [int]$manifest.batch_count) {
    throw "batch $LastBatch exceeds manifest maximum $([int]$manifest.batch_count - 1)"
}
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$generated = 0
$reused = 0
for ($batchIndex = $FirstBatch; $batchIndex -le $LastBatch; $batchIndex++) {
    $output = Join-Path $indexRoot ("rtl_batch_{0:D4}" -f $batchIndex)
    $required = @("mean.memh", "attribute_sparse.memh", "global_gid.memh", "camera.memh", "manifest.json")
    $complete = -not $Force
    foreach ($name in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $output $name))) { $complete = $false }
    }
    if ($complete) { $reused++; continue }
    $arguments = @($builder, "--index-dir", $indexRoot, "--batch-index", $batchIndex, "--output", $output)
    if ($ScenePly) { $arguments += @("--scene-ply", [System.IO.Path]::GetFullPath($ScenePly)) }
    & $pythonExe @arguments
    if ($LASTEXITCODE -ne 0) { throw "batch $batchIndex generation failed with exit code $LASTEXITCODE" }
    $generated++
}
$stopwatch.Stop()
[ordered]@{
    index_dir = $indexRoot
    first_batch = $FirstBatch
    last_batch = $LastBatch
    generated = $generated
    reused = $reused
    wall_seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
} | ConvertTo-Json
