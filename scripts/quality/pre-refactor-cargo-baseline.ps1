# T05A 变更前基线：cargo 测试与 Tauri check（证据用，退出码落盘）。
$ErrorActionPreference = "Stop"
$mingwBin = "C:\tools\paraselene-build\mingw64\bin"
if (Test-Path $mingwBin) { $env:PATH = "$mingwBin;$env:PATH" }
Set-Location (Split-Path -Parent $PSScriptRoot)

cargo test -p paraselene-novel-core -p paraselene-memory-core --target-dir 'D:\MyAgent\.cargo-target' --offline
$testExit = $LASTEXITCODE
Write-Output "PRE_CARGO_TEST_EXIT=$testExit"

cargo check -p paraselene --target-dir 'D:\MyAgent\.cargo-target' --offline
$checkExit = $LASTEXITCODE
Write-Output "PRE_CARGO_CHECK_EXIT=$checkExit"

exit $(if ($testExit -ne 0 -or $checkExit -ne 0) { 1 } else { 0 })
