$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $root "tmp\verilator_bonsai1024_obj\tb_bonsai1024.exe"
$batch = Join-Path $root "experiments\full_frame_batches\bonsai_cam_mid_d64_c256\rtl_batch_0000"
$log = Join-Path $root "tmp\bonsai_batch0_verilator_background_2026-08-16.log"
$status = Join-Path $root "tmp\bonsai_batch0_verilator_background_2026-08-16.status"
$env:PATH = "D:\Tools\msys64\ucrt64\bin;" + $env:PATH

Remove-Item -LiteralPath $log, $status -Force -ErrorAction SilentlyContinue
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
& $exe `
    "+MEAN=$batch\mean.memh" `
    "+ATTR=$batch\attribute_sparse.memh" `
    "+GLOBAL_GIDS=$batch\global_gid.memh" `
    "+CAMERA=$batch\camera.memh" `
    "+FRAME=$batch\frame_state.memh" `
    "+LABEL=bonsai_batch0_1024_verilator_4x4" `
    "+FRAME_MODE=3" `
    "+MAX_TIMEOUT=2000000" *> $log
$exitCode = $LASTEXITCODE
$stopwatch.Stop()
@(
    "exit_code=$exitCode"
    "wall_seconds=$([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))"
    "completed=$(Get-Date -Format o)"
) | Set-Content -LiteralPath $status -Encoding ascii
exit $exitCode
