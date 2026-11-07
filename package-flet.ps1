# Assemble a self-contained Lunoir V in dist/Lunoir-V: a relocatable copy of the
# Python the .venv was made from (same version, so pywin32 and the other compiled
# packages match), the venv's packages, the app, the V backend and Flet runtime,
# and the Lunoir files the app reads at run time (assets, i18n, licenses).
param([switch]$Zip, [switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    if (-not $SkipBuild) {
        & ./build-flet.ps1 -SkipDependencies
    }
    $dist = Join-Path $PSScriptRoot 'dist/Lunoir-V'
    if (Test-Path -LiteralPath $dist) { Remove-Item -LiteralPath $dist -Recurse -Force }
    $python = Join-Path $dist 'python'
    New-Item -ItemType Directory -Path $python -Force | Out-Null

    function Copy-Tree($from, $to, [string[]]$skipDirs = @(), [string[]]$skipFiles = @()) {
        $options = @($from, $to, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/XD', '__pycache__') + $skipDirs
        if ($skipFiles) { $options += @('/XF') + $skipFiles }
        & robocopy @options | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Could not copy $from" }
        $global:LASTEXITCODE = 0
    }

    $info = & .venv/Scripts/python.exe -c "import sys; print(sys.base_prefix); print(f'{sys.version_info[0]}{sys.version_info[1]}')"
    $base, $ver = $info[0], $info[1]
    foreach ($name in @('python.exe', 'pythonw.exe', "python$ver.dll", 'python3.dll',
                        'vcruntime140.dll', 'vcruntime140_1.dll', 'LICENSE.txt')) {
        Copy-Item -LiteralPath (Join-Path $base $name) -Destination $python
    }
    Copy-Tree (Join-Path $base 'DLLs') (Join-Path $python 'DLLs') @() @('_tkinter.pyd', 'tcl*.dll', 'tk*.dll', '*.ico')
    Copy-Tree (Join-Path $base 'Lib') (Join-Path $python 'Lib') @(
        (Join-Path $base 'Lib/site-packages'), 'test', 'idlelib', 'tkinter', 'turtledemo', 'ensurepip', 'lib2to3')
    Copy-Tree .venv/Lib/site-packages (Join-Path $python 'Lib/site-packages') @(
        'pip', 'pip-*', 'setuptools', 'setuptools-*', '_distutils_hack', 'pkg_resources') @(
        'distutils-precedence.pth', 'PyWin32.chm')
    # A ._pth file fixes sys.path (no PYTHONPATH, no user site-packages); `import site`
    # still adds Lib/site-packages and runs pywin32's .pth. `..` holds flet_lunoir.
    Set-Content -LiteralPath (Join-Path $python "python$ver._pth") -Encoding ascii -Value @(
        '.', 'DLLs', 'Lib', '..', 'import site')

    Copy-Tree flet_lunoir (Join-Path $dist 'flet_lunoir') @('tests', 'launcher') @('flet-windows.zip')
    Copy-Tree lunoir/src/renderer/src/assets (Join-Path $dist 'lunoir/src/renderer/src/assets')
    Copy-Tree lunoir/src/shared/i18n (Join-Path $dist 'lunoir/src/shared/i18n')
    Copy-Item -LiteralPath lunoir/LICENSE, lunoir/CREDITS.md -Destination (Join-Path $dist 'lunoir')
    Copy-Item -LiteralPath LICENSE, README.md, Lunoir-V.exe -Destination $dist

    & (Join-Path $python 'python.exe') -c "import flet, win32gui, pythoncom, flet_lunoir.app"
    if ($LASTEXITCODE -ne 0) { throw 'The packaged Python cannot import the app.' }
    $size = (Get-ChildItem -LiteralPath $dist -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
    Write-Host ("Packaged dist/Lunoir-V ({0:N0} MB)." -f $size)
    if ($Zip) {
        $archive = Join-Path $PSScriptRoot 'dist/Lunoir-V.zip'
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive }
        Compress-Archive -Path $dist -DestinationPath $archive
        Write-Host 'Wrote dist/Lunoir-V.zip.'
    }
} finally {
    Pop-Location
}
