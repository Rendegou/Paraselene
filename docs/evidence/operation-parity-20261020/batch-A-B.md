# 操作一致性整改：批次 A、B 交付记录（2026-10-20）

对应 `docs/engineering/FLUTTER-OPERATION-REMEDIATION-20261020.md` 的 R01/R02/R04/R12（批次 A）与 R03/R05（批次 B）。
本轮只使用合成测试材料与合成仓库；未读取作者库、Key 或真实作品，未发送模型请求。

## 工作树与构建环境

- Flutter 工程 HEAD：`cb2271778163a0fb98d1ebf4737ade0a0790b619`（工作树在本轮开始前已有大量未提交改动，本轮不 commit/reset/clean）。
- Flutter 3.32.1 stable，Dart 3.8.1，Windows x64。
- 测试命令均在 `packages` 外的 `apps/desktop` 执行。

## R01：保存状态直接订阅 EditingSession（PASS）

- `lib/workspace/presentation/editor_status.dart`：新增 `SaveStatusIndicator`，用 `ListenableBuilder(Listenable.merge([editing, controller]))` 只重建保存区；状态点/文字仍读 `EditingSession.saveState`，屏障错误读 controller。
- `lib/workspace/presentation/workbench_chrome.dart`：顶栏改用 `SaveStatusIndicator`，保存状态变化不再依赖 controller 通知。
- `lib/workspace/presentation/workbench_dialogs.dart`：`ConfirmChapterDialog` 的编辑监听改为 `controller.editing`。
- 断言：`test/operation_parity/save_status_test.dart` 4 tests（dirty→saving→saved；error；conflict；窄窗恢复面板与键盘重试），保存过程断言 `contentEpoch` 不变、EditorViewport controller 实例不变。

## R02：全宽度保存失败恢复（PASS）

- 顶栏失败点可聚焦，宽窗状态区就地打开恢复面板、窄窗 34×34 图标按钮带语义与 liveRegion；`SaveErrorBanner` 在工具栏与正文之间显示草稿保留、恢复基线、稳定错误码、`durable_save_failed`、重试保存/导出草稿。
- 恢复复用 `controller.retrySave()` 与 `RecoveryExportFlow.run`；导出不接普通版本导出。
- 断言：`save_status_test.dart` 覆盖 1440×900 与 360×720/textScale 2；错误无需 hover 可读；Tab/Enter 可重试；banner 不覆盖正文。

## R04：资料加载身份与竞态（PASS，由 batch-a-sidebar 交付）

- 新增 `lib/workspace/presentation/lore_directory.dart`：workId + request epoch 状态机，旧请求 success/catch/finally 不写新状态，无作品清空，失败显式重试，同作品不重复请求，dispose 后不通知。
- `workbench_sidebar.dart` 接入 LoreDirectory；资料失败显示 `loreReadFailed` + 重试。
- 断言：`test/operation_parity/lore_scope_test.dart` 9 tests（A 挂起→切 B、迟到失败、A→B→A、dispose、请求风暴、重试、无作品）。

## R12：搜索作用域与重命名文案（PASS，由 batch-a-sidebar 交付）

- 章节页签“搜索章节”、资料页签“搜索资料”、作品选择器“搜索作品”；切页签清空旧词，可一键清空；work_picker 增加搜索与空态。
- `showTitlePrompt` 支持用途提交文案（重命名“保存”、新建“创建”）、初值全选、Enter 提交、Escape 取消。
- 新增 ARB 键：`saveAction`、`searchResources`、`noMatchingResources`、`noMatchingWorks`、`loreReadFailed`；三份 ARB 键数 298，en/zh/zh-Hans 一致。
- 断言：`writing_features_test.dart` 9 tests（含重命名全选、搜索作用域、英文 locale）。

## R03：宽稿唯一持久状态（PASS）

- `workbench_screen.dart` 删除局部 `_wide`；顶栏勾选、纸面宽度、切换动作全部读/写 `controller.wide` / `controller.setWide`。
- 断言：`test/operation_parity/wide_layout_test.dart` 2 tests：
  - 版式菜单写入 controller.wide，可读行宽 760→920，`editing.contentEpoch == 1`，同一合成仓库重启后恢复 920；
  - 作品 A 宽稿、作品 B 舒适，切换作品各自恢复。

## R05：连续纸面、滚动与恢复（PASS）

- `editor_viewport.dart`：新增 `documentHeader`/`documentFooter`/`onScrollOffset`/`restoreScrollOffset`/`restoreScrollToken`/`onScrollRestored`；单一 `ScrollPosition` 的文档 extent = 纸面标题 + 正文 + 章末；标题/章末以 `Positioned` 参与同一滚动坐标，正文画布随标题下移；`_ensureCaret` 与 IME 几何按纸面标题高度补偿；恢复在头尾测量与正文 extent 可用后应用并钳制，成功后回调 `markScrollApplied`。
- `manuscript_editor.dart`：删除外层 `SingleChildScrollView` 与未挂接的 `_scroll`；标题/正文/章末全部交给 `EditorViewport`；`onScrollOffset` 接 `noteScrollTop`，恢复接 `pendingScrollTop`/`applyScrollPending`/`contentEpoch`。
- 修复：章末让渡滚动空间时，`prepareViewport` 只作为测量修正量使用，避免把文档偏移钳回正文范围（滚到底章末可见）。
- 断言：
  - `test/operation_parity/paper_flow_test.dart` 2 tests：短章章末紧接正文且不贴窗口底、仅一个 Scrollable；长章标题随纸面滚走、滚到底章末在最后一行之后。
  - `test/operation_parity/scroll_restore_test.dart` 2 tests：长章 420px 关闭重开恢复，缩短正文钳制到 0；作品 A/B 位置不串用。
  - `test/editor/editor_scene_viewport_test.dart` 新增 2 tests：头尾进入同一 extent、滚到底章末贴底、单一 Scrollable；标题下方点击命中第一行正文。

## 命令与退出码

| 命令 | 退出码 | 结果 |
|---|---|---|
| `dart format --output=none --set-exit-if-changed lib test integration_test bin`（批次 A 阶段） | 0 | 无格式差异 |
| `flutter analyze --fatal-infos`（批次 A 阶段） | 0 | 0 issues |
| `flutter test test/operation_parity test/writing_features_test.dart test/m2_workbench_test.dart`（批次 A） | 0 | 317 tests passed |
| `flutter test test/operation_parity test/editor test/cowrite test/writing_features_test.dart test/m4_controller_test.dart test/m4_lifecycle_test.dart test/m2_workbench_test.dart`（批次 B） | 0 | 419 tests passed |
| `flutter test test/operation_parity/paper_flow_test.dart test/operation_parity/scroll_restore_test.dart` | 0 | 4 tests passed |
| `flutter test test/editor/editor_scene_viewport_test.dart` | 0 | 10 tests passed |

## NOT_RUN / 剩余项

- 真实 FFI（生产能力 DLL、test-support DLL owned 套件）、Windows 原生 IME/组字、真实窗口矩阵与 200% 系统缩放未在本批执行。
- `scripts/check-m2-l10n.ps1` 仍因既有 190 个英文键缺 `@description` FAIL（本轮前既存，未修）。
- golden 测试未运行，未更新基线。
- 批次 C（R06/R07/R08）、D、E、F 尚未执行。
