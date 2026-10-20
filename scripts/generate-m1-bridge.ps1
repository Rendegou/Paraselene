# 调用固定版本 FRB 生成器重建 Dart/Rust 桥接代码，并修正 Dart UTF-8 解码的 BOM 处理。
# 生成物需另行审查，脚本不证明生成代码语义正确，也不代表 Release 构建通过。

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
    # The generator's Windows polishing commands use powershell.exe internally.
    # Disable those hooks: all formatting/dependency work runs via pwsh separately.
    & $Generator generate --rust-input crate::api --rust-root rust/bridge --dart-output apps/desktop/lib/native/generated --dart-root apps/desktop --no-add-mod-to-lib --no-dart-format --no-dart-fix --no-rust-format --no-deps-check
    if ($LASTEXITCODE -ne 0) { throw "FRB generation failed with exit $LASTEXITCODE" }
    # Dart's UTF-8 decoder consumes an initial BOM; author text treats it as data.
    # Keep this deterministic fix in generation rather than hand-editing output.
    $m1Dart = Join-Path $m1Root 'apps\desktop\lib\native\generated\frb_generated.dart'
    $m1Text = [IO.File]::ReadAllText($m1Dart)
    $m1Needle = 'return utf8.decoder.convert(inner);'
    if ([regex]::Matches($m1Text, [regex]::Escape($m1Needle)).Count -ne 1) { throw 'Unexpected FRB string decoder; review BOM preservation' }
    $m1Replacement = @'
// Preserve leading U+FEFF, which Dart's UTF-8 decoder otherwise consumes.
    final bom = inner.length >= 3 && inner[0] == 0xef && inner[1] == 0xbb && inner[2] == 0xbf;
    return (bom ? '\uFEFF' : '') + utf8.decoder.convert(inner);
'@
    [IO.File]::WriteAllText($m1Dart, $m1Text.Replace($m1Needle, $m1Replacement))
} finally {
    $env:PATH = $m1OldPath
    $env:RUSTUP_TOOLCHAIN = $m1OldToolchain
    Pop-Location
}
