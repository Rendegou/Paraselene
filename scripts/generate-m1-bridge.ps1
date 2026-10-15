param([string]$Generator = 'D:\MyAgent\toolchain-downloads\frb-2.11.1\bin\flutter_rust_bridge_codegen.exe')
$ErrorActionPreference = 'Stop'
$m1Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$m1OldPath = $env:PATH
$m1OldToolchain = $env:RUSTUP_TOOLCHAIN
Push-Location -LiteralPath $m1Root
try {
    if ((& $Generator --version) -notmatch '^flutter_rust_bridge_codegen 2\.11\.1$') { throw 'FRB generator 2.11.1 required' }
    $env:PATH = 'D:\flutter_sdk\flutter\bin;D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin;' + $env:PATH
    $env:RUSTUP_TOOLCHAIN = 'stable-x86_64-pc-windows-msvc'
    & $Generator generate --rust-input crate::api --rust-root rust/bridge --dart-output apps/desktop/lib/native/generated --dart-root apps/desktop --no-add-mod-to-lib
    if ($LASTEXITCODE -ne 0) { throw "FRB generation failed with exit $LASTEXITCODE" }
} finally {
    $env:PATH = $m1OldPath
    $env:RUSTUP_TOOLCHAIN = $m1OldToolchain
    Pop-Location
}
