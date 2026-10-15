$ErrorActionPreference = 'Stop'
$fontSourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../apps/desktop/assets/fonts'))
$fontStageRoot = Join-Path $PSScriptRoot 'assets/fonts'
New-Item -ItemType Directory -Path $fontStageRoot -Force | Out-Null
$fontFiles = @(
    'NotoSansSC-Regular.ttf', 'NotoSerifSC-Regular.ttf', 'NotoNaskhArabic.ttf',
    'NotoSansSC-OFL.txt', 'NotoSerifSC-OFL.txt', 'NotoNaskhArabic-OFL.txt'
)
foreach ($fontFileName in $fontFiles) {
    $fontSourcePath = Join-Path $fontSourceRoot $fontFileName
    $fontStagePath = Join-Path $fontStageRoot $fontFileName
    Copy-Item -LiteralPath $fontSourcePath -Destination $fontStagePath -Force
    if ((Get-FileHash -LiteralPath $fontSourcePath).Hash -ne (Get-FileHash -LiteralPath $fontStagePath).Hash) {
        throw "Font staging hash mismatch: $fontFileName"
    }
}
Write-Output "Staged and verified $($fontFiles.Count) font/license files."
