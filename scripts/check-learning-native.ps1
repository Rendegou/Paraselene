# 构建并运行学习沙箱的原生探针，保存 configure/build 日志、输入哈希与结果证据。
# 探针不启动 Flutter 引擎，也不代表干净机器上的 WebView2 运行时行为通过。

param([string]$EvidenceDirectory = 'docs/evidence/m9-learning-native', [switch]$Channel, [switch]$Geolocation)
$ErrorActionPreference = 'Stop'
if ($Channel -and $Geolocation) { throw 'Choose only one native suite' }
$learningRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$learningEvidence = [IO.Path]::GetFullPath((Join-Path $learningRoot $EvidenceDirectory))
if (!$learningEvidence.StartsWith($learningRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence must remain inside target repository' }
New-Item -ItemType Directory -Force -Path $learningEvidence | Out-Null
$learningCache = Join-Path $learningRoot 'apps/desktop/build/windows/x64/CMakeCache.txt'
$learningCmake = ((Get-Content -LiteralPath $learningCache | Select-String '^CMAKE_COMMAND:INTERNAL=').Line -split '=', 2)[1]
if (!(Test-Path -LiteralPath $learningCmake -PathType Leaf)) { throw 'Build Release first to locate the configured CMake' }
$learningBuild = Join-Path $learningRoot 'build/learning-native'
& $learningCmake -S (Join-Path $learningRoot 'tests/learning_native') -B $learningBuild -G 'Visual Studio 17 2022' -A x64 *> (Join-Path $learningEvidence 'configure.txt')
if ($LASTEXITCODE -ne 0) { throw 'Native probe configure failed; see configure.txt' }
& $learningCmake --build $learningBuild --config Release *> (Join-Path $learningEvidence 'build.txt')
if ($LASTEXITCODE -ne 0) { throw 'Native probe build failed; see build.txt' }
$learningTemporary = Join-Path $learningBuild ('synthetic-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $learningTemporary | Out-Null
$learningJunctions = Join-Path $learningTemporary 'junction-attacks'
$learningJunctionTarget = Join-Path $learningJunctions 'owned-target'
$learningJunctionProfile = Join-Path $learningJunctions 'profile'
$learningJunctionAncestor = Join-Path $learningJunctions 'ancestor'
New-Item -ItemType Directory -Path $learningJunctionTarget, $learningJunctionProfile, $learningJunctionAncestor | Out-Null
New-Item -ItemType Directory -Path (Join-Path $learningJunctionTarget 'child') | Out-Null
Set-Content -LiteralPath (Join-Path $learningJunctionTarget 'sentinel.txt') -Value 'synthetic-target-must-survive' -NoNewline -Encoding utf8
New-Item -ItemType Junction -Path (Join-Path $learningJunctionProfile 'paraselene-flutter-learning-cache-v1') -Target $learningJunctionTarget | Out-Null
New-Item -ItemType Junction -Path (Join-Path $learningJunctionAncestor 'linked') -Target $learningJunctionTarget | Out-Null
Set-Content -LiteralPath (Join-Path $learningTemporary 'PARASELENE_NATIVE_PROBE_V1') -Value 'owned-synthetic-native-probe' -NoNewline -Encoding utf8
$learningOldTemp = $env:TEMP
$learningOldTmp = $env:TMP
$learningAssets = Join-Path $learningRoot 'apps/desktop/build/windows/x64/runner/Release/data/flutter_assets/assets/learning'
$learningInputs = @(
    (Join-Path $learningBuild 'Release/learning_native_probe.exe'),
    (Join-Path $learningBuild 'Release/learning_channel_probe.exe'),
    (Join-Path $learningRoot 'apps/desktop/windows/runner/learning_window.cpp'),
    (Join-Path $learningRoot 'apps/desktop/windows/runner/learning_window.h'),
    (Join-Path $learningRoot 'apps/desktop/windows/runner/learning_security.cpp'),
    (Join-Path $learningRoot 'apps/desktop/windows/runner/learning_profile.cpp'),
    (Join-Path $learningRoot 'tests/learning_native/probe.cpp'),
    (Join-Path $learningRoot 'tests/learning_native/channel_probe.cpp'),
    (Join-Path $learningRoot 'tests/learning_native/CMakeLists.txt')
) + @(Get-ChildItem -LiteralPath $learningAssets -File -Recurse | Select-Object -ExpandProperty FullName)
$learningInputs | ForEach-Object { Get-FileHash -LiteralPath $_ -Algorithm SHA256 } | Select-Object Path, Hash | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $learningEvidence 'inputs-sha256.json') -Encoding utf8
$learningExit = $null
try {
    $env:TEMP = $learningTemporary
    $env:TMP = $learningTemporary
    $learningExecutable = if ($Channel) { 'learning_channel_probe.exe' } else { 'learning_native_probe.exe' }
    $learningArguments = '"' + $learningAssets + '" "' + $learningTemporary + '"'
    if ($Geolocation) { $learningArguments += ' --geolocation' }
    $learningProcess = Start-Process -FilePath (Join-Path $learningBuild ('Release/' + $learningExecutable)) -ArgumentList $learningArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $learningEvidence 'stdout.txt') -RedirectStandardError (Join-Path $learningEvidence 'stderr.txt')
    if (!$learningProcess.WaitForExit(180000)) { $learningProcess.Kill(); throw 'Dedicated learning probe exceeded 180 seconds' }
    $learningExit = $learningProcess.ExitCode
} finally {
    $env:TEMP = $learningOldTemp
    $env:TMP = $learningOldTmp
    [ordered]@{ exitCode=$learningExit; syntheticRoot=$learningTemporary; assets=$learningAssets; hiddenWindowRequested=$true; privateDesktop=$Channel.IsPresent; geolocationOnly=$Geolocation.IsPresent; flutterEngine=$false; cleanMachine=$false } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $learningEvidence 'result.json') -Encoding utf8
}
Get-Content -LiteralPath (Join-Path $learningEvidence 'stdout.txt') -Tail 20
Get-Content -LiteralPath (Join-Path $learningEvidence 'stderr.txt')
if ($learningExit -ne 0) { throw "Learning native probe failed with exit $learningExit" }
