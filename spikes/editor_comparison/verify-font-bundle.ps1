param(
    [Parameter(Mandatory)][string]$BundlePath,
    [Parameter(Mandatory)][string]$ReportPath
)
$ErrorActionPreference = 'Stop'
$fontBundleRoot = (Resolve-Path -LiteralPath $BundlePath).Path
$fontAssetsRoot = Join-Path $fontBundleRoot 'data/flutter_assets'
$fontSourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../apps/desktop/assets/fonts'))
$fontManifest = Get-Content -LiteralPath (Join-Path $fontAssetsRoot 'FontManifest.json') -Raw | ConvertFrom-Json
$fontVerified = @()
foreach ($fontFace in @{
    'Notebook Sans' = 'NotoSansSC-Regular.ttf'
    'Notebook Serif' = 'NotoSerifSC-Regular.ttf'
    'Noto Arabic' = 'NotoNaskhArabic.ttf'
}.GetEnumerator()) {
    $fontEntry = @($fontManifest | Where-Object family -eq $fontFace.Key)
    if ($fontEntry.Count -ne 1) { throw "Missing/duplicate font family: $($fontFace.Key)" }
    $fontAsset = $fontEntry[0].fonts[0].asset
    if ($fontAsset -ne "assets/fonts/$($fontFace.Value)") {
        throw "Unexpected package-external font path: $fontAsset"
    }
    $fontActualPath = Join-Path $fontAssetsRoot $fontAsset
    $fontExpectedHash = (Get-FileHash -LiteralPath (Join-Path $fontSourceRoot $fontFace.Value)).Hash
    $fontActualHash = (Get-FileHash -LiteralPath $fontActualPath).Hash
    if ($fontExpectedHash -ne $fontActualHash) { throw "Font bundle hash mismatch: $fontAsset" }
    $fontVerified += [ordered]@{ Family=$fontFace.Key; Asset=$fontAsset; Sha256=$fontActualHash }
}
foreach ($fontNotice in 'NotoSansSC-OFL.txt','NotoSerifSC-OFL.txt','NotoNaskhArabic-OFL.txt') {
    $fontExpectedHash = (Get-FileHash -LiteralPath (Join-Path $fontSourceRoot $fontNotice)).Hash
    if ((Get-FileHash -LiteralPath (Join-Path $fontAssetsRoot "assets/fonts/$fontNotice")).Hash -ne $fontExpectedHash) {
        throw "Font notice hash mismatch: $fontNotice"
    }
}
[ordered]@{
    Scope='Bundle presence and SHA256 only; runtime FontLoader verification is separate'
    AppSoSha256=(Get-FileHash -LiteralPath (Join-Path $fontBundleRoot 'data/app.so')).Hash
    Fonts=$fontVerified
    LicenseFilesVerified=3
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath
Write-Output 'Verified 3 bundled font faces and 3 exact OFL notices.'
