function Resolve-VCompiler([string]$Command) {
    $path = (Get-Command -Name $Command -CommandType Application -ErrorAction Stop).Source
    # Scoop exposes v through an executable shim; VEXE must name the real compiler.
    $shim = [System.IO.Path]::ChangeExtension($path, '.shim')
    if (Test-Path -LiteralPath $shim) {
        $metadata = [System.IO.File]::ReadAllText($shim)
        $match = [regex]::Match($metadata, '(?m)^path\s*=\s*"([^"]+)"')
        if ($match.Success) { $path = $match.Groups[1].Value }
    }
    if (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $path) 'vlib/builtin'))) {
        throw 'Pass the real V compiler executable next to vlib with -Compiler (not a launcher shim).'
    }
    return $path
}
