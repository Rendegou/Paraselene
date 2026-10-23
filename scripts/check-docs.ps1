# 检查当前文档入口、本地链接边界及历史快照；不访问网络、作者数据或 SDK。
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot '..'),
    [string]$ReportPath
)
$ErrorActionPreference = 'Stop'

function Get-DocumentationScope {
    @(
        'AGENTS.md', 'README.md', 'DESIGN.md', 'apps/desktop/README.md',
        'packages/text_contract/README.md', 'tools/frontend_checks/README.md',
        'docs/product-scope.md', 'docs/progress.md',
        'docs/engineering/architecture-contracts.md',
        'docs/engineering/frontend-standards.md',
        'docs/engineering/agent-workflow.md', 'docs/engineering/task-template.md',
        'docs/tasks/FE-001-menu-contract.md', 'docs/history/README.md',
        '.superpowers/sdd/progress.md'
    )
}

function Test-DocumentationContainment([string]$Directory, [string]$Path) {
    $docDirectory = [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
    $docPath = [IO.Path]::GetFullPath($Path)
    $docPath.StartsWith($docDirectory + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)
}

function Add-DocumentationFinding($Findings, [string]$Path, [int]$Line,
    [string]$Code, [string]$Detail) {
    $Findings.Add([pscustomobject]@{
        Path = $Path; Line = $Line; Code = $Code; Detail = $Detail
    })
}

function Test-DocumentationLinks([string]$RepositoryRoot, [string]$Relative,
    $Findings) {
    $docFile = Join-Path $RepositoryRoot $Relative
    if (!(Test-Path -LiteralPath $docFile -PathType Leaf)) {
        Add-DocumentationFinding $Findings $Relative 1 'missing-document' 'Required document unavailable'
        return 0
    }
    $docLines = [IO.File]::ReadAllLines($docFile)
    $docFence = $null
    $docLinks = 0
    for ($docIndex = 0; $docIndex -lt $docLines.Length; $docIndex++) {
        $docLine = $docLines[$docIndex]
        if ($docLine -match '^\s*(`{3,}|~{3,})') {
            $docMarker = $Matches[1][0]
            if ($null -eq $docFence) { $docFence = $docMarker }
            elseif ($docFence -eq $docMarker) { $docFence = $null }
            continue
        }
        if ($null -ne $docFence) { continue }
        foreach ($docMatch in [regex]::Matches($docLine, '\[[^\]\r\n]*\]\((<[^>]+>|[^\s)]+)(?:\s+"[^"\r\n]*")?\)')) {
            $docTarget = $docMatch.Groups[1].Value.Trim('<', '>')
            if ($docTarget -match '^(https?://|mailto:|#)') { continue }
            $docLinks++
            $docTarget = [uri]::UnescapeDataString(($docTarget -split '#', 2)[0])
            if ([IO.Path]::IsPathRooted($docTarget) -or $docTarget -match '^[A-Za-z][A-Za-z0-9+.-]*:') {
                Add-DocumentationFinding $Findings $Relative ($docIndex + 1) 'absolute-link' $docTarget
                continue
            }
            $docDestination = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $docFile) $docTarget))
            if (!(Test-DocumentationContainment $RepositoryRoot $docDestination)) {
                Add-DocumentationFinding $Findings $Relative ($docIndex + 1) 'outside-repository-link' $docTarget
            } elseif (!(Test-Path -LiteralPath $docDestination)) {
                Add-DocumentationFinding $Findings $Relative ($docIndex + 1) 'missing-link-target' $docTarget
            }
        }
    }
    return $docLinks
}

function Test-DocumentationSnapshots([string]$RepositoryRoot, $Findings) {
    $docManifestRelative = 'docs/history/snapshot-manifest.json'
    $docManifestPath = Join-Path $RepositoryRoot $docManifestRelative
    try {
        $docManifest = Get-Content -LiteralPath $docManifestPath -Raw | ConvertFrom-Json
        if ($docManifest.schemaVersion -ne 1 -or @($docManifest.snapshots).Count -eq 0) {
            throw 'Unsupported or empty historical snapshot manifest'
        }
    } catch {
        Add-DocumentationFinding $Findings $docManifestRelative 1 'invalid-snapshot-manifest' 'Manifest missing, malformed or unsupported'
        return 0
    }
    $docSnapshotRoot = Join-Path $RepositoryRoot 'docs/history/snapshots'
    $docChecked = 0
    foreach ($docSnapshot in $docManifest.snapshots) {
        $docSnapshotPath = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $docManifestPath) $docSnapshot.path))
        if (!(Test-DocumentationContainment $docSnapshotRoot $docSnapshotPath) -or
            [IO.Path]::GetExtension($docSnapshotPath) -ne '.md') {
            Add-DocumentationFinding $Findings $docManifestRelative 1 'snapshot-path' 'Snapshot must stay in the historical Markdown snapshot directory'
            continue
        }
        if (!(Test-Path -LiteralPath $docSnapshotPath -PathType Leaf)) {
            Add-DocumentationFinding $Findings $docSnapshot.path 1 'missing-snapshot' 'Historical snapshot unavailable'
            continue
        }
        $docChecked++
        $docHash = (Get-FileHash -LiteralPath $docSnapshotPath -Algorithm SHA256).Hash
        $docBytes = (Get-Item -LiteralPath $docSnapshotPath).Length
        if ($docHash -ne $docSnapshot.sha256 -or $docBytes -ne $docSnapshot.bytes) {
            Add-DocumentationFinding $Findings $docSnapshot.path 1 'snapshot-mismatch' 'Historical bytes differ from the archived manifest'
        }
    }
    return $docChecked
}

function Invoke-DocumentationCheck([string]$RepositoryRoot) {
    $docRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    $docFindings = [Collections.Generic.List[object]]::new()
    $docScope = @(Get-DocumentationScope)
    $docLinks = 0
    foreach ($docRelative in $docScope) {
        $docLinks += Test-DocumentationLinks $docRoot $docRelative $docFindings
    }
    $docSnapshots = Test-DocumentationSnapshots $docRoot $docFindings
    [pscustomobject]@{
        Status = if ($docFindings.Count) { 'FAIL' } else { 'PASS' }
        Documents = $docScope.Count; LocalLinks = $docLinks
        HistoricalSnapshots = $docSnapshots; Findings = @($docFindings.ToArray())
        Coverage = 'Explicit current documentation entries, local link paths and archived bytes only; no semantic, heading-anchor, external URL or application verification'
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $docResult = Invoke-DocumentationCheck $Root
        $docJson = $docResult | ConvertTo-Json -Depth 6
        if ($ReportPath) {
            $docReport = if ([IO.Path]::IsPathRooted($ReportPath)) {
                [IO.Path]::GetFullPath($ReportPath)
            } else {
                [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath($Root)) $ReportPath))
            }
            if (!(Test-DocumentationContainment $Root $docReport) -or [IO.Path]::GetExtension($docReport) -ne '.json') {
                throw 'Report must be a JSON file inside the repository'
            }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $docReport) | Out-Null
            Set-Content -LiteralPath $docReport -Value $docJson -Encoding utf8
        }
        Write-Output $docJson
        if ($docResult.Status -ne 'PASS') { exit 1 }
    } catch {
        Write-Error $_ -ErrorAction Continue
        exit 1
    }
    exit 0
}
