#requires -Version 7.0
<#
.SYNOPSIS
    幻月性能基线采样脚本（T00 骨架）。

.DESCRIPTION
    启动后按固定间隔对指定进程名采样驻留内存（WorkingSet64）与累计 CPU 时间，
    计算区间 CPU 占用率，输出 CSV 供 G19 性能门槛（冷启动 / 驻留内存 / CPU）实测引用。
    测量方法：先记录进程累计 CPU 秒数，两次采样差值 ÷ 墙钟秒数 ÷ 逻辑核数 = 区间 CPU 占用率。

.PARAMETER ProcessName
    被采样进程名（不含 .exe），默认 paraselene。

.PARAMETER IntervalSeconds
    采样间隔秒数，默认 5。

.PARAMETER Samples
    采样次数，默认 60（约 5 分钟）。

.PARAMETER OutCsv
    CSV 输出路径，默认写入 docs/evidence/perf-baseline-<时间戳>.csv。

.EXAMPLE
    pwsh scripts/perf-baseline.ps1 -ProcessName paraselene -Samples 120
#>
[CmdletBinding()]
param(
    [string]$ProcessName = "paraselene",
    [ValidateRange(1, 3600)]
    [int]$IntervalSeconds = 5,
    [ValidateRange(1, 100000)]
    [int]$Samples = 60,
    [string]$OutCsv = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not $OutCsv) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutCsv = Join-Path $repoRoot "docs/evidence/perf-baseline-$stamp.csv"
}
$outDir = Split-Path -Parent $OutCsv
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$logicalCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$rows = [System.Collections.Generic.List[object]]::new()
$prevCpuSeconds = $null
$prevTime = $null

Write-Host "采样进程 '$ProcessName'：$Samples 次 × $IntervalSeconds 秒（$logicalCores 逻辑核）→ $OutCsv"

for ($i = 0; $i -lt $Samples; $i++) {
    $procs = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) {
        Write-Warning "第 $i 次采样：未找到进程 '$ProcessName'，跳过（应用未启动？）"
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }

    $now = Get-Date
    # 多实例时聚合：内存求和，CPU 时间求和。
    $workingSet = ($procs | Measure-Object -Property WorkingSet64 -Sum).Sum
    $cpuSeconds = ($procs | Measure-Object -Property CPU -Sum).Sum

    $cpuPercent = $null
    if ($null -ne $prevCpuSeconds -and $null -ne $prevTime) {
        $wall = ($now - $prevTime).TotalSeconds
        if ($wall -gt 0) {
            $cpuPercent = [math]::Round((($cpuSeconds - $prevCpuSeconds) / $wall / $logicalCores) * 100, 2)
        }
    }

    $rows.Add([pscustomobject]@{
        Timestamp        = $now.ToString("o")
        ProcessName      = $ProcessName
        InstanceCount    = $procs.Count
        WorkingSet64MB   = [math]::Round($workingSet / 1MB, 2)
        CpuTotalSeconds  = [math]::Round($cpuSeconds, 2)
        CpuPercentApprox = $cpuPercent
    })

    $prevCpuSeconds = $cpuSeconds
    $prevTime = $now
    if ($i -lt $Samples - 1) { Start-Sleep -Seconds $IntervalSeconds }
}

if ($rows.Count -eq 0) {
    Write-Error "没有任何采样行：进程 '$ProcessName' 全程未运行。"
}

$rows | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding utf8
$avgMem = ($rows | Measure-Object -Property WorkingSet64MB -Average).Average
$maxMem = ($rows | Measure-Object -Property WorkingSet64MB -Maximum).Maximum
Write-Host ("完成：{0} 行。平均驻留 {1:N1} MB，峰值 {2:N1} MB。" -f $rows.Count, $avgMem, $maxMem)
Write-Host "注意：性能数字须连同硬件与系统环境记入 docs/evidence/（AGENTS.md §5）。"
