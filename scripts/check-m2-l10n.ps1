# 校验 ARB 的键集合、占位符类型与元数据在模板和各 locale 之间一致。
# 静态 ARB 检查，不代表生成代码、翻译质量或运行期本地化 UI 通过。

param([string]$ArbDirectory = (Join-Path $PSScriptRoot '..\apps\desktop\lib\l10n'))
$ErrorActionPreference = 'Stop'
$m2Template = Get-Content -LiteralPath (Join-Path $ArbDirectory 'app_en.arb') -Raw | ConvertFrom-Json -AsHashtable
$m2Keys = @($m2Template.Keys | Where-Object { !$_.StartsWith('@') } | Sort-Object -CaseSensitive)
function Get-MessageFields([string]$Message) {
    @([regex]::Matches($Message, '\{([A-Za-z][A-Za-z0-9_]*)\s*[,}]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique -CaseSensitive)
}
foreach ($m2Key in $m2Keys) {
    if (!$m2Template["@$m2Key"].description) { throw "Missing description for $m2Key" }
    foreach ($m2Field in (Get-MessageFields $m2Template[$m2Key])) {
        if (!$m2Template["@$m2Key"].placeholders[$m2Field].type) { throw "Missing placeholder type: $m2Key/$m2Field" }
    }
    $m2Declared = @($m2Template["@$m2Key"].placeholders.Keys | Sort-Object -CaseSensitive) -join ','
    $m2Used = (Get-MessageFields $m2Template[$m2Key]) -join ','
    if ($m2Declared -cne $m2Used) { throw "Template placeholder metadata differs: $m2Key" }
}
$m2Locales = @(Get-ChildItem -LiteralPath $ArbDirectory -Filter 'app_*.arb')
foreach ($m2File in $m2Locales) {
    $m2Arb = Get-Content -LiteralPath $m2File.FullName -Raw | ConvertFrom-Json -AsHashtable
    $m2OtherKeys = @($m2Arb.Keys | Where-Object { !$_.StartsWith('@') } | Sort-Object -CaseSensitive)
    if (($m2Keys -join "`n") -cne ($m2OtherKeys -join "`n")) { throw "ARB keys differ: $($m2File.Name)" }
    foreach ($m2Key in $m2Keys) {
        $m2Expected = (Get-MessageFields $m2Template[$m2Key]) -join ','
        $m2Actual = (Get-MessageFields $m2Arb[$m2Key]) -join ','
        if ($m2Expected -cne $m2Actual) { throw "ARB placeholders differ: $($m2File.Name)/$m2Key" }
        $m2Metadata = $m2Arb["@$m2Key"].placeholders
        if ($m2Metadata) {
            if ((@($m2Metadata.Keys | Sort-Object -CaseSensitive) -join ',') -cne $m2Expected) { throw "ARB placeholder metadata differs: $($m2File.Name)/$m2Key" }
            foreach ($m2Field in $m2Metadata.Keys) {
                if ($m2Metadata[$m2Field].type -cne $m2Template["@$m2Key"].placeholders[$m2Field].type) { throw "ARB placeholder type differs: $($m2File.Name)/$m2Key/$m2Field" }
            }
        }
    }
}
[pscustomobject]@{ Status='PASS'; Keys=$m2Keys.Count; ArbFiles=$m2Locales.Count; TypedPlaceholders=$true } | ConvertTo-Json
