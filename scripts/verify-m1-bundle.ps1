param([string]$BundleDirectory, [string]$EvidenceDirectory)
$ErrorActionPreference = 'Stop'
$m1Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (!$BundleDirectory) { $BundleDirectory = Join-Path $m1Root 'apps\desktop\build\windows\x64\runner\Release' }
$m1Build = Join-Path $m1Root 'build'
$m1Copy = Join-Path $m1Build ('m1-distribution-' + [Guid]::NewGuid().ToString('N'))
if (![IO.Path]::GetFullPath($m1Copy).StartsWith($m1Build + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid bundle destination' }
$m1Evidence = if ($EvidenceDirectory) { [IO.Path]::GetFullPath($EvidenceDirectory) } else { Join-Path $m1Root 'docs\evidence\m1' }
New-Item -ItemType Directory -Force -Path $m1Evidence | Out-Null
Copy-Item -LiteralPath $BundleDirectory -Destination $m1Copy -Recurse
$m1Exe = Join-Path $m1Copy 'paraselene_flutter.exe'
$m1Dll = Join-Path $m1Copy 'paraselene_bridge.dll'
$m1Report = Join-Path $m1Evidence 'copied-bundle-report.json'
$m1FailReport = Join-Path $m1Evidence 'missing-bundle-dll-report.json'
$m1OldPath = $env:PATH
$m1OldDll = $env:PARASELENE_M1_DLL
$m1Status = [ordered]@{ Status='FAIL'; CopiedBundle=$m1Copy; ProbeExitCode=$null; MissingDllExitCode=$null; SdkRemovedFromPath=$true }
function Invoke-BundleProbe([string]$Report) {
    '' | Set-Content -LiteralPath $Report -Encoding utf8
    $m1Process = Start-Process -FilePath $m1Exe -ArgumentList @('--m1-probe',"--report=$Report") -WorkingDirectory (Split-Path $m1Root) -WindowStyle Hidden -PassThru
    if (!$m1Process.WaitForExit(60000)) {
        $m1Process.Kill()
        throw 'Copied bundle probe exceeded 60 seconds'
    }
    return $m1Process.ExitCode
}
try {
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
    # A deliberately invalid development override must not affect bundled app loading.
    $env:PARASELENE_M1_DLL = 'D:\nonexistent-m1-developer-override.dll'
    $m1Status.ProbeExitCode = Invoke-BundleProbe $m1Report
    $m1Actual = Get-Content -LiteralPath $m1Report -Raw | ConvertFrom-Json
    if ($m1Status.ProbeExitCode -ne 0 -or $m1Actual.status -ne 'PASS' -or !$m1Actual.syntheticOnly -or $m1Actual.cloudEnabled -or $m1Actual.schemaVersion -ne 12 -or $m1Actual.checks.Count -ne 11) { throw 'Copied bundle contract failed' }
    Move-Item -LiteralPath $m1Dll -Destination ($m1Dll + '.disabled')
    try {
        $m1Status.MissingDllExitCode = Invoke-BundleProbe $m1FailReport
        $m1Failure = Get-Content -LiteralPath $m1FailReport -Raw | ConvertFrom-Json
        if ($m1Status.MissingDllExitCode -ne 1 -or $m1Failure.status -ne 'FAIL') { throw 'Missing bundled DLL did not fail closed' }
    } finally {
        Move-Item -LiteralPath ($m1Dll + '.disabled') -Destination $m1Dll
    }
    Get-ChildItem -LiteralPath $m1Copy -File -Recurse | ForEach-Object {
        [pscustomobject]@{ Path=[IO.Path]::GetRelativePath($m1Copy,$_.FullName); Bytes=$_.Length; SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $m1Evidence 'copied-bundle-manifest.json') -Encoding utf8
    $m1Status.Status = 'PASS'
} finally {
    $env:PATH = $m1OldPath
    $env:PARASELENE_M1_DLL = $m1OldDll
    $m1Status | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $m1Evidence 'copied-bundle-status.json') -Encoding utf8
}
$m1Status | ConvertTo-Json
