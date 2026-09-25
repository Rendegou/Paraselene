#requires -Version 7.0
<#
.SYNOPSIS
    生成幻月占位图标：透明背景上的淡黄圆月（System.Drawing，1024x1024 PNG）。
.DESCRIPTION
    T00 脚手架临时图标，仅用于跑通 `pnpm tauri icon` 图标流水线；正式形象在 T03 形象包任务替换。
#>
[CmdletBinding()]
param(
    [string]$OutPath = (Join-Path $PSScriptRoot ".." | Resolve-Path | Join-Path -ChildPath "src-tauri/icons-source.png")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$size = 1024
$bmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)

# 外圈光晕 + 月盘，颜色与前端占位原型一致（淡黄月光）。
$halo = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(90, 240, 220, 130))
$moon = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 232, 217, 138))
$rect = New-Object System.Drawing.Rectangle 112, 112, 800, 800
$g.FillEllipse($halo, 40, 40, 944, 944)
$g.FillEllipse($moon, $rect.X, $rect.Y, $rect.Width, $rect.Height)

$dir = Split-Path -Parent $OutPath
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)

$g.Dispose(); $halo.Dispose(); $moon.Dispose(); $bmp.Dispose()
Write-Host "占位图标已生成：$OutPath"
