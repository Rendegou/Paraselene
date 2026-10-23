# CLIENT-MVP A：交互实现与部分原生证据

日期：2026-10-12。工作副本：`D:\MyAgent\paraselene-work`。分支：`codex/client-mvp-20261012`。负责人：root；菜单 interaction_audit；导出 agent_release_audit，额度中断后root收尾。

状态：**A_IMPLEMENTED_PARTIAL / NATIVE_ACCEPTANCE_INTERRUPTED**。B仅合同，C/D未实施；不标CLIENT_MVP_PASS。

## 已交付

- 按计划先完成四视角审查并去重：[清单](../novel/client-mvp-review-20261012.md)、[B数据合同](../novel/client-mvp-data-contract-20261012.md)。含2项P0旧保存风险；没有直接复用存在缺陷的旧hook。
- 章节标题默认h1，主动重命名才出现input；完成/取消、空标题保护、组成输入Enter/Escape过滤；移除固定卷名。
- 当前章CodeMirror在资料页隐藏保活，保留会话undo；记录普通返回的滚动和输入控件范围，同ID共写textarea可恢复；显式出处定位不被普通返回覆盖。资料编辑保留活动线程ID。
- 版式/导出/新增资料共用键盘菜单，首项聚焦、上下循环、Home/End、Escape回触发器，保留Tab；过滤IME及已消费事件，资料卡不再重复消费菜单Escape。
- 文本选择仅在操作chrome受限；正文、输入、资料、候选仍可复制。保留caret与键盘轮廓；没有用CSS宣称未知跨块caret根因已修复。
- 项目框架仅显式design可见；当前仍预览数据，保留准确示例/预览身份，未伪装正式SQLite。
- 原生导出经唯一ipc封装→薄Rust命令→系统保存对话框；只有实际UTF-8写入/sync/替换成功返回saved，取消返回cancelled。失败提示持续、可按原格式重试；重复点击受busy保护，对话框完成后回导出按钮。只导出当前可见稿，无网络，无数据库读取；JSON明确是预览快照。
- 合成A窗口example使用打包前端、同一CodeMirror与相同CSP，没有初始化或读取作者数据库/Key。追加的观察器仅记录元素tag、是否输入、组成事件类别，不记录文字；追加观察器尚未原生运行。

主要新增文件：`ChapterHeading.tsx`、`useSurfaceReturn.ts`、`menuKeyboard.ts/.test.ts`、`useMenuNavigation.ts`、`useStudioExport.ts`、`commands/studio_export.rs`、`examples/notebook_window_probe.rs`。既有大量未提交修改保留，不向原目录同步。

## 实际命令与结果

所有命令为PowerShell7。每项独立核对退出码，不把最后一项成功当作前项成功。

```powershell
node node_modules/typescript/bin/tsc --noEmit
node node_modules/vite/bin/vite.js build --configLoader runner
node scripts/quality/run-web-tests.mjs
node scripts/quality/code-metrics.mjs --verify docs/engineering/code-metrics-baseline.json --json
node scripts/quality/code-metrics.mjs --ipc-boundary
git diff --check
```

最终类型、Vite、32项行为、TS AST和IPC边界均退出0；32/32、0 skipped，TS存量7/当前7/新增0，IPC offenders=[]。Vite175模块，活动chunk500.74KB/gzip164.16KB，有>500KB提示，不调整阈值隐藏。git diff --check退出0（已有CRLF提示不算错误）。2项新测试针对IME/消费事件和菜单导航边界；不是原生IME证据。

最终活动构建：`dist/assets/index-CeLYtN5m.js`，SHA256 `D7D5C29646C517FEBE7DD941637F99706ED5305BFE2A0168B5D5233D445282B6`。仅是前端资产标识，不是安装包标识。

```powershell
$env:PATH='C:\tools\paraselene-build\mingw64\bin;' + $env:PATH
cargo build -p paraselene --example notebook_window_probe --target-dir 'D:\MyAgent\.cargo-target' --offline
cargo test -p paraselene --lib commands::studio_export::tests --target-dir 'D:\MyAgent\.cargo-target' --offline
cargo run -p paraselene-code-metrics --release --target-dir 'D:\MyAgent\.cargo-target' --offline -- --verify docs/engineering/rust-metrics-baseline.json
```

隔离example构建退出0；编译了实际Tauri薄命令。导出测试3/3，0 ignored，11个不相关用例被测试名筛掉：仅导出模块通过，不算全量Rust PASS。覆盖文件名路径/设备名、16MiB字节上限、JSON验证、中文emoji/CRLF写入、已有文件覆盖和失败不留临时文件。Rust AST存量36/当前36/新增0，退出0。测试编译保留旧quiet模块dead_code警告。

用户停止UI之后只做源码检查：`cargo check -p paraselene --example notebook_window_probe --target-dir 'D:\MyAgent\.cargo-target' --offline` 退出0，覆盖最终观察器源码；未再次启动或控制窗口。自建1424/1425测试服务已停止。

新增Rust文件单独rustfmt。没有批量重写旧代码；cargo-fmt全量与全量Rust/Clippy本轮NOT_RUN。

Impeccable detector实际运行一次：3项advisory、退出1；均为原样已有色值`#aebcd3`、`#26344814`和已在DESIGN prose说明的27px窄屏字号，不作为新增设计或行为故障，不假报检测器绿。

## 环境故障与修正

- 沙箱内cargo check失败：generate_context报OUT_DIR未设置；原生build进一步确认Tauri依赖canonicalize被权限拒绝（code5）。同命令沙箱外自动审批获准，原生构建成功；未放宽CSP或IPC。
- node_modules为既有junction；preview的配置打包/runner分别遇EPERM/require/module解析问题。最小本机preview使用Vite API `configFile:false`；沙箱外最终产品build沿用原vite.config.ts成功，没有更改依赖或工具配置。
- example初次启动无窗口：退出`-1073741515`（0xC0000135），objdump显示WebView2Loader.dll依赖。Cargo把Loader放debug目录而example在debug/examples；运行时PATH加入debug后出现原生窗口。安装版Loader分发仍属D验收，不能按这次PATH修正宣称安装成功。
- 本轮尝试的1424/1425浏览器预览连接超时，未形成浏览器操作证据；不继承此前截图为本轮验证。

## 实际原生操作

使用Windows Computer Use插件，经返回的唯一窗口对象控制`幻月 · A阶段合成验收`。初始窗口1280×800逻辑尺寸、最小760×560；截图约1283×831含标题栏。系统读到Windows版本`10.0.26200.0`；WebView2目录版本`154.0.4258.62`。DPI比例没有可靠查询结果，不能用截图尺寸推定所有DPI通过。

1. 启动打包UI，不依赖开发服务器；fixture20章、4040字当前章与7份资料，无私人数据读写。
2. 初始标题是h1且有“重命名”按钮，不是input；点击按钮出现编辑态。
3. 对标题输入执行辅助功能set_value `原生重命名验收😀`，按Return后下一次实际截图显示同名h1及目录同步，input已退出。这验证原生Unicode控件与提交，**不等于微软拼音组成输入**。
4. 原生版式菜单显示菜单语义；Down后截图有“宽稿”焦点轮廓，Escape后后续AX无正文宽度菜单。单层键盘路径有证据，卡片/菜单叠层仍未测。
5. 导出→Markdown，实际AX出现“导出当前写作稿”系统对话框、保存类型`写作稿 (*.md)`、保存/取消按钮。这只证明对话框已打开。
6. 准备点击取消时，工具报告 **Computer Use was stopped by the user with the physical Escape key**。立即停止全部UI操作；无法确认取消结果，不能计取消通过。对话框之后状态、写文件、覆盖、不可写位置与焦点回归未原生复验。

辅助功能focused_element持续只报告RootWebArea，不能据此断言DOM焦点错位。截图显示菜单轮廓与标题提交；尚无逐控件光标类型、原选区、IME候选窗的完整原生记录。

原生测试使用的嵌入前端为早期A实现（约174模块），之后增加滚动/原输入恢复和独立review修正，最终175模块构建没有重新原生运行。不能把早期操作结果转记为最终构建验收。

## 独立review

fresh a_review只读复核，发现3项P2：JSON重试变Markdown、资料返回强制正文焦点、导出busy导致触发器失焦。三项均按建议修正并复跑类型/构建/32行为/TS门；二次复核又指出全章/失效锚点抽屉在paper兄弟节点，焦点监听范围未覆盖，已扩大到writing-main并继续仅记录manuscript时的输入。最终原生操作因用户停止未复验。IME组成Enter是否影响候选提交仅列待验证，review不将其报成已复现缺陷。

## 未完成与下一动作

A出口仍PARTIAL：微软拼音、选区/拖选/双击、资料往返原焦点与undo、段下非输入区域异常caret、叠层Escape、系统取消/写入/覆盖失败、100/125/150%DPI、最小/最大化与窗口策略仍需最终构建实际操作。

按原计划先完成A原生出口，再实施B数据合同；B正式作品、按章SQLite、空稿CAS/切换flush、资料/线程迁移尚未接线。C真实生成未调用，无作者Key或外发授权；D安装产物和安装验收未实施。没有自动读取或使用Key，不把合成/筛选测试当作CLIENT_MVP_PASS。
