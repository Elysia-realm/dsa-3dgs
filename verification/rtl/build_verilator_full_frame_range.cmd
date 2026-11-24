@echo off
setlocal

set "REPO_ROOT=%~dp0\..\.."
for %%I in ("%REPO_ROOT%") do set "REPO_ROOT=%%~fI"
set "MSYS2_ROOT=D:\Tools\msys64"

if not exist "%MSYS2_ROOT%\usr\bin\bash.exe" (
    echo ERROR: MSYS2 bash not found at %MSYS2_ROOT%\usr\bin\bash.exe
    exit /b 2
)
if not exist "%MSYS2_ROOT%\ucrt64\bin\verilator" (
    echo ERROR: UCRT64 Verilator not found at %MSYS2_ROOT%\ucrt64\bin\verilator
    exit /b 2
)

set "MSYSTEM=UCRT64"
set "CHERE_INVOKING=1"
rem GCC 16.2.0-3's new C++11 ABI emits an unresolved basic_string C4 symbol.
rem Verilator and its generated harness are built together, so the supported
rem libstdc++ compatibility ABI is a safe, local workaround for this model.
set "MAKEFLAGS=-B"
set "GS_REPO_ROOT=%REPO_ROOT%"
set "MODEL_EXE=%REPO_ROOT%\tmp\verilator_bonsai1024_range_obj\tb_bonsai1024_range.exe"
if exist "%MODEL_EXE%" del /q "%MODEL_EXE%"

"%MSYS2_ROOT%\usr\bin\bash.exe" -lc "cd \"$(cygpath -u \"$GS_REPO_ROOT\")\" && verilator --binary --build -j 4 -CFLAGS -D_GLIBCXX_USE_CXX11_ABI=0 --sv --timing -Wno-fatal -DSYNTHESIS -DTB_MAX_AXI_WRITES=64 -DTB_MAX_COUNT=1024 -DTB_MAX_PIXELS=4096 -DTB_GID_W=32 -DTB_SEQ_W=16 -DTB_GROUP_CAPACITY=256 -DTB_SORT_CAPACITY=256 -DTB_STATE_ENTRIES=4096 -DTB_LANES=4 -DTB_STATE_WINDOW_ENTRIES=4 -DTB_STATE_MSHR_COUNT=4 -DTB_RESPONSE_BLEND_BYPASS=1 -DTB_BLEND_COMMIT_BYPASS=1 -DTB_OPERAND_ISOLATION=1 -Irtl/raster --top-module tb_real_dma_workload --Mdir tmp/verilator_bonsai1024_range_obj -f verification/rtl/system_top_sources.f verification/rtl/tb_real_dma_workload.sv -o tb_bonsai1024_range.exe"
set "BUILD_RC=%ERRORLEVEL%"

if not "%BUILD_RC%"=="0" (
    echo FAIL: Verilator full-frame model generation returned %BUILD_RC%
    exit /b %BUILD_RC%
)

if not exist "%MODEL_EXE%" (
    echo FAIL: expected executable was not generated
    exit /b 3
)

echo PASS: Verilator full-frame range model built
exit /b 0
