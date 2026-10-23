param([string]$PyodidePackagePath)

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $PyodidePackagePath) {
    $PyodidePackagePath = Join-Path $repo 'spikes/pyodide/node_modules/pyodide'
}
if (-not (Test-Path -LiteralPath $PyodidePackagePath -PathType Container)) {
    throw 'Pyodide is missing. Run npm ci --ignore-scripts in spikes/pyodide first.'
}
$source = (Resolve-Path -LiteralPath $PyodidePackagePath).Path
$names = @('pyodide.mjs', 'pyodide.asm.mjs', 'pyodide.asm.wasm', 'pyodide-lock.json', 'python_stdlib.zip')
foreach ($name in $names) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)) {
        throw "Pyodide resource missing: $name"
    }
}
foreach ($relative in @('public/learning/pyodide', 'dist/learning/pyodide')) {
    $target = [System.IO.Path]::GetFullPath((Join-Path $repo $relative))
    if (-not $target.StartsWith($repo + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Learning assets must remain inside the work copy.'
    }
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    foreach ($name in $names) {
        Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $target $name) -Force
    }
}
Write-Output 'Pinned Pyodide resources prepared for the learning window.'
