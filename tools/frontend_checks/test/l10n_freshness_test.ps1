# 使用真实 SDK 和合成临时应用验证 freshness 门禁；记录原应用哈希，不改产品输入或生成物。
# 只在工作区 build 创建样本，缺工具、负向未拒绝或任何意外变更均非零退出。
[CmdletBinding()]
param(
    [string]$DartExecutable = 'D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.exe',
    [string]$FlutterExecutable = 'D:\flutter_sdk\flutter\bin\flutter.bat',
    [string]$ReportDirectory
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$fixtureId = [guid]::NewGuid().ToString('N')
$fixtureProject = Join-Path $fixtureRoot "build\l10n-freshness-fixtures\$fixtureId\app"
$fixtureScript = Join-Path $fixtureRoot 'scripts\check-l10n-freshness.ps1'
$fixtureCases = [Collections.Generic.List[object]]::new()
$fixtureExit = 1
if (!$ReportDirectory) {
    $ReportDirectory = Join-Path $fixtureRoot "build\l10n-freshness-fixtures\$fixtureId\reports"
}
$ReportDirectory = [IO.Path]::GetFullPath($ReportDirectory)
New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null

function Get-OriginalHashes {
    $fixtureApp = Join-Path $fixtureRoot 'apps\desktop'
    $fixtureInputs = @((Join-Path $fixtureApp 'pubspec.yaml'), (Join-Path $fixtureApp 'l10n.yaml'))
    $fixtureInputs += @(Get-ChildItem -LiteralPath (Join-Path $fixtureApp 'lib\l10n') `
        -Recurse -File -Force | ForEach-Object FullName)
    @($fixtureInputs | Sort-Object | ForEach-Object {
        [ordered]@{
            Path = [IO.Path]::GetRelativePath($fixtureApp, $_).Replace('\', '/')
            Sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash
        }
    }) | ConvertTo-Json -Depth 4 -Compress
}

function Invoke-FreshnessFixture([string]$Name, [int]$ExpectedCode,
    [string]$Difference, [string]$FlutterOverride = $FlutterExecutable,
    [string]$DartOverride = $DartExecutable, [switch]$GeneratorMustFail) {
    $fixtureCaseReport = Join-Path $ReportDirectory $Name
    $fixtureArguments = @('-NoProfile', '-File', $fixtureScript,
        '-AppDirectory', $fixtureProject, '-DartExecutable', $DartOverride,
        '-FlutterExecutable', $FlutterOverride, '-ReportDirectory', $fixtureCaseReport)
    & pwsh @fixtureArguments *> (Join-Path $ReportDirectory "$Name.txt")
    $fixtureCode = $LASTEXITCODE
    $fixtureSummaryPath = Join-Path $fixtureCaseReport 'summary.json'
    $fixtureSummary = if (Test-Path -LiteralPath $fixtureSummaryPath -PathType Leaf) {
        Get-Content -LiteralPath $fixtureSummaryPath -Raw | ConvertFrom-Json
    } else { $null }
    $fixturePass = $fixtureCode -eq $ExpectedCode
    if ($Difference) {
        $fixturePass = $fixturePass -and $fixtureSummary -and @($fixtureSummary.$Difference).Count -gt 0
    }
    if ($fixtureSummary -and $fixtureSummary.PSObject.Properties['SourceUnchanged']) {
        $fixturePass = $fixturePass -and $fixtureSummary.SourceUnchanged
    }
    if ($GeneratorMustFail) {
        $fixturePass = $fixturePass -and $fixtureSummary -and
            $fixtureSummary.PSObject.Properties['GeneratorExitCode'] -and
            $fixtureSummary.GeneratorExitCode -ne 0
    }
    $fixtureCases.Add([pscustomobject]@{
        Case = $Name; ExpectedExitCode = $ExpectedCode; ActualExitCode = $fixtureCode
        Status = if ($fixturePass) { 'PASS' } else { 'FAIL' }
        RequiredDifference = $Difference; Report = $fixtureSummaryPath
    })
    Write-Output "$($fixtureCases[-1].Status): $Name (exit $fixtureCode, expected $ExpectedCode)"
}

$fixtureOriginalBefore = Get-OriginalHashes
$fixtureOriginalBefore | Set-Content -LiteralPath (Join-Path $ReportDirectory 'original-app-before.json') -Encoding utf8
try {
    $fixtureFlutter = Get-Command $FlutterExecutable -CommandType Application -ErrorAction Stop
    $fixtureSdk = Split-Path -Parent (Split-Path -Parent $fixtureFlutter.Source)
    $fixturePackages = Join-Path $fixtureSdk 'packages\flutter_tools\.dart_tool\package_config.json'
    $fixtureSnapshot = Join-Path $fixtureSdk 'bin\cache\flutter_tools.snapshot'
    $fixtureArbDirectory = Join-Path $fixtureProject 'lib\l10n'
    New-Item -ItemType Directory -Path $fixtureArbDirectory | Out-Null
    @'
name: l10n_freshness_fixture
environment:
  sdk: ^3.8.1
flutter:
  generate: true
'@ | Set-Content -LiteralPath (Join-Path $fixtureProject 'pubspec.yaml') -Encoding utf8
    Copy-Item -LiteralPath (Join-Path $fixtureRoot 'apps\desktop\l10n.yaml') -Destination $fixtureProject
    $fixtureEnglish = Join-Path $fixtureArbDirectory 'app_en.arb'
    @{
        '@@locale' = 'en'; greeting = 'Hello fixture'
        '@greeting' = @{ description = 'Synthetic freshness test greeting.' }
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $fixtureEnglish -Encoding utf8
    @{ '@@locale' = 'zh'; greeting = '合成问候' } | ConvertTo-Json | Set-Content `
        -LiteralPath (Join-Path $fixtureArbDirectory 'app_zh.arb') -Encoding utf8
    Push-Location -LiteralPath $fixtureProject
    try {
        & $DartExecutable "--packages=$fixturePackages" $fixtureSnapshot `
            --no-version-check --suppress-analytics gen-l10n --project-dir $fixtureProject `
            *> (Join-Path $ReportDirectory 'seed-gen-l10n.txt')
        if ($LASTEXITCODE -ne 0) { throw "Fixture seed generation failed with exit code $LASTEXITCODE." }
    } finally {
        Pop-Location
    }
    Invoke-FreshnessFixture 'fresh-output' 0
    $fixtureEnglishBytes = [IO.File]::ReadAllBytes($fixtureEnglish)
    $fixtureChangedEnglish = [IO.File]::ReadAllText($fixtureEnglish).Replace('Hello fixture', 'Updated fixture')
    [IO.File]::WriteAllText($fixtureEnglish, $fixtureChangedEnglish)
    Invoke-FreshnessFixture 'existing-message-changed' 1 'Changed'
    [IO.File]::WriteAllBytes($fixtureEnglish, $fixtureEnglishBytes)
    $fixtureGenerated = Join-Path $fixtureArbDirectory 'generated'
    $fixtureGeneratedEnglish = Join-Path $fixtureGenerated 'app_localizations_en.dart'
    $fixtureGeneratedBytes = [IO.File]::ReadAllBytes($fixtureGeneratedEnglish)
    [IO.File]::Delete($fixtureGeneratedEnglish)
    Invoke-FreshnessFixture 'generated-file-missing' 1 'Missing'
    [IO.File]::WriteAllBytes($fixtureGeneratedEnglish, $fixtureGeneratedBytes)
    $fixtureExtraDirectory = Join-Path $fixtureGenerated 'nested'
    New-Item -ItemType Directory -Path $fixtureExtraDirectory | Out-Null
    $fixtureExtra = Join-Path $fixtureExtraDirectory 'unexpected.bin'
    [IO.File]::WriteAllBytes($fixtureExtra, [byte[]]@(0, 1, 2))
    Invoke-FreshnessFixture 'extra-nondart-file' 1 'Extra'
    [IO.File]::Delete($fixtureExtra)
    [IO.File]::AppendAllText($fixtureGeneratedEnglish, "`n")
    Invoke-FreshnessFixture 'raw-byte-only-change' 1 'Changed'
    [IO.File]::WriteAllBytes($fixtureGeneratedEnglish, $fixtureGeneratedBytes)
    [IO.File]::WriteAllText($fixtureEnglish, '{invalid-json')
    Invoke-FreshnessFixture 'generator-failure' 1 -GeneratorMustFail
    [IO.File]::WriteAllBytes($fixtureEnglish, $fixtureEnglishBytes)
    $fixtureConfig = Join-Path $fixtureProject 'l10n.yaml'
    $fixtureConfigBytes = [IO.File]::ReadAllBytes($fixtureConfig)
    $fixtureUnsafe = [IO.File]::ReadAllText($fixtureConfig).Replace(
        'output-dir: lib/l10n/generated', 'output-dir: ../escaped-freshness')
    [IO.File]::WriteAllText($fixtureConfig, $fixtureUnsafe)
    Invoke-FreshnessFixture 'escaping-output-rejected' 1
    if (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $fixtureProject) 'escaped-freshness')) {
        throw 'Unsafe configuration escaped the isolated project.'
    }
    [IO.File]::WriteAllBytes($fixtureConfig, $fixtureConfigBytes)
    Invoke-FreshnessFixture 'missing-flutter-tool' 3 '' (Join-Path $fixtureProject 'missing\flutter.bat')
    Invoke-FreshnessFixture 'missing-dart-tool' 3 '' $FlutterExecutable (Join-Path $fixtureProject 'missing\dart.exe')
    $fixtureExit = if (@($fixtureCases | Where-Object Status -eq 'FAIL').Count) { 1 } else { 0 }
} catch {
    Write-Output "FAIL: freshness fixture execution; $($_.Exception.Message)"
} finally {
    $fixtureOriginalAfter = Get-OriginalHashes
    $fixtureOriginalAfter | Set-Content -LiteralPath (Join-Path $ReportDirectory 'original-app-after.json') -Encoding utf8
    $fixtureOriginalUnchanged = $fixtureOriginalBefore -ceq $fixtureOriginalAfter
    if (!$fixtureOriginalUnchanged) { $fixtureExit = 1 }
    [ordered]@{
        Status = if ($fixtureExit -eq 0) { 'PASS' } else { 'FAIL' }
        ExitCode = $fixtureExit; OriginalApplicationUnchanged = $fixtureOriginalUnchanged
        FixtureProject = $fixtureProject; Cases = $fixtureCases
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ReportDirectory 'summary.json') -Encoding utf8
}
exit $fixtureExit
