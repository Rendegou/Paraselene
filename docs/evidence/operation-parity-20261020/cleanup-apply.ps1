# R16 清理执行脚本：先 -DryRun 输出台账，再 -Execute 逐项删除；任何路径越界/受保护即停。
# 只处理白名单 C01–C07、C10 的 dist/browser-profile、旧 m1-distribution 副本；不触碰 C05/C08/C09/C11–C13。
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
if (-not $DryRun -and -not $Execute) { throw 'Specify -DryRun or -Execute' }
$root = [System.IO.Path]::GetFullPath('D:\MyAgent\paraselene-flutter')
$build = Join-Path $root 'build'
$archiveRoot = Join-Path $build 'release-archive'
$archiveName = 'm1-20261020-1445'
$archive = Join-Path $archiveRoot $archiveName
$keepBundle = 'm1-distribution-393029de294444c5b2c35c2c20979c2f'
$evidence = Join-Path $root 'docs\evidence\operation-parity-20261020'
$log = [System.Collections.Generic.List[object]]::new()

function Assert-Inside([string]$path, [string]$allowedRoot) {
    $full = [System.IO.Path]::GetFullPath($path)
    $rootFull = [System.IO.Path]::GetFullPath($allowedRoot)
    if ($full -eq $rootFull) { throw "Refusing to delete root itself: $full" }
    if (-not $full.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes allowed root: $full" }
    return $full
}

function Get-Stats([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return [ordered]@{ existed = $false; files = 0; bytes = [long]0 } }
    $items = Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue
    return [ordered]@{
        existed = $true
        files = @($items).Count
        bytes = [long](($items | Measure-Object Length -Sum).Sum)
    }
}

# 0) 保留交付：把最新 PASS 包移入 build/release-archive，并复制其验证证据。
if (-not (Test-Path -LiteralPath $archive)) {
    $bundle = Join-Path $build $keepBundle
    if (-not (Test-Path -LiteralPath $bundle)) { throw "Missing verified bundle: $bundle" }
    if ($DryRun) {
        "DRYRUN move $bundle -> $archive"
    } else {
        New-Item -ItemType Directory -Force -Path $archive | Out-Null
        Move-Item -LiteralPath $bundle -Destination (Join-Path $archive $keepBundle)
        foreach ($name in 'copied-bundle-status.json', 'copied-bundle-report.json', 'copied-bundle-manifest.json', 'missing-bundle-dll-report.json', 'copied-bundle-transcript.txt') {
            $source = Join-Path $root "docs\evidence\m1\$name"
            if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $archive }
        }
        @"
# M1 官方发布包归档（R16）
- 归档时间：$(Get-Date -Format o)
- 来源：build\$keepBundle（verify-m1-bundle.ps1 于 2026-10-20T14:45:47+08:00 验证 PASS）
- 内容：paraselene_flutter.exe + paraselene_bridge.dll + 运行所需 DLL/资源，共 65 个文件
- 证据：本目录 copied-bundle-status.json / copied-bundle-report.json / copied-bundle-manifest.json / copied-bundle-transcript.txt
- 完整性：SHA256SUMS.txt（相对路径）
- 说明：这是清理时唯一被实际验证 PASS 的最新独立包；旧 m1-distribution-* 副本均被本包取代并已删除。
"@ | Set-Content -LiteralPath (Join-Path $archive 'README.md') -Encoding utf8
        $files = Get-ChildItem -LiteralPath $archive -Recurse -File -Force
        $files | ForEach-Object {
            $rel = [System.IO.Path]::GetRelativePath($archive, $_.FullName)
            '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $rel
        } | Set-Content -LiteralPath (Join-Path $archive 'SHA256SUMS.txt') -Encoding utf8
    }
    $log.Add([ordered]@{ action = 'archive-latest-pass'; target = $archive; status = if ($DryRun) { 'DRYRUN' } else { 'done' } })
} else {
    "Archive already exists: $archive"
}

# 1) 白名单删除目标。
$targets = @(
    'build\rust-m1-msvc',
    'build\rust-m4-test-msvc',
    'rust\target',
    'apps\desktop\build',
    'apps\desktop\.dart_tool',
    'packages\text_contract\.dart_tool',
    'spikes\codemirror_baseline\dist',
    'spikes\codemirror_baseline\browser-profile'
)
$oldDistributions = Get-ChildItem -LiteralPath $build -Directory -Filter 'm1-distribution-*' | Where-Object { $_.Name -ne $keepBundle } | Sort-Object CreationTime

foreach ($rel in $targets) {
    $full = Assert-Inside (Join-Path $root $rel) $root
    $stats = Get-Stats $full
    if (-not $stats.existed) { "SKIP (missing): $rel"; continue }
    $record = [ordered]@{ action = 'delete'; target = $rel; files = $stats.files; bytes = $stats.bytes; status = 'DRYRUN' }
    if ($DryRun) {
        "DRYRUN delete $rel files=$($stats.files) bytes=$($stats.bytes)"
    } else {
        Remove-Item -LiteralPath $full -Recurse -Force
        if (Test-Path -LiteralPath $full) { throw "Delete failed: $full" }
        $record.status = 'deleted'
        $log.Add($record)
        "DELETED $rel files=$($stats.files) bytes=$($stats.bytes)"
        continue
    }
    $log.Add($record)
}

foreach ($dir in $oldDistributions) {
    $full = Assert-Inside $dir.FullName $root
    if (-not $full.StartsWith($build + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Distribution outside build: $full" }
    $stats = Get-Stats $full
    $record = [ordered]@{ action = 'delete-old-distribution'; target = $dir.Name; files = $stats.files; bytes = $stats.bytes; status = 'DRYRUN' }
    if ($DryRun) {
        "DRYRUN delete old distribution $($dir.Name) files=$($stats.files) bytes=$($stats.bytes)"
    } else {
        Remove-Item -LiteralPath $full -Recurse -Force
        if (Test-Path -LiteralPath $full) { throw "Delete failed: $full" }
        $record.status = 'deleted'
        $log.Add($record)
        "DELETED old distribution $($dir.Name) files=$($stats.files) bytes=$($stats.bytes)"
        continue
    }
    $log.Add($record)
}

$records = @($log | Where-Object { $_.action -ne 'archive-latest-pass' })
$totalBytes = [long](($records | ForEach-Object { $_.bytes } | Measure-Object -Sum).Sum)
$totalFiles = [int](($records | ForEach-Object { $_.files } | Measure-Object -Sum).Sum)
"TOTAL files=$totalFiles bytes=$totalBytes"
$log | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence ("cleanup-apply-{0}.json" -f ($(if ($DryRun) { 'dryrun' } else { 'execute' })))) -Encoding utf8
if ($Execute) { "Cleanup applied. Rebuild required before any release gate." }
