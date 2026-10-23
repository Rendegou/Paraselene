# 文档门禁的独立合成反例；仅在仓库 build 下创建自有 fixture，保留结果供检查。
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'check-docs.ps1')
$docTestRoot = Join-Path (Join-Path $PSScriptRoot '..\build\documentation-tests') ([guid]::NewGuid().ToString('N'))
$docTestResults = [Collections.Generic.List[object]]::new()

function New-DocumentationFixture([string]$Name, [string]$Omit = '') {
    $docFixture = Join-Path $docTestRoot $Name
    foreach ($docRelative in @(Get-DocumentationScope)) {
        if ($docRelative -eq $Omit) { continue }
        $docFixtureFile = Join-Path $docFixture $docRelative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $docFixtureFile) | Out-Null
        Set-Content -LiteralPath $docFixtureFile -Value '# Synthetic documentation fixture' -Encoding utf8
    }
    $docFixtureHistory = Join-Path $docFixture 'docs/history'
    $docFixtureSnapshot = Join-Path $docFixtureHistory 'snapshots/original.md'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $docFixtureSnapshot) | Out-Null
    Set-Content -LiteralPath $docFixtureSnapshot -Value 'original synthetic bytes' -Encoding utf8
    @{ schemaVersion = 1; snapshots = @(@{
        path = 'snapshots/original.md'
        sha256 = (Get-FileHash -LiteralPath $docFixtureSnapshot -Algorithm SHA256).Hash
        bytes = (Get-Item -LiteralPath $docFixtureSnapshot).Length
    }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $docFixtureHistory 'snapshot-manifest.json') -Encoding utf8
    return $docFixture
}

function Assert-DocumentationCase([string]$Name, [string]$Fixture,
    [string]$Status, [string]$Code = '') {
    $docActual = Invoke-DocumentationCheck $Fixture
    if ($docActual.Status -ne $Status -or
        ($Code -and $Code -notin @($docActual.Findings | ForEach-Object Code))) {
        throw "$Name failed: $($docActual | ConvertTo-Json -Depth 6 -Compress)"
    }
    $docTestResults.Add([pscustomobject]@{ Name = $Name; Status = 'PASS' })
}

$docFixture = New-DocumentationFixture 'valid'
Set-Content -LiteralPath (Join-Path $docFixture 'README.md') -Value '[local](docs/product-scope.md#heading) [remote](https://example.com/docs)' -Encoding utf8
Assert-DocumentationCase 'valid local path, fragment and external URL' $docFixture 'PASS'

$docFixture = New-DocumentationFixture 'missing-document' 'docs/product-scope.md'
Assert-DocumentationCase 'missing canonical document fails' $docFixture 'FAIL' 'missing-document'

$docFixture = New-DocumentationFixture 'dangling-link'
Set-Content -LiteralPath (Join-Path $docFixture 'README.md') -Value '[missing](docs/not-present.md)' -Encoding utf8
Assert-DocumentationCase 'dangling local link fails' $docFixture 'FAIL' 'missing-link-target'

$docFixture = New-DocumentationFixture 'escaping-link'
Set-Content -LiteralPath (Join-Path $docFixture 'README.md') -Value '[outside](../outside.md)' -Encoding utf8
Assert-DocumentationCase 'external planning-directory dependency fails' $docFixture 'FAIL' 'outside-repository-link'
$docCliOutput = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'check-docs.ps1') -Root $docFixture 2>&1
if ($LASTEXITCODE -ne 1) { throw "Invalid live documentation must exit 1: $docCliOutput" }
$docTestResults.Add([pscustomobject]@{ Name = 'CLI returns nonzero for invalid live documentation'; Status = 'PASS' })

$docFixture = New-DocumentationFixture 'absolute-link'
Set-Content -LiteralPath (Join-Path $docFixture 'README.md') -Value '[machine path](<C:/not-read/private.md>)' -Encoding utf8
Assert-DocumentationCase 'machine-specific local link fails without reading target' $docFixture 'FAIL' 'absolute-link'

$docFixture = New-DocumentationFixture 'snapshot-change'
Set-Content -LiteralPath (Join-Path $docFixture 'docs/history/snapshots/original.md') -Value 'changed bytes' -Encoding utf8
Assert-DocumentationCase 'rewritten historical bytes fail' $docFixture 'FAIL' 'snapshot-mismatch'

$docFixture = New-DocumentationFixture 'invalid-manifest'
Set-Content -LiteralPath (Join-Path $docFixture 'docs/history/snapshot-manifest.json') -Value '{not-json' -Encoding utf8
Assert-DocumentationCase 'malformed historical manifest fails' $docFixture 'FAIL' 'invalid-snapshot-manifest'

$docFixture = New-DocumentationFixture 'fenced-example'
$docFencedExample = @'
```markdown
[example only](../outside.md)
```
[real](docs/product-scope.md)
'@
Set-Content -LiteralPath (Join-Path $docFixture 'README.md') -Value $docFencedExample -Encoding utf8
Assert-DocumentationCase 'fenced illustrative links do not become live dependencies' $docFixture 'PASS'

[pscustomobject]@{
    Status = 'PASS'; Tests = $docTestResults.Count
    Results = @($docTestResults.ToArray())
} | ConvertTo-Json -Depth 5
