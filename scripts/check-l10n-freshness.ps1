# 在工作区隔离项目中调用已缓存的官方 gen-l10n，按路径全集和原始字节检查生成物。
# 只复制本地化输入，不恢复依赖、不调用网络、不改真实应用配置或生成物。
[CmdletBinding()]
param(
    [string]$AppDirectory = (Join-Path $PSScriptRoot '..\apps\desktop'),
    [string]$DartExecutable = 'D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.exe',
    [string]$FlutterExecutable = 'D:\flutter_sdk\flutter\bin\flutter.bat',
    [string]$ReportDirectory
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$freshRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$freshId = [guid]::NewGuid().ToString('N')
$freshRun = Join-Path $freshRoot "build\l10n-freshness\$freshId"
$freshProject = Join-Path $freshRun 'project'
$freshCode = 1
$freshReportReady = $false
$freshReport = [ordered]@{ Status = 'FAIL'; ExitCode = 1; RunId = $freshId }

function Get-FreshFiles([string]$Directory) {
    $freshFiles = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    if (Test-Path -LiteralPath $Directory -PathType Container) {
        foreach ($freshFile in Get-ChildItem -LiteralPath $Directory -File -Recurse -Force) {
            $freshRelative = [IO.Path]::GetRelativePath($Directory, $freshFile.FullName).Replace('\', '/')
            $freshFiles.Add($freshRelative, $freshFile.FullName)
        }
    }
    return ,$freshFiles
}

function Get-FreshSourceHashes([string]$Directory, [string]$ArbPath, [string]$OutputPath,
    [string]$HeaderPath) {
    $freshPaths = @((Join-Path $Directory 'pubspec.yaml'), (Join-Path $Directory 'l10n.yaml'))
    $freshPaths += @(Get-ChildItem -LiteralPath (Join-Path $Directory $ArbPath) `
        -File -Recurse -Filter '*.arb' | ForEach-Object FullName)
    if ($HeaderPath) { $freshPaths += Join-Path $Directory $HeaderPath }
    $freshPaths += @((Get-FreshFiles (Join-Path $Directory $OutputPath)).Values)
    @($freshPaths | Sort-Object -Unique | ForEach-Object {
        [ordered]@{
            Path = [IO.Path]::GetRelativePath($Directory, $_).Replace('\', '/')
            Sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash
        }
    }) | ConvertTo-Json -Depth 4 -Compress
}

try {
    $AppDirectory = [IO.Path]::GetFullPath($AppDirectory)
    if (!$ReportDirectory) { $ReportDirectory = $freshRun }
    $ReportDirectory = [IO.Path]::GetFullPath($ReportDirectory)
    if ($ReportDirectory -eq $AppDirectory -or
        $ReportDirectory.StartsWith($AppDirectory + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ReportDirectory must be outside the checked application.'
    }
    New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
    $freshReportReady = $true
    $freshDart = Get-Command $DartExecutable -CommandType Application -ErrorAction SilentlyContinue
    $freshFlutter = Get-Command $FlutterExecutable -CommandType Application -ErrorAction SilentlyContinue
    if (!$freshDart -or !$freshFlutter) {
        $freshCode = 3
        throw 'Dart or Flutter executable unavailable.'
    }
    $freshSdk = Split-Path -Parent (Split-Path -Parent $freshFlutter.Source)
    $freshPackages = Join-Path $freshSdk 'packages\flutter_tools\.dart_tool\package_config.json'
    $freshSnapshot = Join-Path $freshSdk 'bin\cache\flutter_tools.snapshot'
    if (!(Test-Path -LiteralPath $freshPackages -PathType Leaf) -or
        !(Test-Path -LiteralPath $freshSnapshot -PathType Leaf)) {
        $freshCode = 3
        throw 'Cached official Flutter tool snapshot or package configuration unavailable.'
    }
    New-Item -ItemType Directory -Path $freshProject | Out-Null
    foreach ($freshInput in @('pubspec.yaml', 'l10n.yaml')) {
        Copy-Item -LiteralPath (Join-Path $AppDirectory $freshInput) -Destination $freshProject
    }
    # 与 Flutter 使用同一已缓存 YAML/path 包解释文件选项；所有路径须留在隔离项目内。
    $freshReader = Join-Path $freshRun 'read_l10n_config.dart'
    @'
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

void main(List<String> arguments) {
  final yaml = loadYaml(File(arguments.single).readAsStringSync());
  if (yaml is! YamlMap || yaml['synthetic-package'] != false) {
    throw const FormatException('Expected synthetic-package: false in l10n.yaml.');
  }
  String path(String key, String fallback) {
    final value = yaml[key] ?? fallback;
    if (value is! String || value.isEmpty) {
      throw FormatException('Expected a nonempty path for $key.');
    }
    final parsed = Uri.parse(value).path;
    if (p.isAbsolute(parsed) || p.split(parsed).contains('..') || parsed.isEmpty) {
      throw FormatException('Expected a project-contained relative path for $key.');
    }
    return p.normalize(parsed);
  }
  final arb = path('arb-dir', 'lib/l10n');
  final output = path('output-dir', arb);
  if (p.equals(arb, output) || p.isWithin(output, arb)) {
    throw const FormatException('The generated output must have a separate directory.');
  }
  path('template-arb-file', 'app_en.arb');
  path('output-localization-file', 'app_localizations.dart');
  if (yaml['untranslated-messages-file'] != null) {
    path('untranslated-messages-file', '');
  }
  print(jsonEncode({
    'arb': arb,
    'output': output,
    'header': yaml['header-file'] == null ? null : p.join(arb, path('header-file', '')),
  }));
}
'@ | Set-Content -LiteralPath $freshReader -Encoding utf8
    $freshConfigLog = Join-Path $ReportDirectory 'config-errors.txt'
    $freshConfigJson = & $freshDart.Source "--packages=$freshPackages" $freshReader `
        (Join-Path $freshProject 'l10n.yaml') 2> $freshConfigLog
    if ($LASTEXITCODE -ne 0) { throw "Invalid isolated localization configuration. Log: $freshConfigLog" }
    $freshConfig = $freshConfigJson | ConvertFrom-Json
    $freshBefore = Get-FreshSourceHashes $AppDirectory $freshConfig.arb $freshConfig.output $freshConfig.header
    $freshBefore | Set-Content -LiteralPath (Join-Path $ReportDirectory 'source-before.json') -Encoding utf8
    foreach ($freshArb in Get-ChildItem -LiteralPath (Join-Path $AppDirectory $freshConfig.arb) `
        -File -Recurse -Filter '*.arb') {
        $freshDestination = Join-Path $freshProject ([IO.Path]::GetRelativePath($AppDirectory, $freshArb.FullName))
        New-Item -ItemType Directory -Path (Split-Path -Parent $freshDestination) -Force | Out-Null
        Copy-Item -LiteralPath $freshArb.FullName -Destination $freshDestination
    }
    if ($freshConfig.header) {
        $freshHeader = Join-Path $freshProject $freshConfig.header
        New-Item -ItemType Directory -Path (Split-Path -Parent $freshHeader) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $AppDirectory $freshConfig.header) -Destination $freshHeader
    }
    $freshLog = Join-Path $ReportDirectory 'gen-l10n.txt'
    Push-Location -LiteralPath $freshProject
    try {
        & $freshDart.Source "--packages=$freshPackages" $freshSnapshot `
            --no-version-check --suppress-analytics gen-l10n --project-dir $freshProject *> $freshLog
        $freshGeneratorCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    $freshAfter = Get-FreshSourceHashes $AppDirectory $freshConfig.arb $freshConfig.output $freshConfig.header
    $freshAfter | Set-Content -LiteralPath (Join-Path $ReportDirectory 'source-after.json') -Encoding utf8
    $freshReport.SourceUnchanged = $freshBefore -ceq $freshAfter
    $freshReport.GeneratorExitCode = $freshGeneratorCode
    $freshReport.TemporaryProject = $freshProject
    $freshReport.GeneratorLog = $freshLog
    if (!$freshReport.SourceUnchanged) { throw 'Application localization inputs or generated files changed during the check.' }
    if ($freshGeneratorCode -ne 0) {
        $freshCode = $freshGeneratorCode
        throw "Official gen-l10n failed with exit code $freshGeneratorCode. Log: $freshLog"
    }
    $freshExpected = Get-FreshFiles (Join-Path $freshProject $freshConfig.output)
    $freshActual = Get-FreshFiles (Join-Path $AppDirectory $freshConfig.output)
    if (!$freshExpected.Count) { throw 'Official gen-l10n produced no output files.' }
    $freshMissing = @($freshExpected.Keys | Where-Object { !$freshActual.ContainsKey($_) } | Sort-Object)
    $freshExtra = @($freshActual.Keys | Where-Object { !$freshExpected.ContainsKey($_) } | Sort-Object)
    $freshChanged = @($freshExpected.Keys | Where-Object {
        $freshActual.ContainsKey($_) -and
        ![Collections.StructuralComparisons]::StructuralEqualityComparer.Equals(
            [IO.File]::ReadAllBytes($freshExpected[$_]), [IO.File]::ReadAllBytes($freshActual[$_]))
    } | Sort-Object)
    $freshReport.ExpectedFileCount = $freshExpected.Count
    $freshReport.ActualFileCount = $freshActual.Count
    $freshReport.Missing = $freshMissing
    $freshReport.Extra = $freshExtra
    $freshReport.Changed = $freshChanged
    if ($freshMissing.Count -or $freshExtra.Count -or $freshChanged.Count) {
        throw "Localization output differs: missing=$($freshMissing.Count), extra=$($freshExtra.Count), changed=$($freshChanged.Count)."
    }
    $freshCode = 0
    $freshReport.Status = 'PASS'
    Write-Output "PASS: l10n-freshness; $($freshExpected.Count) generated files match byte-for-byte."
} catch {
    $freshReport.Status = if ($freshCode -eq 3) { 'NOT_RUN' } else { 'FAIL' }
    $freshReport.Detail = $_.Exception.Message
    Write-Output "$($freshReport.Status): l10n-freshness; $($_.Exception.Message)"
} finally {
    $freshReport.ExitCode = $freshCode
    if ($freshReportReady) {
        $freshReport | ConvertTo-Json -Depth 6 | Set-Content `
            -LiteralPath (Join-Path $ReportDirectory 'summary.json') -Encoding utf8
    }
}
exit $freshCode
