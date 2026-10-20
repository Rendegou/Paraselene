# 校验 M1 Rust-owned 合同与 Dart FFI：Rust fmt/test/clippy/build、Dart format/analyze 与真实 DLL 测试。
# 只有传入 -WindowsBuild 才跑 Windows 构建与集成测试，默认不证明打包或安装行为通过。

param(
    [string]$FlutterExecutable = 'D:\flutter_sdk\flutter\bin\flutter.bat',
    [string]$DartExecutable = 'D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.exe',
    [switch]$WindowsBuild
)
$ErrorActionPreference = 'Stop'
$m1Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$m1App = Join-Path $m1Root 'apps\desktop'
$m1Evidence = Join-Path $m1Root 'docs\evidence\m1\checks'
$m1Manifest = Join-Path $m1Root 'rust\Cargo.toml'
$m1Target = Join-Path $m1Root 'build\rust-m1-msvc'
$m1Results = [Collections.Generic.List[object]]::new()
$m1OldDll = $env:PARASELENE_M1_DLL
New-Item -ItemType Directory -Force -Path $m1Evidence | Out-Null
function Invoke-M1Check([string]$Name, [string]$Executable, [string[]]$Arguments, [string]$Directory) {
    $m1Exit = 1
    $m1Log = Join-Path $m1Evidence "$Name.txt"
    # Successful silent commands must not leave an earlier failure transcript.
    [IO.File]::WriteAllText($m1Log, '')
    Push-Location -LiteralPath $Directory
    try {
        & $Executable @Arguments 2>&1 | Tee-Object -FilePath $m1Log
        $m1Exit = $LASTEXITCODE
        if ($m1Exit -ne 0) { throw "$Name failed with exit $m1Exit" }
    } finally {
        $m1Results.Add([pscustomobject]@{ Check=$Name; Executable=$Executable; Arguments=$Arguments; ExitCode=$m1Exit })
        Pop-Location
    }
}
try {
    Invoke-M1Check 'rust-owned-format' 'cargo' @('fmt','--manifest-path',$m1Manifest,'-p','paraselene-application','-p','paraselene-bridge','--check') $m1Root
    Invoke-M1Check 'rust-contract-tests' 'cargo' @('+stable-x86_64-pc-windows-msvc','test','--manifest-path',$m1Manifest,'-p','paraselene-application','-p','paraselene-memory-core','-p','paraselene-novel-core','--target-dir',$m1Target,'--locked','--offline') $m1Root
    Invoke-M1Check 'rust-owned-clippy' 'cargo' @('+stable-x86_64-pc-windows-msvc','clippy','--manifest-path',$m1Manifest,'-p','paraselene-application','-p','paraselene-bridge','--all-targets','--no-deps','--target-dir',$m1Target,'--locked','--offline','--','-D','warnings') $m1Root
    Invoke-M1Check 'rust-debug-build' 'cargo' @('+stable-x86_64-pc-windows-msvc','build','--manifest-path',$m1Manifest,'-p','paraselene-bridge','--target-dir',$m1Target,'--locked','--offline') $m1Root
    $env:PARASELENE_M1_DLL = Join-Path $m1Target 'debug\paraselene_bridge.dll'
    Invoke-M1Check 'dart-owned-format' $DartExecutable @('format','--output=none','--set-exit-if-changed','lib/main.dart','lib/native/runtime.dart','lib/probe','bin','test','integration_test') $m1App
    Invoke-M1Check 'flutter-analyze' $FlutterExecutable @('analyze','--fatal-infos') $m1App
    Invoke-M1Check 'real-ffi-test' $FlutterExecutable @('test','test/m1_real_ffi_test.dart') $m1App
    Invoke-M1Check 'real-dll-cli' $DartExecutable @('run',(Join-Path $m1App 'bin\m1_probe.dart')) $m1Root
    if ($WindowsBuild) {
        Invoke-M1Check 'windows-release-build' $FlutterExecutable @('build','windows','--release') $m1App
        # Integration exercises the installed bundle DLL; never the developer override.
        $env:PARASELENE_M1_DLL = $null
        Invoke-M1Check 'windows-integration' $FlutterExecutable @('test','integration_test/m1_app_test.dart','-d','windows') $m1App
    }
} finally {
    $env:PARASELENE_M1_DLL = $m1OldDll
    $m1Results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $m1Evidence 'commands.json') -Encoding utf8
}
