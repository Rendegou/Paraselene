#requires -Version 7.0
<#
.SYNOPSIS
    幻月统一质量检查入口（T05A 建立）。

.DESCRIPTION
    列出并逐项运行本地质量检查；本地与后续 CI 使用同一入口和同一口径。
    每个检查输出 `CHECK <名称>: PASS|FAIL|NOT_RUN`；工具/依赖/环境缺失一律记
    NOT_RUN，绝不把缺工具报成 PASS。退出码：0=全部已运行且通过；1=至少一项
    FAIL；3=存在 NOT_RUN 且无 FAIL；2=用法错误。

    检查项（category:frontend|rust|docs）：
      typecheck               pnpm typecheck（前端类型检查）
      build                   pnpm build（Vite runner 构建）
      web-tests               node scripts/quality/run-web-tests.mjs（前端行为测试）
      ipc-boundary            组件禁直接 import @tauri-apps（AST 检查）
      ts-metrics              TS 函数/组件/模块长度与圈复杂度，对基线校验
      cargo-novel-memory-test 小说/记忆核心 Rust 测试
      cargo-check-paraselene  Tauri 外壳编译检查
      rust-metrics            Rust 函数/模块有效行，对基线校验
      cargo-fmt               rustfmt 全仓格式检查（历史债务，见债务清单）
      cargo-clippy            clippy（novel-core/memory-core 变更面）

.PARAMETER List
    只列出检查及其工具可用性，不运行。

.PARAMETER All
    运行所有工具可用的检查。

.PARAMETER Check
    只运行指定名称的一个检查。

.EXAMPLE
    pwsh scripts/check-quality.ps1 -List
    pwsh scripts/check-quality.ps1 -All
    pwsh scripts/check-quality.ps1 -Check typecheck
#>
[CmdletBinding()]
param(
    [switch]$List,
    [switch]$All,
    [string]$Check = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$mingwBin = "C:\tools\paraselene-build\mingw64\bin"
if (Test-Path $mingwBin) {
    $env:PATH = "$mingwBin;$env:PATH"
}
Set-Location $repoRoot

function Test-Tool([string]$name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

# 检查注册表：Name/Category/Need(工具数组)/Run(scriptblock 返回退出码)。
$checks = @(
    @{ Name = "typecheck"; Category = "frontend"; Need = @("pnpm"); Run = { pnpm typecheck | Out-Host; return $global:LASTEXITCODE } },
    @{ Name = "build"; Category = "frontend"; Need = @("pnpm"); Run = { pnpm build | Out-Host; return $global:LASTEXITCODE } },
    @{ Name = "web-tests"; Category = "frontend"; Need = @("node"); Run = { node scripts/quality/run-web-tests.mjs | Out-Host; return $global:LASTEXITCODE } },
    @{ Name = "ipc-boundary"; Category = "frontend"; Need = @("node"); Run = { node scripts/quality/code-metrics.mjs --ipc-boundary | Out-Host; return $global:LASTEXITCODE } },
    @{ Name = "ts-metrics"; Category = "frontend"; Need = @("node"); Run = { node scripts/quality/code-metrics.mjs --verify docs/engineering/code-metrics-baseline.json | Out-Host; return $global:LASTEXITCODE } },
    @{ Name = "cargo-novel-memory-test"; Category = "rust"; Need = @("cargo"); Run = { cargo test -p paraselene-novel-core -p paraselene-memory-core --target-dir 'D:\MyAgent\.cargo-target' --offline | Out-Host; return $global:LASTEXITCODE } },
    @{ Name = "cargo-check-paraselene"; Category = "rust"; Need = @("cargo"); Run = { cargo check -p paraselene --target-dir 'D:\MyAgent\.cargo-target' --offline | Out-Host; return $global:LASTEXITCODE } },
    @{ Name = "rust-metrics"; Category = "rust"; Need = @("cargo"); Run = { cargo run -p paraselene-code-metrics --release --target-dir 'D:\MyAgent\.cargo-target' --offline -- --verify docs/engineering/rust-metrics-baseline.json | Out-Host; return $global:LASTEXITCODE } },
    @{ Name = "cargo-fmt"; Category = "rust"; Need = @("cargo"); Run = { cargo fmt --all -- --check | Out-Host; return $global:LASTEXITCODE } },
    @{ Name = "cargo-clippy"; Category = "rust"; Need = @("cargo"); Run = { cargo clippy -p paraselene-novel-core -p paraselene-memory-core --target-dir 'D:\MyAgent\.cargo-target' --offline -- -D warnings | Out-Host; return $global:LASTEXITCODE } }
)

function Show-Check([object]$c) {
    $missing = @($c.Need | Where-Object { -not (Test-Tool $_) })
    $state = if ($missing.Count -gt 0) { "tool-missing:$($missing -join ',')" } else { "available" }
    [pscustomobject]@{ Name = $c.Name; Category = $c.Category; State = $state }
}

if ($List) {
    $checks | ForEach-Object { Show-Check $_ } | Format-Table -AutoSize
    return
}

$selected = @()
if ($Check) {
    $selected = @($checks | Where-Object { $_.Name -eq $Check })
    if ($selected.Count -eq 0) {
        Write-Error "未知检查：$Check。用 -List 查看可用检查。"
        exit 2
    }
} elseif ($All) {
    $selected = $checks
} else {
    Write-Error "请指定 -List、-All 或 -Check <名称>。"
    exit 2
}

$fail = 0
$notRun = 0
foreach ($c in $selected) {
    $missing = @($c.Need | Where-Object { -not (Test-Tool $_) })
    if ($missing.Count -gt 0) {
        Write-Output "CHECK $($c.Name): NOT_RUN (missing: $($missing -join ', '))"
        $notRun++
        continue
    }
    $started = Get-Date
    try {
        $code = & $c.Run
        if ($null -eq $code) { $code = 0 }
    } catch {
        Write-Output $_.Exception.Message
        $code = 1
    }
    $secs = [int]((Get-Date) - $started).TotalSeconds
    if ($code -eq 0) {
        Write-Output "CHECK $($c.Name): PASS (exit=0, ${secs}s)"
    } else {
        Write-Output "CHECK $($c.Name): FAIL (exit=$code, ${secs}s)"
        $fail++
    }
}

Write-Output "SUMMARY: total=$($selected.Count) fail=$fail not_run=$notRun"
if ($fail -gt 0) { exit 1 }
if ($notRun -gt 0) { exit 3 }
exit 0
