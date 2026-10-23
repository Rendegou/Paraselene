# Luna 前端整改独立验收 · 2026-10-22

## 结论

**所验自动化范围通过。** 本结论覆盖本次指定的未提交前端整改和 AST 门禁审查，不代表真实 Windows 原生环境或 golden 比较通过。未发现需上报的实质缺陷；未改动生产代码、测试、规范、golden 或其他证据文件。

基点为 `b1f9c43`。审查前读取了 `AGENTS.md`、`docs/engineering/frontend-standards.md` 与 `DESIGN.md`，并检查 tracked diff 和新增源码/测试。复核了 `detail-final-reviewed` 的状态与运行日志、freshness 样本汇总及八张历史 golden 差异图的前后 SHA-256 清单。既有证据用于交叉核对，不代替以下独立检查。

## 独立检查与观察

- **AST 菜单规则：PASS。** 按指定命令执行 Dart AST 扫描，退出码 0：141 个自有生产文件、0 项违规。`tools/frontend_checks/lib/metrics.dart:119` 处理泛型/前缀类型并检查 `PopupMenuButton.child`；`:225` 报告自定义 child 分支。新增正反例覆盖普通、带前缀和泛型构造，以及原生 `icon`、默认分支和显式 null child（`tools/frontend_checks/test/metrics_test.dart:169`）。
- **工具栏测量与窄窗布局：通过代码及有效断言核对。** `toolbar_layout.dart:11` 起按当前本地化字符串、text scaler、工具能力和保存状态测量，并预留标题/状态宽度；`toolbar_row.dart:25` 监听状态变化并使用 Expanded 标题，`:99` 的标题单行且省略时保留 tooltip。测试核对实际 RenderParagraph 宽高，而非只查 Widget（`toolbar_fold_test.dart:62`）；窄窗 200% 用例实际打开更多菜单并检查动作可达（`:145`）；状态/恢复测试核对目标边界和可点击命中（`toolbar_state_geometry_test.dart:34`）。
- **菜单命中/焦点及编辑器按键归属：通过代码与断言核对。** 相关菜单使用共享 ButtonStyle 的原生 `icon` 分支（例如 `toolbar_menus.dart:24`、`toolbar_more_menu.dart:30`、`editor_source_menu.dart:48`）；出处状态用共享控件（`manuscript_source_widgets.dart:49`、`:90`）。出处测试核对 48px 目标、Material 焦点轮廓和命中区下缘点击（`source_state_test.dart:100`）。编辑器 `_key` 在 `editor_viewport_state.dart:303` 对非 primary focus 节点返回 ignored；现有新增回归断言检查按钮 Enter 不改正文、Escape 关闭菜单并保留焦点归属，见 `toolbar_state_geometry_test.dart:97`。
- **设置异步生命周期：通过代码与行为证据核对。** `_save`/`_delete` 在 await 前冻结 repository、参数（`deepseek_settings.dart:78`、`:89`）；`_apply` 防重入，在 await 后检查 mounted，只在原 route 仍 current 时关闭；`finally` 在仍 mounted 时清空输入文本，控制器由 State 的 `dispose` 清空并释放（`:97` 起）。新增测试覆盖保存 key/cloud、删除 cloud/key 各阶段等待，以及 Escape/外点关闭、失败恢复（`deepseek_settings_test.dart:130`、`:169`、`:187`）。
- **版本历史：通过代码与有效断言核对。** 初始化时冻结 controller、work/chapter 身份并缓存读取 Future（`version_history_dialog.dart:35`）；加载、错误、空、内容分别处理，读取失败有显式重试（`:166` 起）。回滚确认之后及 await 之后均检查目标身份/生命周期；成功仅关闭原 route，失败显示当前弹窗 live region 错误（`:61` 起、`:141`）。测试实际核对缓存读取次数、稳定错误码与不泄露异常细节、重试、作品/目标切换期间阻止旧目标回滚、成功/失败及迟到结果不会关闭新 route（`versions_dialog_test.dart:162`、`:240`、`:263`、`:285`、`:340`、`:385`）。
- **本地化 freshness 默认 gate：通过脚本审阅与独立 fixture 汇总核对。** `scripts/check-frontend.ps1:123` 把 freshness 设为默认检查；缺工具退出 3 标作 NOT_RUN。新脚本在独立 build 临时目录复制输入、调用缓存的官方工具，拒绝应用内报告目录及路径逃逸，并逐路径/原始字节比较（`check-l10n-freshness.ps1:46`、`:75`、`:94`、`:156`）。对应九个 SDK 正反 fixture 汇总为 9/9，且记录源输入与生成物未变。此项本轮未重新执行官方生成器或整套 Flutter gate。

## 验证状态边界

- **本轮已执行：** 上述只读源码/测试/evidence 审查；Dart AST 扫描，退出 0，141 文件、0 违规。
- **既有最终 evidence（核对而未重跑）：** `detail-final-reviewed/summary.json` 显示选中自动检查 PASS、整体 PARTIAL；门禁反例 22/22、普通回归 676/676、owned 2/2、text 9/9、Release PASS、复制包探针 PASS。回归日志确有具体断言与各测试名，非单看通过数字。
- **golden：SKIPPED。** 未运行 golden 比较、未更新基线。before/after-final 清单均列出八张图且 SHA-256 相同；本轮没有触碰图片。
- **物理验收：NOT_RUN。** Windows IME、DPI/多屏、屏幕阅读器、净机安装均未执行。模拟按键和 Widget 测试不替代这些项目。
- **主代理补充定向复验（Luna 只读核对日志）：** `luna-acceptance-20261022/targeted-tests.txt` 记录六文件关键回归，退出码 0、47 项通过。日志包含 DeepSeek 关闭中迟到保存、工具栏几何/状态、版式和版本弹窗相关套件。本 Luna 验收未运行 Flutter；完整 gate/build 也未由 Luna 执行。

## 发现

无达到缺陷报告标准的问题。未将物理项未执行、golden 比较跳过或纯建议描述为缺陷。

