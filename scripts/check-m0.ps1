param(
    [string]$DartExecutable = 'D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.exe',
    [ValidateSet('All','Vectors')][string]$Check = 'All',
    [string]$GoldenFile,
    [string]$EvidenceDirectory
)
$ErrorActionPreference = 'Stop'
$migrationRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$packageRoot = Join-Path $migrationRoot 'packages\text_contract'
$oracleManifest = Join-Path $migrationRoot 'rust\contract-oracle\Cargo.toml'
$rustTarget = Join-Path $migrationRoot 'build\rust-m0'
$evidenceRoot = if ($EvidenceDirectory) { [IO.Path]::GetFullPath($EvidenceDirectory) } else { Join-Path $migrationRoot 'docs\evidence\m0' }
if (!$GoldenFile) { $GoldenFile = Join-Path $packageRoot 'test\fixtures\rust_fingerprints.json' }
New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
$results = [Collections.Generic.List[object]]::new()
$originalPath = $env:PATH

function Invoke-ModuleCheck {
    param([string]$Name, [string]$Executable, [string[]]$ArgumentList, [string]$Directory)
    Push-Location -LiteralPath $Directory
    $checkExit = 1
    try {
        & $Executable @ArgumentList 2>&1 | Tee-Object -FilePath (Join-Path $evidenceRoot "$Name.txt")
        $checkExit = $LASTEXITCODE
        if ($checkExit -ne 0) { throw "$Name failed with exit $checkExit" }
    } finally {
        $results.Add([pscustomobject]@{ Check=$Name; Executable=$Executable; Arguments=$ArgumentList; Directory=$Directory; ExitCode=$checkExit })
        Pop-Location
    }
}

try {
    $env:PATH = 'C:\tools\paraselene-build\mingw64\bin;' + $env:PATH
    if ($Check -eq 'All') {
    Invoke-ModuleCheck 'dart-format' $DartExecutable @('format','--output=none','--set-exit-if-changed','lib','test','bin') $packageRoot
    Invoke-ModuleCheck 'dart-analyze' $DartExecutable @('analyze','--fatal-infos') $packageRoot
    Invoke-ModuleCheck 'dart-test' $DartExecutable @('test','--reporter','expanded') $packageRoot
    Invoke-ModuleCheck 'dart-probe' $DartExecutable @('run','bin/synthetic_probe.dart') $packageRoot
    Invoke-ModuleCheck 'rust-format' 'cargo' @('fmt','--manifest-path',$oracleManifest,'--check') $migrationRoot
    Invoke-ModuleCheck 'rust-test' 'cargo' @('test','--manifest-path',$oracleManifest,'--target-dir',$rustTarget,'--locked','--offline') $migrationRoot
    Invoke-ModuleCheck 'rust-clippy' 'cargo' @('clippy','--manifest-path',$oracleManifest,'--target-dir',$rustTarget,'--locked','--offline','--all-targets','--','-D','warnings') $migrationRoot
    Invoke-ModuleCheck 'rust-build' 'cargo' @('build','--manifest-path',$oracleManifest,'--target-dir',$rustTarget,'--locked','--offline') $migrationRoot
    }
    $fixture = Join-Path $packageRoot 'test\fixtures\test_vectors.json'
    $oracleBinary = Join-Path $rustTarget 'debug\paraselene-contract-oracle.exe'
    $vectorOutput = Join-Path $evidenceRoot 'rust-vector-results.json'
    # Clear the current result before attempting the process; a failure cannot reuse old success.
    '' | Set-Content -LiteralPath $vectorOutput -Encoding utf8
    '' | Set-Content -LiteralPath (Join-Path $evidenceRoot 'rust-vector-golden.txt') -Encoding utf8
    $actualJson = @(Invoke-ModuleCheck 'rust-vector-verify' $oracleBinary @($fixture) $migrationRoot)
    $goldenExit = 1
    $actual = @()
    try {
        $expected = Get-Content -Raw -LiteralPath $GoldenFile | ConvertFrom-Json
        $actual = $actualJson -join "`n" | ConvertFrom-Json
        $actualJson | Set-Content -LiteralPath $vectorOutput -Encoding utf8
        if (($expected | ConvertTo-Json -Depth 5 -Compress) -cne ($actual | ConvertTo-Json -Depth 5 -Compress)) {
            throw 'Rust hashes/coordinates differ from committed golden vectors'
        }
        $goldenExit = 0
        'Matched actual BLAKE3 hashes and coordinates.' | Set-Content -LiteralPath (Join-Path $evidenceRoot 'rust-vector-golden.txt') -Encoding utf8
    } catch {
        $_.Exception.Message | Set-Content -LiteralPath (Join-Path $evidenceRoot 'rust-vector-golden.txt') -Encoding utf8
        throw
    } finally {
        $results.Add([pscustomobject]@{ Check='rust-vector-golden'; Executable=$oracleBinary; Arguments=@($fixture); Directory=$migrationRoot; ExitCode=$goldenExit; Vectors=@($actual).Count })
    }
} finally {
    $env:PATH = $originalPath
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidenceRoot 'commands.json') -Encoding utf8
}
Write-Output "M0_$($Check.ToUpperInvariant())_CHECKS_PASS"
