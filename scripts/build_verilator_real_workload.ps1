param(
    [int]$MaxCount = 1024,
    [int]$MaxPixels = 4096,
    [int]$GroupCapacity = 256,
    [int]$SortCapacity = 256,
    [int]$Lanes = 4,
    [int]$StateEntries = 4096,
    [int]$StateWindowEntries = 4,
    [int]$StateMshrCount = 4,
    [int]$ResponseBlendBypass = 1,
    [int]$BlendCommitBypass = 1,
    [int]$OperandIsolation = 1,
    [int]$StreamingDepthPrepass = 0,
    [string]$BuildTag = "real_1024_4x4"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$bash = "D:\Tools\msys64\usr\bin\bash.exe"
$obj = "tmp/verilator_$BuildTag`_obj"
$exeName = "tb_$BuildTag.exe"
$tmp = "D:/3DGS/tmp/msys_tmp"

if (-not (Test-Path -LiteralPath $bash)) {
    throw "MSYS2 bash not found at $bash"
}
New-Item -ItemType Directory -Path (Join-Path $root "tmp\msys_tmp") -Force | Out-Null

$defines = @(
    "-DTB_MAX_AXI_WRITES=64",
    "-DTB_MAX_COUNT=$MaxCount",
    "-DTB_MAX_PIXELS=$MaxPixels",
    "-DTB_GID_W=32",
    "-DTB_SEQ_W=16",
    "-DTB_GROUP_CAPACITY=$GroupCapacity",
    "-DTB_SORT_CAPACITY=$SortCapacity",
    "-DTB_STATE_ENTRIES=$StateEntries",
    "-DTB_LANES=$Lanes",
    "-DTB_STATE_WINDOW_ENTRIES=$StateWindowEntries",
    "-DTB_STATE_MSHR_COUNT=$StateMshrCount",
    "-DTB_RESPONSE_BLEND_BYPASS=$ResponseBlendBypass",
    "-DTB_BLEND_COMMIT_BYPASS=$BlendCommitBypass",
    "-DTB_OPERAND_ISOLATION=$OperandIsolation",
    "-DTB_USE_STREAMING_DEPTH_PREPASS=$StreamingDepthPrepass"
) -join " "

$env:MSYSTEM = "UCRT64"
$env:CHERE_INVOKING = "1"
$generate = @"
export TMP=/d/3DGS/tmp/msys_tmp TEMP=/d/3DGS/tmp/msys_tmp TMPDIR=/d/3DGS/tmp/msys_tmp
cd /d/3DGS
rm -rf $obj
verilator --cc --sv --timing -Wno-fatal -DSYNTHESIS $defines -Irtl/raster --top-module tb_real_dma_workload --Mdir $obj -f verification/rtl/system_top_sources.f verification/rtl/tb_real_dma_workload.sv --main -o $exeName
"@
& $bash -lc $generate
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$build = @"
export TMP=/d/3DGS/tmp/msys_tmp TEMP=/d/3DGS/tmp/msys_tmp TMPDIR=/d/3DGS/tmp/msys_tmp
cd /d/3DGS/$obj
make -f Vtb_real_dma_workload.mk -j 1 CPPFLAGS='-I. -ID:/Tools/msys64/ucrt64/share/verilator/include -ID:/Tools/msys64/ucrt64/share/verilator/include/vltstd -D_GLIBCXX_USE_CXX11_ABI=0 -DVL_TIME_CONTEXT -fcoroutines'
g++ -D_GLIBCXX_USE_CXX11_ABI=0 verilated.o verilated_timing.o verilated_threads.o Vtb_real_dma_workload__main.o Vtb_real_dma_workload__ALL.a -pthread -lpthread -latomic -o $exeName
"@
& $bash -lc $build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$exe = Join-Path $root ($obj.Replace("/", "\") + "\" + $exeName)
Write-Output $exe
