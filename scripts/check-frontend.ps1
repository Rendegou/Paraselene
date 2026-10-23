# 自有 Flutter/Dart 前端统一检查入口。默认静态门禁，不访问作者库或模型。
# 可选检查与物理系统验收分别记录；退出 0 只表示所选自动检查通过。
[CmdletBinding()]
param(
    [switch]$Test,
    [switch]$Golden,
    [switch]$WindowsBuild,
    [switch]$RestoreTools,
    [string]$DartExecutable = 'D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.exe',
    [string]$FlutterExecutable = 'D:\flutter_sdk\flutter\bin\flutter.bat',
    [string]$ProductionDll,
    [string]$TestSupportDll,
    [string]$ReportDirectory
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$frontRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$frontApp = Join-Path $frontRoot 'apps\desktop'
$frontTools = Join-Path $frontRoot 'tools\frontend_checks'
$frontText = Join-Path $frontRoot 'packages\text_contract'
$frontRun = [guid]::NewGuid().ToString('N')
if (!$ReportDirectory) {
    $ReportDirectory = Join-Path $frontRoot "build\frontend-checks\$frontRun"
}
$ReportDirectory = [IO.Path]::GetFullPath($ReportDirectory)
if (!$ProductionDll) {
    $ProductionDll = Join-Path $frontRoot 'build\rust-m1-msvc\debug\paraselene_bridge.dll'
}
if (!$TestSupportDll) {
    $TestSupportDll = Join-Path $frontRoot 'build\rust-m4-test-msvc\debug\paraselene_bridge.dll'
}
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
$frontResults = [Collections.Generic.List[object]]::new()
$frontOldDll = $env:PARASELENE_M1_DLL
$frontOldRun = $env:PARASELENE_M4_RUN_ID
$frontOldTemp = $env:TEMP
$frontOldTmp = $env:TMP
$frontTemp = Join-Path $ReportDirectory 'temporary'
New-Item -ItemType Directory -Force -Path $frontTemp | Out-Null
$env:TEMP = $frontTemp
$env:TMP = $frontTemp

function Add-FrontResult([string]$Name, [string]$Status, [bool]$Selected,
    [Nullable[int]]$Code, [string]$Detail) {
    $frontResults.Add([pscustomobject]@{
        Check = $Name; Status = $Status; Selected = $Selected
        ExitCode = $Code; Detail = $Detail
    })
}

function Invoke-FrontCheck([string]$Name, [string]$Executable,
    [string[]]$Arguments, [string]$Directory, [Nullable[int]]$UnavailableExitCode = $null) {
    $frontLog = Join-Path $ReportDirectory "$Name.txt"
    if (!(Get-Command $Executable -ErrorAction SilentlyContinue)) {
        Add-FrontResult $Name 'NOT_RUN' $true $null 'Executable unavailable'
        return
    }
    Push-Location -LiteralPath $Directory
    try {
        & $Executable @Arguments 2>&1 | Tee-Object -FilePath $frontLog
        $frontCode = $LASTEXITCODE
        $frontStatus = if ($frontCode -eq 0) { 'PASS' }
            elseif ($null -ne $UnavailableExitCode -and $frontCode -eq $UnavailableExitCode) { 'NOT_RUN' }
            else { 'FAIL' }
        Add-FrontResult $Name $frontStatus $true $frontCode $frontLog
    } catch {
        $_.Exception.Message | Set-Content -LiteralPath $frontLog -Encoding utf8
        Add-FrontResult $Name 'FAIL' $true 1 $frontLog
    } finally {
        Pop-Location
    }
}

function Invoke-FrontFlutter([string]$Name, [string[]]$Arguments) {
    Invoke-FrontCheck $Name $FlutterExecutable `
        (@('--no-version-check', '--suppress-analytics') + $Arguments) $frontApp
}

function Invoke-FrontDartTests([string]$Name, [string]$Directory) {
    $frontConfig = Join-Path $Directory '.dart_tool\package_config.json'
    if (!(Test-Path -LiteralPath $frontConfig -PathType Leaf)) {
        Add-FrontResult $Name 'NOT_RUN' $true $null 'Package configuration unavailable'
        return
    }
    $frontPackages = Get-Content -LiteralPath $frontConfig -Raw | ConvertFrom-Json
    $frontTest = $frontPackages.packages | Where-Object { $_.name -eq 'test' } | Select-Object -First 1
    if (!$frontTest) {
        Add-FrontResult $Name 'NOT_RUN' $true $null 'Cached test runner unavailable'
        return
    }
    $frontBaseUri = [uri]::new([IO.Path]::GetFullPath($frontConfig))
    $frontTestUri = [uri]::new($frontBaseUri, [string]$frontTest.rootUri)
    $frontRunner = Join-Path $frontTestUri.LocalPath 'bin\test.dart'
    Invoke-FrontCheck $Name $DartExecutable `
        @("--packages=$frontConfig", $frontRunner, '--reporter', 'expanded') $Directory
}

function Invoke-FrontStatic {
    Invoke-FrontCheck 'documentation' 'pwsh' `
        @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'check-docs.ps1'),
            '-ReportPath', (Join-Path $ReportDirectory 'documentation.json')) $frontRoot
    Invoke-FrontCheck 'documentation-negative-tests' 'pwsh' `
        @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'test-docs.ps1')) $frontRoot
    if ($RestoreTools) {
        Invoke-FrontCheck 'restore-tools-offline' $DartExecutable `
            @('pub', 'get', '--offline') $frontTools
    }
    $frontConfig = Join-Path $frontTools '.dart_tool\package_config.json'
    if (Test-Path -LiteralPath $frontConfig -PathType Leaf) {
        Invoke-FrontCheck 'ast-structure-theme' $DartExecutable `
            @('--packages=.dart_tool/package_config.json', 'bin/check_frontend.dart',
                '--root', $frontRoot, '--output', (Join-Path $ReportDirectory 'metrics.json')) $frontTools
        Invoke-FrontDartTests 'gate-negative-tests' $frontTools
        Invoke-FrontCheck 'gate-analyze' $DartExecutable `
            @('analyze', '--fatal-infos') $frontTools
    } else {
        foreach ($frontName in @('ast-structure-theme', 'gate-negative-tests', 'gate-analyze')) {
            Add-FrontResult $frontName 'NOT_RUN' $true $null 'Run -RestoreTools using cached dependencies'
        }
    }
    if (Get-Command $DartExecutable -ErrorAction SilentlyContinue) {
        Invoke-FrontCheck 'arb-contract' 'pwsh' `
            @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'check-m2-l10n.ps1'),
                '-DartExecutable', $DartExecutable) $frontRoot
    } else {
        Add-FrontResult 'arb-contract' 'NOT_RUN' $true $null 'Dart executable unavailable'
    }
    Invoke-FrontCheck 'l10n-freshness' 'pwsh' `
        @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'check-l10n-freshness.ps1'),
            '-DartExecutable', $DartExecutable, '-FlutterExecutable', $FlutterExecutable,
            '-ReportDirectory', (Join-Path $ReportDirectory 'l10n-freshness')) $frontRoot -UnavailableExitCode 3
    Invoke-FrontCheck 'app-format' $DartExecutable `
        @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'integration_test', 'bin') $frontApp
    Invoke-FrontCheck 'text-format' $DartExecutable `
        @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test') $frontText
    Invoke-FrontCheck 'gate-format' $DartExecutable `
        @('format', '--output=none', '--set-exit-if-changed', 'lib', 'bin', 'test') $frontTools
    Invoke-FrontFlutter 'app-analyze' @('analyze', '--no-pub', '--fatal-infos')
    Invoke-FrontCheck 'text-analyze' $DartExecutable @('analyze', '--fatal-infos') $frontText
}

function Invoke-FrontTests {
    if (!$Test) {
        foreach ($frontName in @('regression-production', 'regression-owned', 'text-tests')) {
            Add-FrontResult $frontName 'SKIPPED' $false $null 'Select -Test'
        }
        return
    }
    Invoke-FrontDartTests 'text-tests' $frontText
    if (Test-Path -LiteralPath $ProductionDll -PathType Leaf) {
        $env:PARASELENE_M1_DLL = $ProductionDll
        $frontFiles = @(Get-ChildItem -LiteralPath (Join-Path $frontApp 'test') `
            -Recurse -File -Filter '*_test.dart' | Where-Object {
                $_.Name -notin @('m4_owned_repository_test.dart', 'm2_golden_test.dart')
            } | ForEach-Object { $_.FullName })
        Invoke-FrontFlutter 'regression-production' `
            (@('test', '--no-pub', '--exclude-tags', 'golden', '--reporter', 'expanded') + $frontFiles)
    } else {
        Add-FrontResult 'regression-production' 'NOT_RUN' $true $null 'Production bridge DLL unavailable'
    }
    if (Test-Path -LiteralPath $TestSupportDll -PathType Leaf) {
        $env:PARASELENE_M1_DLL = $TestSupportDll
        $env:PARASELENE_M4_RUN_ID = $frontRun
        Invoke-FrontFlutter 'regression-owned' `
            @('test', '--no-pub', 'test/m4_owned_repository_test.dart', '--reporter', 'expanded')
    } else {
        Add-FrontResult 'regression-owned' 'NOT_RUN' $true $null 'Dedicated test-support DLL unavailable'
    }
}

function Invoke-FrontOptional {
    if ($Golden) {
        $env:PARASELENE_M1_DLL = $ProductionDll
        Invoke-FrontFlutter 'golden-comparison' `
            @('test', '--no-pub', 'test/m2_golden_test.dart', '--tags', 'golden', '--reporter', 'expanded')
    } else {
        Add-FrontResult 'golden-comparison' 'SKIPPED' $false $null 'Select -Golden; never updates baselines'
    }
    if ($WindowsBuild) {
        Invoke-FrontFlutter 'windows-release-build' @('build', 'windows', '--release', '--no-pub')
    } else {
        Add-FrontResult 'windows-release-build' 'SKIPPED' $false $null 'Select -WindowsBuild'
    }
    foreach ($frontName in @('physical-ime', 'physical-dpi-multimonitor',
        'screen-reader', 'clean-machine-installation')) {
        Add-FrontResult $frontName 'NOT_RUN' $false $null 'Requires separate real-system evidence'
    }
}

try {
    Invoke-FrontStatic
    Invoke-FrontTests
    Invoke-FrontOptional
} catch {
    Add-FrontResult 'gate-execution' 'FAIL' $true 1 $_.Exception.Message
} finally {
    $env:PARASELENE_M1_DLL = $frontOldDll
    $env:PARASELENE_M4_RUN_ID = $frontOldRun
    $env:TEMP = $frontOldTemp
    $env:TMP = $frontOldTmp
    $frontFailed = @($frontResults | Where-Object { $_.Selected -and $_.Status -eq 'FAIL' })
    $frontMissing = @($frontResults | Where-Object { $_.Selected -and $_.Status -eq 'NOT_RUN' })
    $frontSelectedStatus = if ($frontFailed.Count) { 'FAIL' } elseif ($frontMissing.Count) { 'NOT_RUN' } else { 'PASS' }
    $frontReport = [pscustomobject]@{
        RunId = $frontRun; SelectedChecksStatus = $frontSelectedStatus
        OverallStatus = if ($frontFailed.Count) { 'FAIL' } else { 'PARTIAL' }
        Coverage = 'Selected automated checks only; optional and physical checks remain separately listed.'
        Results = $frontResults
    }
    $frontReport | ConvertTo-Json -Depth 8 | Set-Content `
        -LiteralPath (Join-Path $ReportDirectory 'summary.json') -Encoding utf8
    $frontResults | Format-Table Check, Status, ExitCode -AutoSize
    Write-Output "Selected checks: $frontSelectedStatus. Report: $ReportDirectory"
}
if ($frontFailed.Count) { exit 1 }
if ($frontMissing.Count) { exit 3 }
exit 0
