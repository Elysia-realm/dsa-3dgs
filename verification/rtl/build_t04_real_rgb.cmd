@echo off
setlocal
set "MSYSTEM=UCRT64"
set "CHERE_INVOKING=1"
set "GS_T04_ROOT=%~dp0\..\.."
"D:\Tools\msys64\usr\bin\bash.exe" -lc "cd \"$(cygpath -u \"$GS_T04_ROOT\")\" && verilator --binary --build -j 4 -CFLAGS -D_GLIBCXX_USE_CXX11_ABI=0 --sv --timing -Wno-fatal -DSYNTHESIS -DTB_FINAL_RGB=1 -DTB_MAX_AXI_WRITES=64 -DTB_MAX_COUNT=128 -DTB_MAX_PIXELS=16384 -DTB_GID_W=32 -DTB_SEQ_W=16 -DTB_GROUP_CAPACITY=128 -DTB_SORT_CAPACITY=128 -DTB_STATE_ENTRIES=4096 -DTB_LANES=4 -Irtl/raster --top-module tb_real_dma_workload --Mdir tmp/verilator_t04_rgb -f verification/rtl/system_top_sources.f verification/rtl/tb_real_dma_workload.sv -o tb_t04_rgb.exe"
exit /b %ERRORLEVEL%
