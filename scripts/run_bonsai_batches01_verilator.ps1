$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $root "tmp\verilator_bonsai1024_obj\tb_bonsai1024.exe"
$batch0 = Join-Path $root "experiments\full_frame_batches\bonsai_cam_mid_d64_c256\rtl_batch_0000"
$batch1 = Join-Path $root "experiments\full_frame_batches\bonsai_cam_mid_d64_c256\rtl_batch_0001"
$output = Join-Path $root "experiments\full_frame_batches\bonsai_cam_mid_d64_c256\rtl_batches_0000_0001"
$log = Join-Path $root "tmp\bonsai_batches01_verilator_2026-08-16.log"
$status = Join-Path $root "tmp\bonsai_batches01_verilator_2026-08-16.status"
$env:PATH = "D:\Tools\msys64\ucrt64\bin;" + $env:PATH

if (-not (Test-Path -LiteralPath $exe)) {
    throw "Verilator model not found: $exe"
}
New-Item -ItemType Directory -Path $output -Force | Out-Null
Remove-Item -LiteralPath $log, $status -Force -ErrorAction SilentlyContinue
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
& $exe `
    "+MEAN=$batch0\mean.memh" `
    "+ATTR=$batch0\attribute_sparse.memh" `
    "+GLOBAL_GIDS=$batch0\global_gid.memh" `
    "+CAMERA=$batch0\camera.memh" `
    "+MEAN2=$batch1\mean.memh" `
    "+ATTR2=$batch1\attribute_sparse.memh" `
    "+GLOBAL_GIDS2=$batch1\global_gid.memh" `
    "+CAMERA2=$batch1\camera.memh" `
    "+FRAME=$output\frame_state.memh" `
    "+LABEL=bonsai_batches01_2047_verilator_4x4" `
    "+FRAME_MODE=3" `
    "+MAX_TIMEOUT=4000000" *> $log
$exitCode = $LASTEXITCODE
$stopwatch.Stop()
@(
    "exit_code=$exitCode"
    "wall_seconds=$([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))"
    "completed=$(Get-Date -Format o)"
) | Set-Content -LiteralPath $status -Encoding ascii
exit $exitCode
