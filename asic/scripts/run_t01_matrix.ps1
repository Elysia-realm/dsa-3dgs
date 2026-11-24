param(
    [string]$Python = "$PSScriptRoot\..\..\tmp\toolchains\yowasp\Scripts\python.exe",
    [string]$Yosys = "$PSScriptRoot\..\..\tmp\toolchains\oss-cad-suite-20260706\oss-cad-suite\bin\yosys.exe",
    [string]$NangateLib = "$PSScriptRoot\..\..\tmp\toolchains\freepdk45\NangateOpenCellLibrary_typical.lib",
    [string]$ICsproutLib = "$PSScriptRoot\..\..\tmp\toolchains\icsprout55\rvt-v1.10.102\liberty\ics55_LLSC_H7CR_typ_tt_1p2_25_nldm.lib",
    [switch]$ReportOnly
)
$ErrorActionPreference = 'Stop'
$targets = @(
    @{pdk='freepdk45_nangate45'; corner='tt_1p10v_25c'; lib=$NangateLib; driver='BUF_X4'; load='3.899'},
    @{pdk='icsprout55_rvt'; corner='tt_1p20v_25c'; lib=$ICsproutLib; driver='BUFX1H7R'; load='3.539972'}
)
foreach ($target in $targets) {
    foreach ($variant in @('shared_baseline', 'alpha_only')) {
        $runArgs = @("$PSScriptRoot\run_t01_synthesis.py", '--yosys', $Yosys,
            '--liberty', $target.lib, '--pdk', $target.pdk, '--corner', $target.corner,
            '--variant', $variant, '--clock-mhz', '200', '--driver-cell', $target.driver,
            '--output-load-ff', $target.load)
        if ($ReportOnly) { $runArgs += '--report-only' }
        & $Python @runArgs
        if ($LASTEXITCODE -ne 0) { throw "T01 failed: $($target.pdk) / $variant; inspect mapping.log" }
    }
}
