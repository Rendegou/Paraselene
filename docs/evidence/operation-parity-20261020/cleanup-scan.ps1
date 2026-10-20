# R16 清理扫描：只读统计、分发副本 manifest、路径核验。不删除任何内容。
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath('D:\MyAgent\paraselene-flutter')
$evidence = Join-Path $root 'docs\evidence\operation-parity-20261020'
$envInfo = [ordered]@{
    timestamp = (Get-Date).ToString('o')
    root = $root
    head = (& git -C $root rev-parse HEAD)
    statusCount = @(& git -C $root status --porcelain).Count
    flutter = (& 'D:\flutter_sdk\flutter\bin\flutter.bat' --version | Select-Object -First 1)
    os = [System.Environment]::OSVersion.VersionString
    ps = $PSVersionTable.PSVersion.ToString()
}

function Get-TreeStats([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return [ordered]@{ exists = $false } }
    $files = Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue
    return [ordered]@{
        exists = $true
        files = @($files).Count
        bytes = [long](($files | Measure-Object Length -Sum).Sum)
        top = (Get-Item -LiteralPath $path).FullName
    }
}

$targets = [ordered]@{
    C01 = 'build\rust-m1-msvc'
    C02 = 'build\rust-m4-test-msvc'
    C03 = 'rust\target'
    C04 = 'apps\desktop\build'
    C05 = 'build\learning-native'
    C06 = 'apps\desktop\.dart_tool'
    C07 = 'packages\text_contract\.dart_tool'
    C08 = 'build\vendor'
    C09 = 'spikes\editor_comparison'
    C10 = 'spikes\codemirror_baseline'
    C11 = 'apps\desktop\test\failures'
    C12 = 'apps\desktop\test\goldens'
    C13 = 'docs\evidence'
    C14 = 'build\m4-owned-synthetic-v1'
}
$stats = [ordered]@{}
foreach ($k in $targets.Keys) {
    $stats[$k] = Get-TreeStats (Join-Path $root $targets[$k])
    if ($stats[$k].exists) {
        $stats[$k].gcd = (& git -C $root ls-files -- $targets[$k]).Count
        & git -C $root check-ignore -q -- $targets[$k]
        $stats[$k].ignored = ($LASTEXITCODE -eq 0)
    }
}

$dist = Get-ChildItem -LiteralPath (Join-Path $root 'build') -Directory -Filter 'm1-distribution-*' | Sort-Object Name
$distData = [ordered]@{}
$pathSets = [ordered]@{}
foreach ($d in $dist) {
    $files = Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force
    $manifest = foreach ($f in $files) {
        [ordered]@{
            relative = $f.FullName.Substring($d.FullName.Length + 1)
            length = $f.Length
            sha256 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
        }
    }
    $distData[$d.Name] = [ordered]@{
        created = $d.CreationTime.ToString('o')
        bytes = [long](($files | Measure-Object Length -Sum).Sum)
        files = @($files).Count
        manifest = @($manifest)
    }
    $pathSets[$d.Name] = (($manifest.relative | Sort-Object) -join "`n")
}

$pathSetGroups = $pathSets.GetEnumerator() | Group-Object Value | ForEach-Object { @{ count = $_.Count; dirs = @($_.Group.Key) } } | ForEach-Object { [ordered]@{ count = $_.count; dirs = $_.dirs } }

[ordered]@{ env = $envInfo; targets = $stats; distributions = $distData; pathSetGroups = $pathSetGroups } |
    ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath (Join-Path $evidence 'cleanup-scan.json') -Encoding utf8

$envInfo | ConvertTo-Json | Write-Output
"targets:"
foreach ($k in $stats.Keys) {
    $s = $stats[$k]
    if ($s.exists) { "{0}: files={1} bytes={2} gitTracked={3} ignored={4}" -f $k, $s.files, $s.bytes, $s.gcd, $s.ignored }
    else { "${k}: missing" }
}
"distributions:"
foreach ($n in $distData.Keys) { "{0}: files={1} bytes={2} created={3}" -f $n, $distData[$n].files, $distData[$n].bytes, $distData[$n].created }
"pathSetGroups:"
foreach ($g in $pathSetGroups) { "count={0} dirs={1}" -f $g.count, ($g.dirs -join ',') }
