# 批次 D（R09、R10、R11、R13）交付记录

工作树：`D:\MyAgent\paraselene-flutter`，HEAD `cb2271778163a0fb98d1ebf4737ade0a0790b619`（未提交）。
依据：`docs/engineering/FLUTTER-OPERATION-REMEDIATION-20261020.md`（批次 D）。
证据目录：`docs/evidence/operation-parity-20261020/`；本文件随批次 D 任务逐项追加。

## R10 快捷键按焦点/层级（P1）

实现：
- `apps/desktop/lib/workspace/presentation/manuscript_editor.dart`
  - 新增 `_focusedEditable()`：从 `FocusManager.instance.primaryFocus` 向上查找 `EditableText`，返回 `(editable, composing)`；组字中的任何输入框都先把按键交还 IME。
  - `_globalKey` 增加路由门控：`ModalRoute.of(context)?.isCurrent != true` 时直接忽略，浮动菜单/对话框之上的窗口级快捷键与层级退出不越过最内层。
  - Escape 逐层退出：已打开查找 → 关闭查找；已展开讨论 → 收起讨论；否则调用 `onExitFocus` 退出专注；每层只退一层，无对应层返回未处理。
  - Ctrl+F/Ctrl+S 在其他可编辑输入框（重命名、资料编辑、讨论草稿、查找输入）内不再抢占；正文范围仍打开/聚焦查找、触发 `flushAll`。
  - `ManuscriptEditor` 新增 `onExitFocus`（专注模式最外层退出回调）。
- `apps/desktop/lib/workspace/presentation/workbench_content.dart`、`workbench_screen.dart`：透传 `onExitFocus`，仅在 `_focus` 时提供。
- `apps/desktop/lib/workspace/presentation/workbench_chrome.dart`：`_moreMenu` 的 `workspaceToolItems(...)` 移入 `itemBuilder`，菜单打开时按最新 actions/选区能力计算启用态，不沿用上一帧缓存。

测试：
- 新增 `apps/desktop/test/operation_parity/focus_shortcuts_test.dart`（4 tests）：
  1. 正文 `Ctrl+F` 打开查找、Escape 关闭并回正文，正文未重置；
  2. 重命名对话框内 `Ctrl+F`/`Ctrl+S` 不打开查找、不越过最内层保存，Escape 只关对话框，随后防抖保存仍完成；
  3. 已展开段下讨论按 Escape 收起一层，线程/标记/草稿保留，焦点回正文；
  4. 专注模式下先 Escape 关查找、再 Escape 退出专注（侧栏恢复）。
- 回归：`flutter test test/operation_parity test/editor test/cowrite test/writing_features_test.dart test/m2_workbench_test.dart` → 413 tests，All tests passed（退出 0）。
- 门禁：`dart format --output=none --set-exit-if-changed lib test integration_test bin` → 163 文件 0 变化（退出 0）；`flutter analyze --fatal-infos` → No issues found。

未测/NOT_RUN：
- 真实微软拼音候选确认/取消、真实窗口物理键盘、SendKeys/SendInput 自动化路径；真实 Windows IME 下“组字中快捷键交还 IME”仍需人工复核。
- Ctrl+Z/Ctrl+Y 在正文与输入框中的控件级 undo 行为未新增断言（沿用现有 `editor_input_client_test.dart` 覆盖）。
- R09/R11/R13 本文件后续追加。

## R09 资料查阅/带入/编辑分离（P2，队友 batch-a-sidebar 实施）

实现：
- 新增 `apps/desktop/lib/workspace/presentation/lore_preview.dart`：只读预览卡（宽窗右侧临时卡、窄窗居中面板复用同一内容）、`loreRowById`/`LorePreviewData.fromRow` 条目定位、`loreRequestSnapshots` 提交时引用快照、`attachLoreReference`/`removeLoreReference`（复用 registry 的整章规则与 32 项上限）。
- `apps/desktop/lib/workspace/presentation/workbench_sidebar.dart`：资料行携带 entry ID 打开预览；条目在刷新后缺失时提示并返回，不选其他条目冒充；总入口仍打开资料库列表；预览提供“关闭/带入讨论/移除引用/展开编辑”。
- `apps/desktop/lib/lore/lore_library.dart`：新增 `editInitialEntry`，从预览“展开编辑”直接进入既有的 `LoreEditDialog` 编辑与确认链，不重建工作台。
- 预览本身不写库、不发起模型上下文，只有明确点“带入讨论”才走既有引用接口；无章节/无线程、超上限、成功边界均有本地化提示；“历史请求中的引用（提交时快照）”与“当前资料内容”分开展示。
- 三份 ARB 各新增 14 键（`loreGroupTimeline`、`loreGroupTaboo`、`loreGroupStyle`、`attachToDiscussion`、`removeReference`、`expandLoreEdit`、`lorePreviewHint`、`loreAttachedBoundary`、`loreAttachUnavailable`、`loreAttachLimit`、`loreEntryMissing`、`historyReferences`、`viewCurrentLore`、`currentLoreContent`）。

测试：
- 新增 `apps/desktop/test/operation_parity/reference_flow_test.dart`（14 tests）：条目定位纯函数、预览后 attached 不变、带入仅加指定条目且可移除、A/B 线程引用互不串、修改资料后旧请求快照不变、长章中部查阅返回滚动/选区/一次 undo 延续、窄窗无溢出、中英文案。
- 回归：`flutter test test/writing_features_test.dart test/operation_parity/lore_scope_test.dart` → 18 tests（退出 0）。

未测/NOT_RUN：侧栏资料行点击的真实集成（合成仓库不实现 LoreHost，测试内资料页签无行；已用纯函数 + 组件级 + registry 级覆盖，行 onTap 到预览仅静态核对）；真实 FFI/桌面手测留最终门禁。

## R11 出处四态（P2）

实现：
- `apps/desktop/lib/lore/source_mark_controller.dart`：新增 `SourceMarkHost` 接口（`SourceMarkRepository get sourceMarks`）与 `SourceMarkState { loading, error, empty, content }`；控制器记录 `loading/loaded/failed`，`stateFor(work,chapter,head,body)` 按实际读取状态与 `visible` 结果判定四态；失败与迟到响应仍按 work/document/head/body/epoch 校验，不发布旧装饰。
- `apps/desktop/lib/workspace/presentation/editor_source_menu.dart`：新增 `loading` 参数；加载中显示 spinner 与“出处加载中…”，内容态显示菜单与提示，失败态显示“出处未能加载，请刷新后重试。”，空态显示“本章暂无出处”；加载中隐藏刷新按钮。
- `apps/desktop/lib/workspace/presentation/manuscript_editor.dart`：出处加载器改为 `RealWorkspaceRepository.lore` 或测试用 `SourceMarkHost.sourceMarks`；标题元信息行常驻四态入口（`source-marks-loading/retry/empty/menu`），失败可点击重试；关联资料打不开时在元信息下显示“关联资料未能打开，请重试。”与重试入口（`source-open-retry`），正文仍可写；历史出处继续只读展示且禁用跳转到当前正文。
- 三份 ARB 各新增 4 键：`sourceMarksLoading`、`sourceMarksEmpty`、`sourceOpenFailed`、`sourceOpenRetry`；`flutter gen-l10n` 退出 0，三份 ARB 键集一致（316 键）。

测试：
- 新增 `apps/desktop/test/operation_parity/source_state_test.dart`（5 tests）：加载中→空态且正文可写；失败显式提示并重试恢复；旧章节迟到响应不装饰当前正文；菜单/空态/失败态文案互斥；历史出处显示记录版本原文且跳转被禁用。
- 扩展 `apps/desktop/test/source_marks_test.dart`：新增“四态分离”断言（加载中→空→内容→失败→重试回加载中→内容），共 11 tests 通过。
- 回归：`flutter test test/operation_parity test/editor test/cowrite test/writing_features_test.dart test/m2_workbench_test.dart test/source_marks_test.dart` → 443 tests，All tests passed（退出 0）。
- 门禁：`dart format --output=none --set-exit-if-changed lib test integration_test bin` → 166 文件 0 变化（退出 0）；`flutter analyze --fatal-infos` → No issues found。

未测/NOT_RUN：真实 Rust 出处读取故障注入、真实 FFI 下旧 head 迟到响应、Windows 桌面 IME 与点击命中；真实 `source_marks_real_ffi_test.dart` 未在 R11 单独重跑（最终门禁统一执行）。

## R13 工具栏按空间折叠（P2）

实现：
- `apps/desktop/lib/workspace/presentation/workbench_chrome.dart`：顶栏继续按实际 `constraints.maxWidth` 与 `MediaQuery.textScaler` 分层——`compact` 隐藏低频按钮文字、`narrow` 只保留查找/讨论/讨论记录/更多图标入口；章节与版本、模型设置、版式、专注、章节讨论、导出、界面语言在窄窗统一收进“更多”菜单，窄窗菜单额外包含讨论这段、章节讨论、确认本章、确认版本、舒适/宽稿、专注、导出与中英切换，低频工具（资料/出处/RPG/摘要/记忆/导入/旧想法/练习/人物/备份/模型）仍按 capacities 计算启用态，未删除任何功能入口。
- `_BarButton` 增加 `Semantics(label, button, enabled)`（Tooltip 排除语义避免重复朗读）、键盘可聚焦（`canRequestFocus`）与焦点底色；视觉高度由 34 提升到 40，`_BarMenu` 同步 40，保证鼠标/触控目标且不撑破 56px 顶栏。
- 保存失败仍由顶栏状态图标（warning + 语义标签）与工具条下方 `SaveErrorBanner` 双重呈现，不依赖颜色或悬浮提示；窄窗错误入口点击打开恢复面板。

测试：
- 新增 `apps/desktop/test/operation_parity/toolbar_fold_test.dart`（4 tests）：
  1. 布局矩阵（360×720 / 600×800 / 900×700 / 1440×900 / 1920×1080 × 中英 × 100%/200%）无溢出，查找正文、更多与保存状态入口始终存在；
  2. 360×720/200% 下不常驻低频按钮，打开“更多”后确认/版本/版式/专注/导出/中英全部可达；
  3. 顶栏图标按钮有语义名与 ≥40px 目标高度；
  4. 合成仓库下模型设置入口可见但语义标记禁用，不静默消失。
- 回归：`flutter test test/operation_parity test/editor test/cowrite test/writing_features_test.dart test/m2_workbench_test.dart test/source_marks_test.dart` → 447 tests，All tests passed（退出 0）。
- 门禁：`dart format --output=none --set-exit-if-changed lib test integration_test bin` → 167 文件 0 变化（退出 0）；`flutter analyze --fatal-infos` → No issues found。

未测/NOT_RUN：
- 真实 Windows 桌面 200% DPI、真实微软拼音、物理键盘 Tab 遍历与悬浮提示；窄窗“更多”中的工作区工具在合成仓库下不出现（`workspaceToolItems` 仅真实资料库返回），真实 FFI 环境需人工复核全部工具可达。
- 窗口 360×720 最小尺寸下的真实拖动/点击命中；净机安装与多显示器未执行。
