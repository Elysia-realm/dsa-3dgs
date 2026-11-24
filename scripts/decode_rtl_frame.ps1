param(
    [Parameter(Mandatory = $true)][string]$State,
    [Parameter(Mandatory = $true)][int]$Width,
    [Parameter(Mandatory = $true)][int]$Height,
    [Parameter(Mandatory = $true)][string]$Output,
    [string]$Metadata
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$lines = @(Get-Content -LiteralPath $State | Where-Object { $_.Trim() })
if ($lines.Count -ne $Width * $Height) {
    throw "expected $($Width * $Height) pixels, got $($lines.Count)"
}

$bitmap = New-Object System.Drawing.Bitmap($Width, $Height)
$nonzero = 0
$rgbMin = @(255, 255, 255)
$rgbMax = @(0, 0, 0)
$tMin = 65535
$tMax = 0
$mask13 = [System.Numerics.BigInteger]8191
$mask16 = [System.Numerics.BigInteger]65535

try {
    for ($pixel = 0; $pixel -lt $lines.Count; $pixel++) {
        $word = [System.Numerics.BigInteger]::Parse(
            "0" + $lines[$pixel].Trim(),
            [System.Globalization.NumberStyles]::AllowHexSpecifier)
        $q = @(
            [int]($word -band $mask13),
            [int](($word -shr 13) -band $mask13),
            [int](($word -shr 26) -band $mask13)
        )
        $rgb = @()
        for ($channel = 0; $channel -lt 3; $channel++) {
            $value = [math]::Max(0, [math]::Min(255, [math]::Round($q[$channel] * 255.0 / 4096.0)))
            $rgb += [int]$value
            $rgbMin[$channel] = [math]::Min($rgbMin[$channel], $value)
            $rgbMax[$channel] = [math]::Max($rgbMax[$channel], $value)
        }
        if ($rgb[0] -ne 0 -or $rgb[1] -ne 0 -or $rgb[2] -ne 0) { $nonzero++ }
        $t = [int](($word -shr 39) -band $mask16)
        $tMin = [math]::Min($tMin, $t)
        $tMax = [math]::Max($tMax, $t)
        $x = $pixel % $Width
        $y = [math]::Floor($pixel / $Width)
        $bitmap.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($rgb[0], $rgb[1], $rgb[2]))
    }
    $outputPath = [System.IO.Path]::GetFullPath($Output)
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($outputPath)) | Out-Null
    $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $bitmap.Dispose()
}

if ($Metadata) {
    [ordered]@{
        state = [System.IO.Path]::GetFullPath($State)
        width = $Width
        height = $Height
        nonzero_pixels = $nonzero
        rgb_min = $rgbMin
        rgb_max = $rgbMax
        transmittance_min = $tMin
        transmittance_max = $tMax
    } | ConvertTo-Json | Set-Content -LiteralPath $Metadata -Encoding utf8
}
Write-Output ([System.IO.Path]::GetFullPath($Output))
