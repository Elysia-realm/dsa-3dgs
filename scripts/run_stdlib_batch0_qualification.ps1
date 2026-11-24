$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root "scripts\build_full_frame_rtl_batch_stdlib.cpp"
$exe = Join-Path $root "tmp\build_full_frame_rtl_batch_stdlib.exe"
$index = Join-Path $root "experiments\full_frame_batches\bonsai_cam_mid_d64_c256"
$output = Join-Path $index "rtl_batch_0000_stdlib"
$log = Join-Path $root "tmp\stdlib_batch0_qualification_2026-08-16.log"
$status = Join-Path $root "tmp\stdlib_batch0_qualification_2026-08-16.status"
$env:PATH = "D:\Tools\msys64\ucrt64\bin;" + $env:PATH
Remove-Item -LiteralPath $log, $status -Force -ErrorAction SilentlyContinue
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
& "D:\Tools\msys64\ucrt64\bin\g++.exe" -std=c++20 -O2 $source -o $exe 2>&1 | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) {
    throw "stdlib batch builder compilation failed with exit code $LASTEXITCODE"
}
& $exe `
    (Join-Path $root "data\bonsai\point_cloud\iteration_30000\point_cloud.ply") `
    (Join-Path $index "depth_gid_index.bin") `
    (Join-Path $index "mean_stream.bin") `
    0 1024 14112 14891 15502 $output *>> $log
$exitCode = $LASTEXITCODE
$stopwatch.Stop()
@(
    "exit_code=$exitCode"
    "wall_seconds=$([math]::Round($stopwatch.Elapsed.TotalSeconds, 3))"
    "completed=$(Get-Date -Format o)"
) | Set-Content -LiteralPath $status -Encoding ascii
exit $exitCode
