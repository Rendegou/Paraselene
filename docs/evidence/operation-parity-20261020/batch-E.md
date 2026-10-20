# 批次 E（R14 能力/保存/采纳提示真实 + §7 验收矩阵）交付记录

工作树：`D:\MyAgent\paraselene-flutter`，HEAD `cb2271778163a0fb98d1ebf4737ade0a0790b619`（未提交）。
依据：`docs/engineering/FLUTTER-OPERATION-REMEDIATION-20261020.md`（批次 E、§7 验收矩阵）。
证据目录：`docs/evidence/operation-parity-20261020/`。真实 Windows/IME/FFI 项在本文件末尾集中标 NOT_RUN。

## R14 能力、保存与采纳提示真实（P1）

实现：
- `apps/desktop/lib/cowrite/discussion_panel.dart`
  - 整章讨论（`target/anchor == null`）或原目标已失效（`valid == false`）时，在状态行下显示固定说明（key `discussion-generation-unavailable`）：只能保留草稿与查看历史，生成预览需要有效选段；生成按钮仍禁用，不伪装整章模型、不自动转全选。
  - 候选区前置“采纳只写编辑稿、可一次撤销、不创建正式版本”的说明（key `candidate-apply-notice`）；采纳失败显示原因（key `candidate-apply-failed`，liveRegion，warning 色）：“候选未写入：正文或原目标已变化，请重新预览后再采纳。”
  - 采纳按钮统一走 `_applyCandidate(operationId)`：调用既有 `workspace.applyCandidate(operationId)`，失败时保留正文/草稿与原候选并显示错误；成功时清除错误，编辑稿通过既有 `preserveEditorHistory` 路径支持一次撤销。
  - `didUpdateWidget` 在线程 id 变化时清除采纳失败状态，避免把上一条线程的错误带到另一条线程。
  - 候选列表只取 `patchStatus == 'pending'` 的行，历史/已拒绝/过期候选不重复提供采纳入口。
- `apps/desktop/lib/l10n/app_zh.arb`、`app_zh_Hans.arb`、`app_en.arb`
  - 新增 `candidateApplyNotice`、`candidateApplyFailed`、`discussionGenerationUnavailable`；改写 `confirmNotice`：Ctrl+S 与自动保存只写编辑稿，确认后创建新的正式版本，编辑稿保留并以新版本为基准。
  - `flutter gen-l10n` 退出 0；三份 ARB 各 319 键、键集一致。
- `apps/desktop/lib/workspace/presentation/workbench_dialogs.dart`：沿用既有 `ConfirmChapterDialog` 展示 `confirmNotice`，无需改代码。

测试：
- 新增 `apps/desktop/test/operation_parity/capability_notice_test.dart`（5 tests，全部通过）：
  1. 整章线程显示生成不可用说明与“生成预览需要有效选段”，生成按钮禁用，草稿仍可编辑；
  2. 采纳提示可见；注入 `revision_conflict` 失败时显示 `candidate-apply-failed`、正文不变、无正式版本；重试成功后失败提示消失、正文仍不变、编辑历史保留且无正式版本；
  3. 自动保存/`flushAll` 不新增正式版本；确认对话框显示“只写编辑稿”语义；确认后版本数 +1；
  4. `prepareGeneration` 不写正文、不新增版本、不自动发送；取消预览只调用取消接口、不发送、正文不变；
  5. 20 万字正文 + 4 条候选连续采纳后正文长度不变、无正式版本；线程草稿 flush 后冷启动（同一合成仓库、新 controller）正文/线程/草稿保留，且未隐式发起生成请求。
- 回归：`flutter test test/operation_parity test/editor test/cowrite test/writing_features_test.dart test/m2_workbench_test.dart test/source_marks_test.dart test/m2_locale_test.dart` → **453 tests All passed**（退出 0）。
- 门禁：`dart format --output=none --set-exit-if-changed lib test integration_test bin` → 168 文件 0 变化（退出 0）；`flutter analyze --fatal-infos` → No issues found（退出 0）。

未测/NOT_RUN：
- 真实 Rust revision_conflict / 目标失效注入（需要真实 FFI 与并发写；本轮用 `WorkspaceFailure('revision_conflict')` 合成故障覆盖 UI 决策，最终门禁再跑真实 DLL 全量）。
- 真实编辑器内“采纳一次后单次 undo”的物理 Ctrl+Z 次数（widget 测试断言 `preserveEditorHistory` 与正文不变，物理键盘 undo 栈留人工复核）。
- 真实外网/云端模型请求、真实候选过期票据、真实请求材料/输出语言变更后的重新预览；真实 IME 与桌面窗口矩阵见下。

## §7 验收矩阵映射（V01–V28）

代码/测试证据均为同一工作树构建；“PASS”指合成/widget 级证据通过，“NOT_RUN（真实桌面）”指真实 Windows 输入、FFI 故障注入、外网等未在本轮执行。

| 验收 | 证据 | 状态 |
| --- | --- | --- |
| V01 保存状态刷新 | `test/operation_parity/save_status_test.dart` ① | PASS |
| V02 保存错误/冲突/基线 | `save_status_test.dart` ②③、`editor_status.dart` 错误码/基线展示 | PASS（真实 Rust 注入 NOT_RUN） |
| V03 窄窗失败恢复/导出 | `save_status_test.dart` ④（360×720、200%、键盘 Enter） | PASS（导出写盘失败/取消 NOT_RUN） |
| V04 等待期间继续输入/退出 | `save_status_test.dart`、`m4_close_controller_test.dart` 既有 drain 覆盖 | PASS |
| V05 宽稿持久化 | `test/operation_parity/wide_layout_test.dart`（A/B 作品、重启恢复） | PASS |
| V06 资料加载身份 | `test/operation_parity/lore_scope_test.dart` 9 tests | PASS |
| V07 纸面连续性 | `test/operation_parity/paper_flow_test.dart`、`test/editor/editor_scene_viewport_test.dart` | PASS |
| V08 滚动恢复/显式跳转 | `test/operation_parity/scroll_restore_test.dart` | PASS（真实重启进程 NOT_RUN） |
| V09 缩放/宽稿/长标题几何 | `paper_flow_test.dart`、`editor_scene_viewport_test.dart`、布局矩阵 | PASS（真实 IME 候选窗 NOT_RUN） |
| V10 单活动槽 | `test/operation_parity/thread_host_test.dart` ①②③ | PASS |
| V11 双标记/失效/索引 | `thread_host_test.dart`、`discussion_index_test.dart` | PASS |
| V12 360 重开讨论索引 | `discussion_index_test.dart` ① | PASS |
| V13 saveThread 失败/重试 | `discussion_index_test.dart` ②③、`test/cowrite/discussion_registry_test.dart` | PASS |
| V14 选区精确创建 | `test/operation_parity/selection_focus_test.dart` ①②⑤ | PASS |
| V15 焦点往返/资料关闭 | `selection_focus_test.dart` ③④、`reference_flow_test.dart` | PASS（真实 LorePicker NOT_RUN） |
| V16 预览/带入/历史快照 | `reference_flow_test.dart` 14 tests | PASS |
| V17 快捷键按焦点 | `test/operation_parity/focus_shortcuts_test.dart` ①② | PASS（真实物理键盘 NOT_RUN） |
| V18 Escape 逐层 | `focus_shortcuts_test.dart` ③④ | PASS |
| V19 微软拼音组合 | — | NOT_RUN（真实 IME） |
| V20 出处四态 | `source_state_test.dart` 5 tests、`test/source_marks_test.dart` 11 tests | PASS（真实 Rust 故障注入 NOT_RUN） |
| V21 历史出处只读 | `source_state_test.dart` ⑤ | PASS |
| V22 搜索/重命名 | `test/writing_features_test.dart`、`lore_scope_test.dart` | PASS |
| V23 折叠/抽屉/可达 | `test/operation_parity/toolbar_fold_test.dart`、`test/m2_workbench_test.dart` 布局矩阵 | PASS（真实 DPI/键盘遍历 NOT_RUN） |
| V24 候选预览/采纳/拒绝 | `capability_notice_test.dart` ②④ | PASS（真实外网/票据过期 NOT_RUN） |
| V25 20 万字冷启动 | `capability_notice_test.dart` ⑤ | PASS（真实进程重启 NOT_RUN） |
| V26 关闭/Alt+F4/导出 | `m4_close_controller_test.dart`、`test/window/**` 既有覆盖 | PASS（真实窗口关闭失败 NOT_RUN） |
| V27 复制/导出不含 UI 占位 | 既有 editor 导出/复制测试 + `paper_flow_test.dart` 单一滚动文本结构 | PASS（真实系统剪贴板 NOT_RUN） |
| V28 清理后重建 | `batch-F.md`（R16）：清理 19,960 文件/11.58 GiB 后离线重建、bundle probe PASS、571+2 tests、m1/m2/m4 integration PASS | PASS |

## 批次 E 未执行项（汇总）

- 真实 Windows 桌面：窗口矩阵物理 DPI、微软拼音候选/取消、Tab 焦点遍历、Alt+F4/关闭失败恢复、系统剪贴板与文件导出写失败。
- 真实 FFI：真实 DLL 全量回归、test-support DLL 的 owned 用例、真实 Rust 故障注入（revision/head/context conflict）与 20 万字真实数据库写入/冷启动。
- 真实外网：模型请求、候选过期票据、请求材料/输出语言变更后的重新预览。
- 以上均列入最终统一门禁或明确 NOT_RUN，不在批次 E 宣称通过。
