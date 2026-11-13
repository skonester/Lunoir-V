param([switch]$SkipDependencies)

$ErrorActionPreference = 'Stop'
$env:V_C_ERROR_BUG_REPORT_DISABLED = '1'
Push-Location -LiteralPath $PSScriptRoot
try {
    $runtime = Join-Path $PSScriptRoot 'runtime/flet'
    $client = Join-Path $runtime 'flet/flet.exe'
    if (-not (Test-Path -LiteralPath $client)) {
        if ($SkipDependencies) { throw 'Flet desktop runtime is missing. Run build-native.ps1 without -SkipDependencies once.' }
        $version = '1.0.5'
        $sha256 = '6b5bddbcf2df8d0986dec60eab0b28c8cd8be1c0cd96cd73d5e34a3122ca867d'
        $staging = Join-Path ([System.IO.Path]::GetTempPath()) ('lunoir-flet-' + [guid]::NewGuid())
        $archive = Join-Path $staging 'flet-windows.zip'
        New-Item -ItemType Directory -Path $staging | Out-Null
        try {
            Write-Host "Downloading Flet $version Windows runtime..."
            & curl.exe --fail --location --retry 3 --output $archive "https://github.com/flet-dev/flet/releases/download/v$version/flet-windows.zip"
            if ($LASTEXITCODE -ne 0) { throw 'Could not download the Flet runtime.' }
            if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha256) { throw 'Flet runtime checksum mismatch.' }
            $unpacked = Join-Path $staging 'unpacked'
            Expand-Archive -LiteralPath $archive -DestinationPath $unpacked
            if (-not (Test-Path -LiteralPath (Join-Path $unpacked 'flet/flet.exe'))) { throw 'The Flet archive did not contain flet/flet.exe.' }
            & robocopy $unpacked $runtime /E /NFL /NDL /NJH /NJS /NP | Out-Null
            if ($LASTEXITCODE -ge 8) { throw 'Could not install the Flet runtime.' }
            $global:LASTEXITCODE = 0
        } finally {
            $resolved = [System.IO.Path]::GetFullPath($staging)
            $temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
            if (-not $resolved.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or -not ([System.IO.Path]::GetFileName($resolved)).StartsWith('lunoir-flet-')) { throw 'Refusing to clean an unexpected staging directory.' }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
    if (-not (Test-Path -LiteralPath 'libmpv-2.dll')) { throw 'The repository libmpv-2.dll is missing.' }
    & v -cc gcc -no-retry-compilation -subsystem windows -o Lunoir-V.exe ./v_lunoir
    if ($LASTEXITCODE -ne 0) { throw 'Could not build the native V player.' }
    $appVersion = ([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'VERSION'))).Trim()
    Write-Host "Built Lunoir-V $appVersion (Lunoir-V.exe): V controller, Flet desktop interface, libmpv playback. No Python runtime."
} finally {
    Pop-Location
}
