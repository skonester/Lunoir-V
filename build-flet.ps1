param([switch]$SkipDependencies)

$ErrorActionPreference = 'Stop'
$env:V_C_ERROR_BUG_REPORT_DISABLED = '1'
Push-Location -LiteralPath $PSScriptRoot
try {
    if (-not (Test-Path -LiteralPath '.venv/Scripts/python.exe')) {
        & python -m venv .venv
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the Python environment.' }
    }
    if (-not $SkipDependencies) {
        & .venv/Scripts/python.exe -m pip install -r flet_lunoir/requirements.txt
        if ($LASTEXITCODE -ne 0) { throw 'Could not install Flet dependencies.' }
    }
    New-Item -ItemType Directory -Path flet_lunoir/runtime -Force | Out-Null
    & .venv/Scripts/python.exe -m flet_lunoir.provision
    if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the Flet desktop runtime.' }
    & v -cc gcc -no-retry-compilation -subsystem windows -o flet_lunoir/runtime/vmpv-host.exe ./host
    if ($LASTEXITCODE -ne 0) { throw 'Could not build the V mpv backend.' }
    Copy-Item -LiteralPath libmpv-2.dll -Destination flet_lunoir/runtime/libmpv-2.dll -Force
    & v -cc gcc -no-retry-compilation -subsystem windows -o Lunoir-V.exe ./flet_lunoir/launcher
    if ($LASTEXITCODE -ne 0) { throw 'Could not build the desktop entry point.' }
    Write-Host 'Built Lunoir-V.exe. Double-click it to open the Flet interface.'
} finally {
    Pop-Location
}
