# 独立收尾复核 · 2026-10-21

复核对象为当前工作树的现行前端规范与自有 Flutter/Dart 实现。审查起点提交为 `b1f9c43`，启动时 `git status --short` 只有 8 张既有 golden 失败图；`before-git-status.txt` 用于区分更早已有的修改。本审查只写本文档，不改生产代码、生成代码、Rust 或 golden。

## 方法与边界

- 读取 `AGENTS.md`、`docs/engineering/frontend-standards.md`、`DESIGN.md`、`docs/progress.md`、本目录 README、统一检查脚本和 AST 负向测试。
- 沿工作区持久化屏障、编辑器/讨论/出处生命周期及辅助弹窗读取实现，核对迟到响应、失败恢复和释放所有权。
- 查看 `build/ui-completion-20261021/contact-large-final.png`、`settings-680-2.png`、`lore-library-680-2.png`、`memory-680-2.png`。它们是已有 widget 截图，不是本次重新采集或真实 Windows 验收。
- 只使用文件读取、`rg`、Git 只读命令与图片查看；未运行 Flutter、测试、构建、FFI 或原生系统矩阵。下列问题首先来自静态执行路径，不能据此声称已执行回归。

## 发现

### P2：设置弹窗关闭后，迟到回调仍访问已经释放的输入控制器

原位置：`D:\MyAgent\paraselene-flutter\apps\desktop\lib\cowrite\deepseek_settings.dart:84`、`:91`、`:105`。

触发：保存或删除设置时，`setKey` / `setCloudEnabled` / `deleteKey` 尚未完成，作者通过遮罩或 Escape 关闭弹窗。该弹窗没有阻止路由关闭；`dispose()` 释放 `_key`，后续 `_save()` / `_delete()` 仍无 mounted 守卫调用 `_key.clear()`。`_save` 的 finally 再次 clear，可能让 disposed-controller 错误逃出原有 catch。F10/F11 要求 await 后重新检查生命周期，当前静态门禁不会发现 TextEditingController 的此类访问。

建议：await 前冻结输入；控制器访问仅在仍 mounted 时执行，释放时由 dispose 清空。用 gated fake 覆盖保存成功/失败、删除期间关闭，再确认没有未处理错误或误关其他路由。无需真实凭据。

修复静态复核：当前 `deepseek_settings.dart:97` 的 `_apply` 统一等待写入，并在 `:119` 仅对仍 mounted 的控制器清空/更新；保存参数在 await 前冻结，成功关闭也检查原 route。原访问已释放控制器的路径在代码层面已消除。已读取新增 gated fake 测试，覆盖四个等待阶段 × 成功/失败 × Escape/外点，以及保留弹窗时的失败/删除状态；本审查尚未取得执行结果。

### P2：版本读取异常被永久显示成加载中

原位置：`D:\MyAgent\paraselene-flutter\apps\desktop\lib\workspace\presentation\workbench_dialogs.dart:328`—`:333`。

触发：`controller.listVersions()` 抛出仓库/存储错误。`FutureBuilder` 只检查 `snapshot.data == null`，失败快照因此一直返回 `LinearProgressIndicator`；没有失败说明与重试入口，违反 F09。`_versions` 是 late final，也不能由就地重试重新发起读取。

建议：以连接状态和 hasError 区分 loading/error/empty/content，提供稳定本地化失败文案和可替换 future 的重试动作；保留关闭和既有回滚行为。

修复静态复核：版本实现迁至 `D:\MyAgent\paraselene-flutter\apps\desktop\lib\workspace\presentation\version_history_dialog.dart`；`:134` 显式处理错误，`:49` 可以更换 future 重试，查询/回滚保留打开时的作品章节身份并检查 route。原永久加载路径在代码层面已消除。已读取新增四态、重试、目标切换和迟到回滚测试；本审查尚未取得执行结果。

### P2：出处菜单与失败恢复入口未继承共享命中几何

位置：`D:\MyAgent\paraselene-flutter\apps\desktop\lib\workspace\presentation\manuscript_source_widgets.dart:45`—`:57`、`:93`—`:101`。

触发：纸面元信息显示正常出处菜单或出处读取失败。菜单的 `PopupMenuButton.child` 是裸 12px Text，未传 padded tapTargetSize；本机 Flutter `popup_menu.dart:1670`—`:1690` 的 child 分支默认 shrinkWrap，不会自动补齐 48px 命中。重试入口是 InkWell + 上下各 2px Padding，亦没有共享控件的最小命中或局部焦点轮廓。以当前 12px/1.6 样式推导，常规高度约 19px/23px；这是样式推导，尚未实测。

这些入口属于菜单与失败恢复，DESIGN 的选区浮动动作/24px 段末标记例外不涵盖它们。现有 `source_state_test.dart` 只检查存在并点击中心，不能证明 F05/DESIGN 的几何合同。

建议：菜单明确消费共享状态样式和 padded 命中；重试采用共享 TextButton。新增常规/200% 的真实命中、焦点轮廓与几何稳定性断言，并保留现有四态行为测试。

修复静态复核（2026-10-22）：重试已换共享 TextButton；出处及顶栏菜单均改用原生 `icon` 分支，组合标签仍由共享 ButtonStyle 管理 side/overlay/tapTargetSize。出处文字不再显式覆盖前景色，禁用时继承原生按钮颜色。本机 SDK 的 `PopupMenuButton(child:...)` 只消费 tapTargetSize 的陷阱已避开，新增 AST 规则与正反向样本禁止再次使用该分支。实际几何/键盘回归以接续验证为准。

## 规范消歧

`D:\MyAgent\paraselene-flutter\docs\engineering\frontend-standards.md:52` 的 F14 整体引用旧中文注释规范。所引 `comment-style-20261020.md:53` / `:54` / `:62` 仍含原注释专项的“禁止修改逻辑、字符串、资源”、不触碰生成目录和“确认只有注释变化”。现行权威顺序已经说明历史文档不能覆盖当前规则，但 F14 的显式引用仍容易把旧任务操作边界带回当前工程。

建议明确仅沿用注释风格、文件职责和公开契约说明，旧注释专项的操作范围与验收不约束一般编码任务。正常生成与 freshness 校验仍遵守现行 F13。

静态复核：当前 F14 已明确仅沿用风格与契约，旧专项操作边界不限制一般功能修正或官方代码生成；上述歧义已消除。

## 其他判断

- 现行规范清楚分开 AST/普通回归、golden 比较、widget 截图和真实 Windows 系统矩阵；本目录 README 的 `SelectedChecksStatus=PASS` / `OverallStatus=PARTIAL` 以及原生 NOT_RUN 表述没有伪称全产品通过。
- 工作区 state/cowrite/close、编辑器 clipboard/frontier、synthetic_confirmation 的现有 part 各有状态、生命周期或合同职责。本次未见仅凭 part 碎片拆文件绕过长度门禁的证据，不建议无理由禁用语言功能。
- `EditorViewportState` 的公开类型及 scene/scroll/painters 接缝在前一提交已存在；生产表面现在消费绑定和帧，不直接写 State 字段。没有发现当前调用点借这些接缝写入错误身份的具体路径，不能仅凭类公开就报告运行时缺陷。
- 除上述项目，所读取范围内未发现其他有直接触发证据的 P1/P2。本判断不代替尚未执行的原生验收，也不把既有通过记录当作之后工作树自动通过。

## 2026-10-22 接续独立复核

本节由新的只读 reviewer 复核当前未提交源码、规范、脚本与已有执行日志。只修改本报告，未运行 Flutter、构建、FFI 或真实系统操作。前述 2026-10-21 触发证据保留，不把旧工作树通过记录覆盖为本次结论。

- `DeepSeekSettings._apply` 在 await 前冻结提交参数，控制器清空/状态更新仅在 mounted 时执行，关闭检查原 route；未再发现原 disposed-controller 路径。`VersionsDialog` 对查询和回滚冻结 controller/work/chapter 身份，明确四态与重试，失败不关闭；`_retry` 当前采用无返回值的同步 setState block。控制器查询在调用时即捕获作品/章节，回滚屏障拒绝重入，未发现新的跨作品写入路径。
- `toolbar_layout.dart` 按当前译文、缩放、选区/线程能力计算动作宽度，并把 `SaveStatusSnapshot` 的真实文案宽度纳入预留空间；`ToolbarRow` 同时订阅 editing，保存状态变化能触发重新折叠。标题的完整文字仍由 Text/tooltip 保留。先前提醒的英文冲突长文案风险已有对应实现处理，仍须读取 1040/1060 边界回归结果，不能仅凭计算认定全部布局通过。
- 所有本次调整的菜单已走 M3 IconButton → ButtonStyleButton，实际消费共享焦点边框/叠色/命中；`menuTrigger` 的零外层 padding 和标签最小40px布局保留原有角色。检查未发现组合标签被强制塞入18px方框的路径。
- `sources-editor-focus-before.txt` 已直接证明：出处按钮取得 primaryFocus 后，Enter 在正文首部插入换行。当前 `EditorViewportState._key` 首先要求自身 hasPrimaryFocus，再处理正文输入/导航；嵌入控件的冒泡事件会交还其原生 Actions。这与 F08 的按键归属要求一致，不改变作者文本或 IME 的独立输入通道。
- freshness 脚本使用缓存官方生成器，在独立项目按原始字节复制输入、校验路径全集和文件字节，并核对原工程前后 hash；缺工具返回3，默认门禁把该结果记为所选 NOT_RUN。AST 新菜单规则有显式/隐式、泛型和前缀正反向样本。未发现当前配置可导致原工程生成物被写回的执行路径。

执行证据状态：已读取 `detail-regressions-after.txt`，该轮为40项通过、1项失败；剩余失败是版本重试用例结束时仍有 `setWide(false)` 创建的350ms合成偏好计时器。当前测试已补400ms模拟时钟推进，最终复跑尚待主任务记录。该旧失败日志不能视作最终全量 PASS；本节也不替代主任务将要运行的统一门禁、截图或原生验收。

阶段性静态结论：上述第一轮读取未再发现具有直接触发证据的未修复 P1/P2；随后增加的回滚失败反馈定向复核发现下项缺口，不能沿用第一轮结论宣称审查全部完成。

### 追加 P2：版本回滚失败后，当前弹窗没有操作失败反馈

触发：在版本列表展开历史版本，确认回滚，仓库抛出 `WorkspaceFailure`（现有合成 fixture 的 `failRollback` 即可触发）。`WorkspaceController._barrier` 捕获错误后只写 `_errorCode` 并返回 false；`VersionsDialog._rollback` 仅处理 true，false 时没有本地状态或提示。`_VersionHistoryContent` 仍展示已成功读取的版本列表，只更新 canRollback，不消费控制器错误码。

底层工作台的 SaveErrorBanner 会响应 errorCode，但它属于模态路由之后的页面，处于遮罩下，操作和焦点均不可达；当前弹窗内没有任何失败文案或稳定错误码。作者只能看到确认框关闭、版本列表保留，无法从操作上下文得知回滚失败。既有 `rollback failure stays open` 只验证弹窗仍打开，不能证明 F09 的失败反馈已履行。

建议：把本次回滚失败码保存在弹窗操作状态，在仍 mounted、身份有效时显示本地 liveRegion 提示；保留版本列表与回滚入口供再次确认重试。可使用既有本地化 errorCode 包装和稳定 fallback，无需新增作者数据、模型请求或生成物手改。新增失败提示可见、保留正文/版本、重试成功和迟到结果不误关其他路由的回归。

修复复核：当前 `_rollback` 在 mounted 和原 controller/work/chapter 身份仍有效时，将控制器稳定错误码或 `versions_rollback_failed` 保存到弹窗局部状态。`_VersionHistoryView` 在版本列表上方使用 liveRegion 显示错误，保留版本内容和回滚入口；再次确认尝试后清旧错误。route 的 isCurrent 检查仅保护成功 pop，失败可在覆盖路由期间记录，返回原弹窗时仍可见，不会因 route 暂时被覆盖而丢失反馈。没有再发现原“失败只留在背景错误条”的路径。

已读取 `rollback-feedback-before.txt`：新增可见性断言精确失败，弹窗内找不到 `synthetic_rollback_failed`。已读取修复后 `rollback-feedback-after.txt`：版本弹窗9项全部通过，覆盖局部错误可见、原文不变、再次确认重试成功及既有身份/迟到成功守卫。此后较新路由用例增加成功/失败参数化，版本测试共10项；新增失败覆盖用例的执行结果等待最终完整门禁，不能由9项旧结果继承为 PASS。

同轮静态复核还确认 AST 规则在分割泛型参数后才提取构造器名称，新增 `new PopupMenuButton<m.Locale>` 等反例，避免类型参数中的前缀点号干扰菜单名称识别。

本次定向静态复核结论：回滚反馈 P2 的原执行路径已修正；当前读取范围未发现新增有直接触发证据的未修复 P1/P2。最终交付仍以主任务正在运行的当前源码统一门禁结果为准，本 reviewer 未运行 Flutter 或原生验收。

## 最终证据核对（2026-10-22）

本 reviewer 只读取主任务产生的最终证据，未亲自运行 Flutter、测试、构建、FFI 或原生系统操作。源码已由主任务冻结。本节记录最终工作树的实际结果，前述失败/待复跑段落保留为问题发现过程，不能替代本节的当前结果。

报告目录 `detail-final-reviewed/`，RunId 为 `c0fa6dc4fa8047acb8fd21e47156a1ff`。已读取 `summary.json`，其中全部所选检查退出0，`SelectedChecksStatus=PASS`；`OverallStatus=PARTIAL`，明确保留可选与物理验收边界。

| 核对内容 | 直接读取的结果 |
| --- | --- |
| AST 全量 | `metrics.json`：141个自有生产文件，0违规 |
| 门禁工具正反向测试 | `gate-negative-tests.txt`：22项全部通过，包括菜单状态分支规则 |
| 普通生产 DLL 回归 | `regression-production.txt`：676项全部通过；尾部明确包括回滚失败反馈、成功/失败不误关较新路由的参数化用例 |
| owned 专项 | `regression-owned.txt`：2项全部通过 |
| 静态、本地化与构建 | summary 记录 ARB、l10n freshness、应用/文本/工具格式和分析、text tests、Windows Release 全部 PASS/0 |
| 独立复制包 | `bundle/copied-bundle-status.json`：PASS，probe退出0、缺DLL退出1、移除SDK PATH；副本标识 `m1-distribution-a2f232fba00a4139933632c793240f8e` |
| 窄窗截图回归 | `narrow-visual-capture.txt`：1项通过，phase为 `standards-narrow-final-20261022`，记录共享按钮命中高度50px及最小32px样式；它不等于 golden 比较或全部页面视觉组合验收 |

golden 比较在最终门禁中仍为 SKIPPED；本 reviewer 未读取/比对 golden 哈希，保留情况由主任务另外核对。真实 IME、物理 DPI/多屏、屏幕阅读器和净机安装均仍 NOT_RUN，不得从以上自动结果继承为 PASS。

最终独立结论：已读取的当前源码与对应最终证据支持本次修复的所选自动检查通过；未发现尚未处理的实质 P1/P2。本结论限定于本报告读取范围及明确列出的自动验收，不声称全产品或原生系统矩阵完成。
