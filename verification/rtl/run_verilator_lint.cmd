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
set "GS_REPO_ROOT=%REPO_ROOT%"
"%MSYS2_ROOT%\usr\bin\bash.exe" -lc "cd \"$(cygpath -u \"$GS_REPO_ROOT\")\" && verilator --lint-only --sv --timing -Wall -Wno-fatal -Irtl/raster --top-module gs_accel_system_top -f verification/rtl/system_top_sources.f"
set "LINT_RC=%ERRORLEVEL%"

if not "%LINT_RC%"=="0" (
    echo FAIL: Verilator lint returned %LINT_RC%
    exit /b %LINT_RC%
)

echo PASS: Verilator lint completed for gs_accel_system_top
exit /b 0
