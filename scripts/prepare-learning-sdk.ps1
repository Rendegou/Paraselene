# 下载并校验固定版本 WebView2 SDK，解压到本地 vendor 目录供原生探针编译。
# 只准备头文件与 SDK 缓存，不安装运行时，也不代表学习沙箱运行通过。

param()
$ErrorActionPreference = 'Stop'
$learningRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$learningVendor = Join-Path $learningRoot 'build/vendor/webview2-1.0.2903.40'
$learningArchive = Join-Path $learningVendor 'sdk.zip'
$learningSha = 'EF128016DD1E51C59178C827ED5B8AA3322C57AFA8675D930F8109505542AD74'
New-Item -ItemType Directory -Force -Path $learningVendor | Out-Null
if (!(Test-Path -LiteralPath $learningArchive)) {
    Invoke-WebRequest -Uri 'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/1.0.2903.40/microsoft.web.webview2.1.0.2903.40.nupkg' -OutFile $learningArchive
}
if ((Get-FileHash -LiteralPath $learningArchive -Algorithm SHA256).Hash -ne $learningSha) { throw 'WebView2 SDK hash mismatch' }
$learningHeader = Join-Path $learningVendor 'package/build/native/include/WebView2.h'
if (!(Test-Path -LiteralPath $learningHeader)) {
    Expand-Archive -LiteralPath $learningArchive -DestinationPath (Join-Path $learningVendor 'package')
}
Write-Output 'Pinned WebView2 SDK is ready. No runtime was installed.'
