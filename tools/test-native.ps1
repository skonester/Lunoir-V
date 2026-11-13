param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$env:V_C_ERROR_BUG_REPORT_DISABLED = '1'
$root = Split-Path -Parent $PSScriptRoot
$previousPath = $env:PATH
Push-Location -LiteralPath $root
try {
    $env:PATH = $root + [System.IO.Path]::PathSeparator + $previousPath
    if (-not $SkipBuild) { & ./build-native.ps1 -SkipDependencies }
    # V otherwise infers a GUI subsystem from Win32 imports and hides test diagnostics.
    & v -subsystem console -cc gcc -no-retry-compilation test ./v_lunoir
    if ($LASTEXITCODE -ne 0) { throw 'The native V tests failed.' }
} finally {
    $env:PATH = $previousPath
    Pop-Location
}
