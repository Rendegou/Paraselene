# 字体打包更正与 A/B 重采

2026-10-15。C验证前检查发现，原型pubspec用`../../apps/desktop/assets/fonts`
作为font asset键。FontManifest虽声明Notebook字体，Windows最终bundle仅14文件，
没有3个TTF；因此原A/B报告中的字体条件没有成立证据，不能作为固定字体对照。
主会话已向用户明确更正。原始测量没有伪造，但错误地把fontFamily声明当作实际加载。

修正：`prepare-fonts.ps1`从只读使用的M2字体资产复制3个TTF和3份OFL到包内
`assets/fonts`并校验SHA256；pubspec只引用包内路径。`loadSpikeFonts()`在runApp前
await全部FontLoader，缺资源则启动失败。无需下载字体、不改M2或原工程。

`verify-font-bundle.ps1`对旧保留bundle退出1（预期负例，拒绝包外路径），
对新bundle退出0，3字体及3份OFL SHA256匹配。新profile程序启动并退出0。
证据 `ab-font-bundle.json`，重采 `ab-font-validated-profile.json`，构建日志
`ab-font-build.txt`。修正后bundle保留在 `build/m3-ab-font-validated-profile`。

同一i9-13900HX/Windows、Flutter3.32.1 profile、DPR1.5、正文760logical px、
Notebook Serif20px/1.85，原BMP合成fixture未改。UI帧代理仍非真实显示器呈现：

|候选|样本|单次装载ms|编辑P50 ms|编辑P95 ms|
|---|---|---:|---:|---:|
|A|10k|9.12|8.00|9.35|
|A|200k|74.33|81.41|85.04|
|A|200k单逻辑行|78.08|74.62|79.33|
|B|10k|21.36|4.72|7.17|
|B|200k|864.92|86.16|213.72|
|B|200k单逻辑行|326.39|75.34|83.05|

当前两候选仍未满足输入P95≤50ms。修正后B的单次20万字装载已落在1s预算内，
不能继续引用旧字体条件下的1066ms宣称该项失败。B复制/撤销缺陷独立成立。
原生IME trace发生在旧字体构建中，继续只证明当时的小样本组合输入，不是新bundle认证。

旧`flutter-profile-before-font-fix.json`及preflight留档；新的`flutter-profile.json`
是修正字体后的A/B结果。原`artifact-manifest.json`只标识旧构建，不能误当新bundle散列。
