# 操作一致性整改：批次 C（R06、R07、R08）交付记录（2026-10-20）

对应 `docs/engineering/FLUTTER-OPERATION-REMEDIATION-20261020.md` 的 R06（讨论线程单活动槽）、R07（完整讨论索引与线程保存错误）与 R08（选区落点）。
本轮只使用合成仓库与合成正文，未读取作者库、Key 或真实作品，未发送模型请求。

## 工作树与构建环境

- Flutter 工程 HEAD：`cb2271778163a0fb98d1ebf4737ade0a0790b619`（工作树在本轮开始前已有大量未提交改动，本轮不 commit/reset/clean）。
- Flutter 3.32.1 stable，Dart 3.8.1，Windows x64；测试在 `apps/desktop` 执行。

## R06：线程单活动槽、收起与标记（PASS）

### 代码

- `lib/editor/editor_discussion_overlay.dart`：新增 `markerBuilder` 与 `onHostMeasured`；高度 > 0 的槽位用 `Offstage` + `_RenderMeasuredHost`（`RenderProxyBox`）自然测量，测量结果变化 ≥ 0.5 px 才回调，避免 build→measure→setState 循环；高度为 0 的槽位渲染段末 24×24 标记，同一段多个标记向右依次排开，各自独立命中区。
- `lib/editor/editor_viewport.dart`：透传 `discussionMarkerBuilder`/`onThreadHostMeasured`。
- `lib/workspace/presentation/manuscript_editor.dart`：
  - `_syncHosts` 只把“非整章且 anchor 有效”的线程放进槽位；活动线程使用实测高度，其余 `height: 0`；同签名不重复重排；
  - 新增单活动线程状态 `_activeThreadId`（默认不展开）、`_activateThread`（先 `flush` 同步草稿、选中 anchor 区间、滚动露出）、`_collapseActiveThread`（flush、收起、光标落到 anchor.to、焦点回正文）、`_onHostMeasured`（更新高度后再次露出）；
  - 新增段末标记按钮 `thread-marker-open-<id>`，点击展开对应线程；正文代次变化（切章/确认）自动收起并清空高度缓存。
- `lib/cowrite/discussion_panel.dart`：新增可选 `onCollapse`；卡片改为有界 `SingleChildScrollView`（`maxHeight: 420`）避免超长历史撑满纸面；顶部显示冻结引文摘要（≤36 标量）或整章标题、有效/失效状态与草稿提示，并提供“收起”图标按钮；原有草稿/生成/候选/历史逻辑保留。
- `lib/editor/editor_thread_slot.dart`/`editor_layout.dart`：`height: 0` 的宿主仍产生 `threadGeometry`（高度为 0、排在前一宿主底部），不占排版高度；清空槽位后布局高度恢复。

### 断言

`test/operation_parity/thread_host_test.dart`（3 tests）：

1. 三条线程只展开一条，活动槽有高度、其余槽为 0，同段第二个标记仍可点击；点“收起”后布局高度回到基线，三条标记恢复。
2. 在线程 1 输入草稿→切到线程 2，线程 1 草稿已写入 Registry；收起后重新展开草稿仍在；`controller.body` 与视口正文不变。
3. 新建章节后活动卡片消失、线程列表与槽位清空、旧标记消失。

`test/editor/editor_thread_layout_test.dart` 新增 1 test：`height: 0` 宿主不预留空间，布局高度只增加展开高度。

## R08：选区落点与焦点往返（PASS）

### 代码

- `lib/workspace/presentation/manuscript_editor.dart`：
  - 记录最近一次非折叠选区 `_lastSelection`；顶栏/工具栏抢焦点导致选区折叠时，仍按冻结的 UTF-16 区间创建线程；
  - 新增就近轻量入口（选区末端旁 `discuss-selection-inline`，仅选区非折叠时出现，不常驻工具栏）；
  - `_discussSelection` 创建后 `_activateThread(thread, focusDraft: true)`：选中 anchor 区间、展开卡片、滚动露出、焦点进草稿；
  - 忙碌/只读/屏障再次校验；只读期间取消的临时选区先挂起，解锁重绘后折叠到原选区末尾；
  - 收起后焦点回正文、光标折叠在 anchor.to；打开资料对话框再关闭时焦点回讨论草稿（`DiscussionPanel`）。
- `lib/workspace/presentation/discussion_panel.dart`：新增 `autofocusDraft`、`FocusNode _draftFocus`；资料选择返回后 `requestFocus` 回草稿。
- `lib/editor/editor_viewport.dart`：新增 `selectionActionBuilder`（选区末端画布矩形定位）、`onStateReady`、`revealThread`（把展开卡片滚入视口并留 12/24 px 边距）、`headerExtent` 只读测试访问器。
- `lib/editor/editor_input_client.dart`：编辑器失焦（焦点在讨论草稿/菜单）时 `setEditingState` 不调用，只更新本地选区与布局，下次 attach 再同步，修复 `TextInputConnection` 的 `'attached'` 断言。
- `lib/workspace/presentation/workbench_chrome.dart`：讨论按钮启用态加 `!isBusy`；“更多”菜单实时计算能力。

### 断言

`test/operation_parity/selection_focus_test.dart`（5 tests）：

1. 选中 0..4 后模拟工具栏抢焦点使选区折叠，点内联入口仍按 0..4 创建线程，`target.from/to/text` 精确匹配；面板出现、草稿自动获焦、正文与 undo 不变。
2. 长正文滚到底部选段，创建后卡片底部在视口内且 `scroll.offset > 0`。
3. 创建后输入草稿，收起卡片：面板消失、线程与草稿保留、正文获焦、光标折叠在 anchor.to、段末标记仍在。
4. Shift+方向键扩选后出现内联入口，可创建 0..4 线程。
5. 鼠标从首行文字拖拽产生非折叠选区与内联入口；只读屏障下点击不创建线程，解锁后光标折叠到原选区末尾（offset 4）。

## R07：完整讨论索引与线程保存错误（PASS）

### 代码

- `lib/cowrite/discussion_index.dart`：把未使用的旧下拉按钮改为 `showDiscussionIndex(...)` 对话框；标题显示 `讨论记录 · N`，右上角可见关闭按钮、底部关闭；逐条列出本章全部线程（有效、失效、整章），显示冻结引文（≤32 标量）或整章标题、有效/失效状态、未发草稿提示；点击条目先关面板，再把原线程对象交回工作区（按真实 ID 重开，不新建、不按相似句检索）。内容用固有宽度 `Column` + 有界 `SingleChildScrollView`，窄窗 360×720 与 200% 文字下不溢出。
- `lib/workspace/presentation/workbench_chrome.dart`：删除旧的 `PopupMenuButton` + `_ThreadIndexEntry`；顶栏索引入口在宽窗显示文字、窄窗显示图标，所有宽度都能打开同一索引；有未落盘线程草稿时入口叠加 `discussion-unsaved-dot` 角标，不用悬浮提示掩盖保存状态。
- `lib/cowrite/discussion_panel.dart`：订阅 `DiscussionRegistry`，线程写入失败时在卡片内显示 `discussionSaveFailed` 与“重试保存”；整章/失效线程临时对话框显示冻结引文、状态与历史，生成按钮在 `!valid` 时禁用，候选“采纳”在失效线程上禁用；可见收起/关闭按钮由对话框传入。
- `lib/workspace/presentation/manuscript_editor.dart`：临时面板关闭（按钮、Escape、点遮罩）后把焦点还给正文；失效线程不跳旧坐标。
- `lib/workspace/workspace_state.dart` 的 `_drain()` 原本已在导航/退出屏障中循环 `discussions.flush()`，线程脏数据会阻止离开并保留草稿。

### 断言

`test/operation_parity/discussion_index_test.dart`（3 tests，360×720 窗口）：

1. 窄窗顶栏索引列出 3 条线程；未发草稿与“选段已变化”在索引内可见；打开已存在线程不新增线程、ID/草稿不变、仓库行数不变。
2. 失效线程从索引重开为临时面板，显示冻结引文原文、失效原因与历史；Escape 关闭后正文重新获焦，线程与草稿不变。
3. 注入一次线程保存失败：面板显示保存失败与重试；重试成功后同一仓库重建控制器，冷启动读回 3 条线程与原草稿。

## 命令与退出码

| 命令 | 退出码 | 结果 |
|---|---|---|
| `dart format --output=none --set-exit-if-changed lib test integration_test bin` | 0 | 162 文件，无格式差异 |
| `flutter analyze --fatal-infos` | 0 | No issues |
| `flutter test test/operation_parity/thread_host_test.dart` | 0 | 3 tests passed |
| `flutter test test/operation_parity/selection_focus_test.dart` | 0 | 5 tests passed |
| `flutter test test/operation_parity/discussion_index_test.dart` | 0 | 3 tests passed |
| `flutter test test/operation_parity test/editor test/cowrite test/writing_features_test.dart test/m2_workbench_test.dart` | 0 | 409 tests passed |

## NOT_RUN / 剩余项

- `DiscussionPanel` 的“资料对话框关闭后焦点回草稿”因 `LorePicker` 依赖 `RealWorkspaceRepository`，本批只用代码路径审查与 widget 结构验证，未在合成仓库下执行对话框往返；真实 FFI/真实资料库往返列为 NOT_RUN。
- 真实 Windows 鼠标/键盘 IME、真实桌面截图矩阵、200% 系统缩放未在本批执行；golden 未运行、未更新基线。
- 批次 D（R09/R10/R11/R13）、E（R14）、F（R15/R16）尚未执行。
