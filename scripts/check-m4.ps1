# 校验 M4 owned 存储与工作台：Rust fmt/test/clippy/build、Dart 测试、owned test-support 与可选集成。
# 依赖本地桥接 DLL 与构建产物，不替代用户真实数据迁移或 Release 验收。

param(
    [string]$FlutterExecutable = 'D:\flutter_sdk\flutter\bin\flutter.bat',
    [string]$DartExecutable = 'D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.exe',
    [switch]$WindowsBuild
)
$ErrorActionPreference = 'Stop'
$m4Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$m4App = Join-Path $m4Root 'apps\desktop'
$m4Evidence = Join-Path $m4Root 'docs\evidence\m4\checks'
$m4Manifest = Join-Path $m4Root 'rust\Cargo.toml'
$m4Target = Join-Path $m4Root 'build\rust-m1-msvc'
$m4Results = [Collections.Generic.List[object]]::new()
$m4OldDll = $env:PARASELENE_M1_DLL
$m4OldRun = $env:PARASELENE_M4_RUN_ID
$m4TestTarget = Join-Path $m4Root 'build\rust-m4-test-msvc'
New-Item -ItemType Directory -Force -Path $m4Evidence | Out-Null
function Invoke-M4Check([string]$Name, [string]$Executable, [string[]]$Arguments, [string]$Directory) {
    $m4Exit = 1
    $m4Log = Join-Path $m4Evidence "m4-native-followup-$Name.txt"
    [IO.File]::WriteAllText($m4Log, '')
    Push-Location -LiteralPath $Directory
    try {
        & $Executable @Arguments 2>&1 | Tee-Object -FilePath $m4Log
        $m4Exit = $LASTEXITCODE
        if ($m4Exit -ne 0) { throw "$Name failed with exit $m4Exit" }
    } finally {
        $m4Results.Add([pscustomobject]@{ Check=$Name; Executable=$Executable; Arguments=$Arguments; ExitCode=$m4Exit })
        Pop-Location
    }
}
try {
    Invoke-M4Check 'rust-fmt' 'cargo' @('fmt','--manifest-path',$m4Manifest,'-p','paraselene-application','-p','paraselene-bridge','--check') $m4Root
    Invoke-M4Check 'rust-tests' 'cargo' @('+stable-x86_64-pc-windows-msvc','test','--manifest-path',$m4Manifest,'-p','paraselene-application','-p','paraselene-memory-core','-p','paraselene-novel-core','--features','paraselene-application/test-support','--target-dir',$m4Target,'--locked','--offline') $m4Root
    Invoke-M4Check 'rust-clippy' 'cargo' @('+stable-x86_64-pc-windows-msvc','clippy','--manifest-path',$m4Manifest,'-p','paraselene-application','-p','paraselene-bridge','--all-targets','--no-deps','--target-dir',$m4Target,'--locked','--offline','--','-D','warnings') $m4Root
    Invoke-M4Check 'rust-bridge-build' 'cargo' @('+stable-x86_64-pc-windows-msvc','build','--manifest-path',$m4Manifest,'-p','paraselene-bridge','--target-dir',$m4Target,'--locked','--offline') $m4Root
    $env:PARASELENE_M1_DLL = Join-Path $m4Target 'debug\paraselene_bridge.dll'
    Invoke-M4Check 'gen-l10n-freshness' $FlutterExecutable @('gen-l10n') $m4App
    Invoke-M4Check 'dart-fmt' $DartExecutable @('format','--output=none','--set-exit-if-changed','lib','test','integration_test') $m4App
    Invoke-M4Check 'flutter-analyze' $FlutterExecutable @('analyze','--fatal-infos') $m4App
    $m4Files = @(Get-ChildItem -LiteralPath (Join-Path $m4App 'test') -Recurse -Filter '*_test.dart' | Where-Object { $_.Name -ne 'm4_owned_repository_test.dart' } | ForEach-Object { $_.FullName })
    Invoke-M4Check 'dart-tests-production' $FlutterExecutable (@('test') + $m4Files) $m4App
    Invoke-M4Check 'rust-test-bridge-build' 'cargo' @('+stable-x86_64-pc-windows-msvc','build','--manifest-path',$m4Manifest,'-p','paraselene-bridge','--features','test-support','--target-dir',$m4TestTarget,'--locked','--offline') $m4Root
    $env:PARASELENE_M1_DLL = Join-Path $m4TestTarget 'debug\paraselene_bridge.dll'
    $env:PARASELENE_M4_RUN_ID = [guid]::NewGuid().ToString('N')
    Invoke-M4Check 'dart-owned-test-support' $FlutterExecutable @('test','test/m4_owned_repository_test.dart') $m4App
    if ($WindowsBuild) {
        Invoke-M4Check 'windows-release-build' $FlutterExecutable @('build','windows','--release') $m4App
        $env:PARASELENE_M1_DLL = $null
        # Sequential real-Windows files: one invocation per file avoids the
        # follow-up app failing to attach a debug connection after the first
        # session exits (observed as "log reader never started" on file 2+).
        Invoke-M4Check 'windows-integration-m1' $FlutterExecutable @('test','integration_test/m1_app_test.dart','-d','windows') $m4App
        Invoke-M4Check 'windows-integration-m2' $FlutterExecutable @('test','integration_test/m2_app_test.dart','-d','windows') $m4App
        $env:PARASELENE_M1_DLL = Join-Path $m4TestTarget 'debug\paraselene_bridge.dll'
        $env:PARASELENE_M4_RUN_ID = [guid]::NewGuid().ToString('N')
        Invoke-M4Check 'windows-integration-m4' $FlutterExecutable @('test','integration_test/m4_app_test.dart','-d','windows') $m4App
    }
} finally {
    $env:PARASELENE_M1_DLL = $m4OldDll
    $env:PARASELENE_M4_RUN_ID = $m4OldRun
    $m4Results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $m4Evidence 'm4-native-followup-commands.json') -Encoding utf8
}
