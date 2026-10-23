param(
    [Parameter(Mandatory = $true)][string]$PyodidePackagePath
)

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$target = [System.IO.Path]::GetFullPath((Join-Path $repo 'dist'))
if (-not $target.StartsWith($repo + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Probe output must stay inside the work copy.'
}
$source = (Resolve-Path -LiteralPath $PyodidePackagePath).Path
$probe = Join-Path $repo 'spikes/webview2-probe'
New-Item -ItemType Directory -Force -Path $target, (Join-Path $target 'pyodide') | Out-Null
Copy-Item -LiteralPath (Join-Path $probe 'probe.html') -Destination (Join-Path $target 'probe.html')
Copy-Item -LiteralPath (Join-Path $probe 'probe-result.html') -Destination (Join-Path $target 'probe-result.html')
Copy-Item -LiteralPath (Join-Path $probe 'sandbox-probe.js') -Destination (Join-Path $target 'sandbox-probe.js')
Copy-Item -LiteralPath (Join-Path $probe 'sandbox-probe-worker.js') -Destination (Join-Path $target 'sandbox-probe-worker.js')
foreach ($name in @('pyodide.mjs', 'pyodide.asm.mjs', 'pyodide.asm.wasm', 'pyodide-lock.json', 'python_stdlib.zip')) {
    Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $target 'pyodide' $name)
}
Write-Output "Probe assets ready in $target"
