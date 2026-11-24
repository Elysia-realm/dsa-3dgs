$root = Split-Path -Parent $PSScriptRoot
$status = Join-Path $root "tmp\bonsai_batch0_verilator_background_2026-08-16.status"
$log = Join-Path $root "tmp\bonsai_batch0_verilator_background_2026-08-16.log"
$frame = Join-Path $root "experiments\full_frame_batches\bonsai_cam_mid_d64_c256\rtl_batch_0000\frame_state.memh"

$process = Get-Process -Name "tb_bonsai1024" -ErrorAction SilentlyContinue
if ($process) {
    Write-Output ("RUNNING pid={0} cpu_seconds={1} elapsed_seconds={2} memory_mb={3}" -f `
        $process.Id, [math]::Round($process.CPU, 1),
        [math]::Round(((Get-Date) - $process.StartTime).TotalSeconds, 1),
        [math]::Round($process.WorkingSet64 / 1MB, 1))
    exit 0
}

if (-not (Test-Path -LiteralPath $status)) {
    Write-Output "ENDED_WITHOUT_STATUS"
    exit 2
}
Get-Content -LiteralPath $status
if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 80 }
if (-not (Test-Path -LiteralPath $frame)) {
    Write-Output "FRAME_MISSING"
    exit 3
}
$lineCount = (Get-Content -LiteralPath $frame).Count
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $frame).Hash
Write-Output "frame_lines=$lineCount"
Write-Output "frame_sha256=$hash"
if ($lineCount -ne 2752) { exit 4 }
if (-not (Select-String -LiteralPath $log -SimpleMatch "PASS: tb_real_dma_workload" -Quiet)) { exit 5 }
exit 0
