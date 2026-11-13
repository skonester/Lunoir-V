param(
    [Parameter(Mandatory = $true)][string]$Py2v,
    [string]$Compiler = 'v'
)

$ErrorActionPreference = 'Stop'
$py2vPath = (Get-Command -Name $Py2v -CommandType Application).Source
. (Join-Path $PSScriptRoot 'tools/py2v/resolve-compiler.ps1')
$compilerPath = Resolve-VCompiler $Compiler
$reportRoot = Join-Path $PSScriptRoot 'v_lunoir'
$outputRoot = Join-Path $reportRoot 'generated'
$utf8 = [System.Text.UTF8Encoding]::new($false)
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$previousV = $env:V
$previousVexe = $env:VEXE
$previousPath = $env:PATH
$previousBugReport = $env:V_C_ERROR_BUG_REPORT_DISABLED
Push-Location -LiteralPath $PSScriptRoot
try {
    # py2v's checker uses V; vfmt also needs VEXE to select the intended toolchain.
    $env:V = $compilerPath
    $env:VEXE = $compilerPath
    $env:PATH = (Split-Path -Parent $compilerPath) + [System.IO.Path]::PathSeparator + $previousPath
    $env:V_C_ERROR_BUG_REPORT_DISABLED = '1'
    $ErrorActionPreference = 'Continue'
    $output = @(& $py2vPath --package flet_lunoir -o v_lunoir/generated --check --jobs 2 2>&1 |
        ForEach-Object { $_.ToString() })
    $translationExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    [System.IO.File]::WriteAllLines((Join-Path $reportRoot 'translation.txt'), [string[]]$output, $utf8)
    $output | ForEach-Object { Write-Host $_ }

    $sources = @(Get-ChildItem -LiteralPath flet_lunoir -Filter '*.py' -File | Sort-Object Name)
    $files = @($sources | ForEach-Object {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name) + '.v'
        $generated = Join-Path $outputRoot ('py_flet_lunoir/' + $name)
        $exists = Test-Path -LiteralPath $generated -PathType Leaf
        [ordered]@{
            source = 'flet_lunoir/' + $_.Name
            source_sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            output = 'generated/py_flet_lunoir/' + $name
            output_sha256 = if ($exists) { (Get-FileHash -LiteralPath $generated -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
            emitted = $exists
        }
    })
    $missing = @($files | Where-Object { -not $_.emitted })

    # Match py2v/check.v: import the whole module through a synthetic entry point.
    # Checking a library directory or individual generated file can miss siblings.
    $entry = Join-Path $outputRoot ('py2v_diagnostics_' + [guid]::NewGuid().ToString('N') + '.v')
    try {
        [System.IO.File]::WriteAllText($entry, "module py2v_diagnostics`n`nimport py_flet_lunoir`n`npub fn unused() {}`n", $utf8)
        Push-Location -LiteralPath $outputRoot
        try {
            $ErrorActionPreference = 'Continue'
            $diagnostics = @(& $compilerPath -shared -check -nocolor ([System.IO.Path]::GetFileName($entry)) 2>&1 |
                ForEach-Object { $_.ToString() })
            $checkExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = 'Stop'
            Pop-Location
        }
        [System.IO.File]::WriteAllLines((Join-Path $reportRoot 'diagnostics.txt'), [string[]]$diagnostics, $utf8)
    } finally {
        Remove-Item -LiteralPath $entry -ErrorAction SilentlyContinue
    }

    $preparationPath = Join-Path (Split-Path -Parent $py2vPath) 'preparation.json'
    $summary = [regex]::Match(($output -join "`n"), '(?m)^py_flet_lunoir\t(\d+)\t')
    $report = [ordered]@{
        status = if ($translationExitCode -eq 0 -and $checkExitCode -eq 0 -and $missing.Count -eq 0) { 'compiler_check_passed' } else { 'requires_manual_porting' }
        compiler = ((& $compilerPath version) -join "`n")
        py2v_sha256 = (Get-FileHash -LiteralPath $py2vPath -Algorithm SHA256).Hash.ToLowerInvariant()
        tool_preparation = if (Test-Path -LiteralPath $preparationPath) { Get-Content -Raw -LiteralPath $preparationPath | ConvertFrom-Json } else { $null }
        translation_exit_code = $translationExitCode
        compiler_exit_code = $checkExitCode
        reported_errors = if ($summary.Success) { [int]$summary.Groups[1].Value } else { $null }
        emitted_files = $files.Count - $missing.Count
        source_files = $files.Count
        files = $files
    }
    [System.IO.File]::WriteAllText((Join-Path $reportRoot 'conversion.json'), ($report | ConvertTo-Json -Depth 8) + "`n", $utf8)
    Write-Host "Generated $($report.emitted_files)/$($report.source_files) V files. Status: $($report.status)."
    Write-Host 'Reports: v_lunoir/translation.txt, v_lunoir/diagnostics.txt, v_lunoir/conversion.json'
    if ($report.status -ne 'compiler_check_passed') { exit 1 }
} finally {
    $env:V = $previousV
    $env:VEXE = $previousVexe
    $env:PATH = $previousPath
    $env:V_C_ERROR_BUG_REPORT_DISABLED = $previousBugReport
    Pop-Location
}
