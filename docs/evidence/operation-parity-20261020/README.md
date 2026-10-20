# 操作一致性整改证据索引（2026-10-20）

本目录是 `docs/engineering/FLUTTER-OPERATION-REMEDIATION-20261020.md`（R01–R16）的实施证据入口。
工作树为 `D:\MyAgent\paraselene-flutter`，所有批次在同一工作树上执行；HEAD 与脏文件状态见各批次文件首部。
真实 Windows 桌面、IME、生产/测试 FFI DLL、外网模型等未执行项在各批次和本索引末尾集中标 NOT_RUN，不宣称通过。

## 批次与文件

| 批次 | 范围 | 证据文件 |
| --- | --- | --- |
| A | R01 保存状态订阅、R02 全宽度保存失败恢复、R04 资料加载身份、R12 搜索作用域/重命名 | `batch-A-B.md` |
| B | R03 宽稿唯一持久状态、R05 纸面/滚动/阅读位置恢复 | `batch-A-B.md` |
| C | R06 线程单活动槽、R07 完整讨论索引与保存错误、R08 选区落点与焦点往返 | `batch-C.md` |
| D | R09 资料查阅/带入/编辑分离、R10 快捷键按焦点/层级、R11 出处四态、R13 工具栏折叠 | `batch-D.md` |
| E | R14 能力/保存/采纳提示真实、§7 验收矩阵映射 | `batch-E.md` |
| F | R15 文档入口整理、R16 文件清理与重建 | `batch-F.md`、`cleanup-manifest.md` |

## R01–R16 状态

| R | 主题 | 状态 | 主要证据 |
| --- | --- | --- | --- |
| R01 | 保存状态订阅 EditingSession | 完成 | `test/operation_parity/save_status_test.dart` |
| R02 | 全宽度保存失败恢复 | 完成 | 同上（宽/窄窗、恢复面板、导出草稿） |
| R03 | 宽稿唯一持久状态 | 完成 | `test/operation_parity/wide_layout_test.dart` |
| R04 | 资料加载 workId+epoch | 完成 | `test/operation_parity/lore_scope_test.dart` |
| R05 | 纸面/滚动单一坐标与恢复 | 完成 | `paper_flow_test.dart`、`scroll_restore_test.dart`、`test/editor/editor_scene_viewport_test.dart` |
| R06 | 线程单活动槽 | 完成 | `test/operation_parity/thread_host_test.dart` |
| R07 | 完整索引与线程保存错误 | 完成 | `test/operation_parity/discussion_index_test.dart` |
| R08 | 选区落点与焦点往返 | 完成 | `test/operation_parity/selection_focus_test.dart` |
| R09 | 资料查阅/带入/编辑分离 | 完成 | `test/operation_parity/reference_flow_test.dart` |
| R10 | 快捷键按焦点/层级 | 完成 | `test/operation_parity/focus_shortcuts_test.dart` |
| R11 | 出处四态 | 完成 | `test/operation_parity/source_state_test.dart`、`test/source_marks_test.dart` |
| R12 | 搜索作用域/重命名文案 | 完成 | `test/writing_features_test.dart`、`lore_scope_test.dart` |
| R13 | 工具栏按空间折叠 | 完成 | `test/operation_parity/toolbar_fold_test.dart`、`test/m2_workbench_test.dart` |
| R14 | 能力/保存/采纳提示真实 | 完成 | `test/operation_parity/capability_notice_test.dart` |
| R15 | 文档入口整理 | 完成 | `batch-F.md` |
| R16 | 文件清理与重建验证 | 完成 | `batch-F.md`、`cleanup-manifest.md`、`bundle-probe/` |

## V01–V28

验收矩阵逐项映射见 `batch-E.md` 的「§7 验收矩阵映射」表：合成/widget 级证据标 PASS；真实 IME、真实 FFI 故障注入、真实外网、真实进程重启/桌面矩阵等标 NOT_RUN，留最终统一门禁。

## 本轮统一命令（apps/desktop）

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test bin
flutter analyze --fatal-infos
flutter test test/operation_parity
flutter test test/editor test/cowrite test/writing_features_test.dart test/m2_workbench_test.dart test/source_marks_test.dart test/m2_locale_test.dart
```

真实 FFI 全量、owned 加密库、Rust、Release、bundle 探针与 Windows integration 的命令见批次 F 和根 `scripts/`。

## 最终统一门禁结果（清理后重建同一构建）\n\n- 生产能力 DLL 全量 Flutter：571 tests PASS（排除 golden 与 owned 专项）；owned test-support：2 tests PASS。\n- `dart format` 168 文件 0 变化；`flutter analyze --fatal-infos` No issues；`flutter gen-l10n` 退出 0。\n- `flutter build windows --release` 退出 0；`scripts/verify-m1-bundle.ps1` PASS（新副本，ProbeExitCode 0、MissingDllExitCode 1）。\n- Windows integration：m1 1 passed、m2 1 passed、m4 2 passed。\n- golden 单独报告：2 failed（既有视觉基线未重批，未执行 --update-goldens）。\n- Rust：源码未改，按 §7.4 NOT_RUN；桥接 debug/test-support/release 已重建。\n\n## NOT_RUN 汇总（最终）

- 真实 Windows 桌面：微软拼音组合/候选/取消、物理键盘 Tab 遍历、200% DPI 窗口矩阵、Alt+F4/关闭失败恢复、系统剪贴板与导出写失败。
- 真实 FFI 故障注入（revision/head/context 冲突）仍用合成失败覆盖；生产 DLL 全量与 test-support owned 已在最终门禁执行。
- 真实外网：模型请求、候选过期票据、请求材料/输出语言变更后的重新预览。
- 净机安装/安装器卸载残留、真实作者数据迁移与接管、多显示器、真实 IME/200% DPI/系统剪贴板；golden 未重批且不得自动 `--update-goldens`。

