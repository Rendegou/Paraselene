# 校验 M2 工作台：ARB 对齐、gen-l10n、format/analyze、行为测试与真实字体 golden。
# 默认跳过 Windows 构建与集成；golden 受字体和平台影响，不代表真机验收通过。

param(
    [string]$FlutterExecutable='D:\flutter_sdk\flutter\bin\flutter.bat',
    [string]$DartExecutable='D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.exe',
    [switch]$WindowsBuild
)
$ErrorActionPreference='Stop'
$m2Root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$m2App=Join-Path $m2Root 'apps\desktop'
$m2Evidence=Join-Path $m2Root 'docs\evidence\m2\checks'
$m2Results=[Collections.Generic.List[object]]::new()
$m2OldDll=$env:PARASELENE_M1_DLL
New-Item -ItemType Directory -Force -Path $m2Evidence | Out-Null
function Invoke-M2Check([string]$Name,[string]$Executable,[string[]]$Arguments,[string]$Directory) {
    $m2Code=1
    $m2Log=Join-Path $m2Evidence "$Name.txt"
    [IO.File]::WriteAllText($m2Log,'')
    Push-Location -LiteralPath $Directory
    try {
        & $Executable @Arguments 2>&1 | Tee-Object -FilePath $m2Log
        $m2Code=$LASTEXITCODE
        if ($m2Code -ne 0) { throw "$Name failed with exit $m2Code" }
    } finally {
        $m2Results.Add([pscustomobject]@{Check=$Name;Executable=$Executable;Arguments=$Arguments;ExitCode=$m2Code})
        Pop-Location
    }
}
try {
    Invoke-M2Check 'arb-parity' 'pwsh' @('-NoProfile','-File',(Join-Path $PSScriptRoot 'check-m2-l10n.ps1')) $m2Root
    Invoke-M2Check 'gen-l10n' $FlutterExecutable @('gen-l10n') $m2App
    Invoke-M2Check 'dart-format' $DartExecutable @('format','--output=none','--set-exit-if-changed','lib','test','integration_test','bin') $m2App
    Invoke-M2Check 'flutter-analyze' $FlutterExecutable @('analyze','--fatal-infos') $m2App
    $env:PARASELENE_M1_DLL=Join-Path $m2Root 'build\rust-m1-msvc\debug\paraselene_bridge.dll'
    Invoke-M2Check 'behavior-and-layout' $FlutterExecutable @('test','--exclude-tags','golden') $m2App
    Invoke-M2Check 'real-font-goldens' $FlutterExecutable @('test','test/m2_golden_test.dart','--tags','golden') $m2App
    if ($WindowsBuild) {
        $env:PARASELENE_M1_DLL=$null
        Invoke-M2Check 'windows-workbench' $FlutterExecutable @('test','integration_test/m2_app_test.dart','-d','windows') $m2App
        Invoke-M2Check 'm1-diagnostic-regression' $FlutterExecutable @('test','integration_test/m1_app_test.dart','-d','windows') $m2App
        Invoke-M2Check 'windows-release' $FlutterExecutable @('build','windows','--release') $m2App
    }
} finally {
    $env:PARASELENE_M1_DLL=$m2OldDll
    $m2Results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $m2Evidence 'commands.json') -Encoding utf8
}
