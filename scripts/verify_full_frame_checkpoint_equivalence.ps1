param(
    [Parameter(Mandatory = $true)][string]$IndexDir,
    [Parameter(Mandatory = $true)][int]$FirstBatch,
    [Parameter(Mandatory = $true)][int]$SplitBatch,
    [Parameter(Mandatory = $true)][int]$LastBatch,
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [string]$Executable = "",
    [int]$MaxTimeoutPerBatch = 2000000,
    [int]$FrameMode = 3
)

$ErrorActionPreference = "Stop"
if ($FirstBatch -lt 0 -or $SplitBatch -lt $FirstBatch -or $LastBatch -le $SplitBatch) {
    throw "expected FirstBatch <= SplitBatch < LastBatch"
}

$runner = Join-Path $PSScriptRoot "run_full_frame_rtl_range.ps1"
$outputRoot = [System.IO.Path]::GetFullPath($OutputDir)
$continuousDir = Join-Path $outputRoot "continuous"
$prefixDir = Join-Path $outputRoot "prefix"
$resumedDir = Join-Path $outputRoot "resumed"

$common = @{
    IndexDir = $IndexDir
    MaxTimeoutPerBatch = $MaxTimeoutPerBatch
    FrameMode = $FrameMode
}
if ($Executable) { $common.Executable = $Executable }

& $runner @common -FirstBatch $FirstBatch -LastBatch $LastBatch -OutputDir $continuousDir
if ($LASTEXITCODE -ne 0) { throw "continuous range simulation failed" }

& $runner @common -FirstBatch $FirstBatch -LastBatch $SplitBatch -OutputDir $prefixDir
if ($LASTEXITCODE -ne 0) { throw "checkpoint prefix simulation failed" }

$checkpoint = Join-Path $prefixDir "frame_state.memh"
& $runner @common -FirstBatch ($SplitBatch + 1) -LastBatch $LastBatch `
    -OutputDir $resumedDir -StateIn $checkpoint
if ($LASTEXITCODE -ne 0) { throw "checkpoint resumed simulation failed" }

$continuousFrame = Join-Path $continuousDir "frame_state.memh"
$resumedFrame = Join-Path $resumedDir "frame_state.memh"
$continuousHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $continuousFrame).Hash
$resumedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resumedFrame).Hash
$byteEqual = [System.Linq.Enumerable]::SequenceEqual(
    [System.IO.File]::ReadAllBytes($continuousFrame),
    [System.IO.File]::ReadAllBytes($resumedFrame)
)

$result = [ordered]@{
    first_batch = $FirstBatch
    split_batch = $SplitBatch
    last_batch = $LastBatch
    continuous_frame = $continuousFrame
    resumed_frame = $resumedFrame
    continuous_sha256 = $continuousHash
    resumed_sha256 = $resumedHash
    byte_equal = $byteEqual
    completed = (Get-Date -Format o)
}
$resultPath = Join-Path $outputRoot "checkpoint_equivalence.json"
$result | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding utf8
$result | ConvertTo-Json

if (-not $byteEqual) { throw "checkpoint result differs from continuous result" }
Write-Output "PASS: checkpoint result is byte-identical to continuous result"

