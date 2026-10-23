param(
    [Parameter(Mandatory = $true)][string]$PyodidePackagePath
)

& (Join-Path $PSScriptRoot 'prepare-webview2-probe.ps1') -PyodidePackagePath $PyodidePackagePath
if (-not $?) { throw 'Probe asset preparation failed.' }

# This override applies only to the probe build; the product CSP is unchanged.
$env:TAURI_CONFIG = (@{ app = @{ security = @{ csp = @{
    'worker-src' = "'self' blob:"
    'connect-src' = 'ipc: http://ipc.localhost http://probe-assets.localhost'
    'script-src' = "'self' http://probe-assets.localhost 'wasm-unsafe-eval'"
} } } } | ConvertTo-Json -Compress -Depth 6)
$env:PATH = 'C:\tools\paraselene-build\mingw64\bin;' + $env:PATH
cargo run -p paraselene --example sandbox_probe --target-dir 'D:\MyAgent\.cargo-target' --offline --quiet
exit $LASTEXITCODE
