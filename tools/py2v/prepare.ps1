param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$Compiler
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
. (Join-Path $PSScriptRoot 'resolve-compiler.ps1')
$compilerPath = Resolve-VCompiler $Compiler
if (-not (Test-Path -LiteralPath (Join-Path $source 'frontend/ast_dump.py'))) {
    throw 'SourceDirectory must contain the py2v sources and frontend/ast_dump.py.'
}

# Work on a private copy. Never change the supplied py2v checkout or installed V.
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('lunoir-py2v-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $scratch | Out-Null
Get-ChildItem -LiteralPath $source -Filter '*.v' -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $scratch
}
Copy-Item -LiteralPath (Join-Path $source 'frontend') -Destination $scratch -Recurse
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Replace-Source([string]$Name, [string]$Before, [string]$After) {
    $path = Join-Path $scratch $Name
    $code = [System.IO.File]::ReadAllText($path).Replace("`r`n", "`n")
    if (-not $code.Contains($Before)) {
        throw "The py2v source has changed: expected text missing from $Name. Copy: $scratch"
    }
    [System.IO.File]::WriteAllText($path, $code.Replace($Before, $After), $utf8)
}

# Fix build errors in the supplied source snapshot, without changing code generation.
Replace-Source 'transpiler.v' 'for module in t.star_imports {' 'for module_name in t.star_imports {'
Replace-Source 'transpiler.v' 't.registry.dotted_for_v_module(module)' 't.registry.dotted_for_v_module(module_name)'
Replace-Source 'transpiler.v' "result = module`n" "result = module_name`n"
Replace-Source 'transpiler.v' 't.call_signatures = signatures' 't.call_signatures = signatures.clone()'
Replace-Source 'transpiler.v' 'saved_scope_idents := t.scope_idents' 'saved_scope_idents := t.scope_idents.clone()'
Replace-Source 'transpiler.v' 't.scope_idents = saved_scope_idents' 't.scope_idents = saved_scope_idents.clone()'
Replace-Source 'transpiler.v' 'mut base_args := vargs' 'mut base_args := vargs.clone()'
Replace-Source 'transpiler.v' 'ptype := t.typename_from_annotation(arg.annotation)' "ptype := if ann := arg.annotation { t.typename_from_annotation(*ann) } else { '' }"
Replace-Source 'transpiler.v' "`t`tn++`n`t}`n}`n`n// module_scope_decl" "`t`tn++`n`t}`n`treturn ''`n}`n`n// module_scope_decl"
Replace-Source 'parser.v' 'returns:         fd.returns' 'returns:         if ret := fd.returns { ?Expr(*ret) } else { none }'
Replace-Source 'parser.v' 'kw_defaults << parse_optional_expr(item)' 'kw_defaults << if expr := parse_optional_expr(item) { ?Expr(*expr) } else { none }'
Replace-Source 'parser.v' 'keys << parse_optional_expr(item)' 'keys << if expr := parse_optional_expr(item) { ?Expr(*expr) } else { none }'
Replace-Source 'parser.v' 'pattern: &inner_pat' 'pattern: if pattern := inner_pat { ?&MatchPattern(&MatchPattern(pattern)) } else { none }'

$previousVexe = $env:VEXE
$previousBugReport = $env:V_C_ERROR_BUG_REPORT_DISABLED
try {
    $env:VEXE = $compilerPath
    $env:V_C_ERROR_BUG_REPORT_DISABLED = '1'
    $executable = Join-Path $scratch 'py2v.exe'
    $ErrorActionPreference = 'Continue'
    $buildOutput = @(& $compilerPath -cc gcc -gc none -no-retry-compilation -o $executable $scratch 2>&1 |
        ForEach-Object { $_.ToString() })
    $buildExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    [System.IO.File]::WriteAllLines((Join-Path $scratch 'build.txt'), [string[]]$buildOutput, $utf8)
    if ($buildExitCode -ne 0) {
        throw "Could not build py2v. See $scratch/build.txt. Use a V compiler with os.exec_opt and generic option reflection."
    }
    $inputs = @(Get-ChildItem -LiteralPath $source -Filter '*.v' -File | Sort-Object Name |
        ForEach-Object { [ordered]@{ file = $_.Name; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() } })
    $inputs += @(Get-ChildItem -LiteralPath (Join-Path $source 'frontend') -Filter '*.py' -File -Recurse |
        Sort-Object FullName | ForEach-Object {
            [ordered]@{
                file = $_.FullName.Substring($source.Length + 1).Replace('\', '/')
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        })
    $metadata = [ordered]@{
        compiler = ((& $compilerPath version) -join "`n")
        patches = 'Lunoir-V tools/py2v/prepare.ps1'
        inputs = $inputs
    }
    [System.IO.File]::WriteAllText((Join-Path $scratch 'preparation.json'), ($metadata | ConvertTo-Json -Depth 5) + "`n", $utf8)
    Write-Host "Prepared py2v in $scratch"
    Write-Output $executable
} finally {
    $ErrorActionPreference = 'Stop'
    $env:VEXE = $previousVexe
    $env:V_C_ERROR_BUG_REPORT_DISABLED = $previousBugReport
}
