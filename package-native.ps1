param([switch]$Zip, [switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    if (-not $SkipBuild) { & ./build-native.ps1 }
    $distRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'dist'))
    $dist = [System.IO.Path]::GetFullPath((Join-Path $distRoot 'Lunoir-V'))
    if ((Split-Path -Parent $dist) -ne $distRoot -or (Split-Path -Leaf $dist) -ne 'Lunoir-V') { throw 'Unexpected package output path.' }
    if (Test-Path -LiteralPath $dist) { Remove-Item -LiteralPath $dist -Recurse -Force }
    New-Item -ItemType Directory -Path $dist -Force | Out-Null

    function Copy-Tree([string]$From, [string]$To) {
        & robocopy $From $To /E /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Could not copy $From" }
        $global:LASTEXITCODE = 0
    }

    Copy-Tree 'runtime/flet' (Join-Path $dist 'runtime/flet')
    Copy-Tree 'lunoir/src/renderer/src/assets' (Join-Path $dist 'lunoir/src/renderer/src/assets')
    Copy-Tree 'lunoir/i18n' (Join-Path $dist 'lunoir/i18n')
    Copy-Item -LiteralPath lunoir/LICENSE, lunoir/CREDITS.md -Destination (Join-Path $dist 'lunoir')
    Copy-Item -LiteralPath LICENSE, README.md, VERSION, Lunoir-V.exe, libmpv-2.dll -Destination $dist
    $size = (Get-ChildItem -LiteralPath $dist -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
    $appVersion = ([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'VERSION'))).Trim()
    Write-Host ("Packaged Lunoir V $appVersion in dist/Lunoir-V ({0:N0} MB, no Python)." -f $size)
    if ($Zip) {
        $archive = Join-Path $distRoot 'Lunoir-V.zip'
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive }
        Compress-Archive -Path $dist -DestinationPath $archive
        Write-Host 'Wrote dist/Lunoir-V.zip.'
    }
} finally {
    Pop-Location
}
