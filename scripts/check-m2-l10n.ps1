# 校验 ARB 键、用途元数据、嵌套 ICU 与占位符类型；不输出消息正文。
# 此静态检查不能替代 gen-l10n、翻译复核或原生语言切换验收。
param(
    [string]$ArbDirectory = (Join-Path $PSScriptRoot '..\apps\desktop\lib\l10n'),
    [string]$DartExecutable = 'D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.exe'
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $DartExecutable -PathType Leaf)) {
    Write-Output 'NOT_RUN: Dart executable unavailable.'
    exit 3
}
$frontArbCheck = Join-Path $PSScriptRoot '..\tools\frontend_checks\bin\check_arb.dart'
& $DartExecutable $frontArbCheck $ArbDirectory
exit $LASTEXITCODE
